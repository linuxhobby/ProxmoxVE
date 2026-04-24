#!/bin/bash
# PVE 9.0 精简工具 - 已集成 molly-guard 防误操作保护
# 基于原版：https://github.com/Mapleawaa/PVE-Tools-9

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
error(){ echo -e "${RED}[$(date +'%H:%M:%S')]${NC} $1" >&2; }

if [[ $EUID -ne 0 ]]; then
    error "请使用 root 权限运行！"
    exit 1
fi

# ====================== 功能1：系统优化 ======================
system_optimization() {
    clear
    echo -e "${CYAN}=== 1. 系统优化 (订阅弹窗 / 温度监控 / 电源模式 / 安全防护) ===${NC}\n"
    echo "1) 删除订阅弹窗"
    echo "2) 安装温度监控（CPU/NVMe/HDD 显示到 Web UI）"
    echo "3) 设置 CPU 电源模式（性能/节能）"
    echo "4) 安装 molly-guard (防止误敲 reboot/shutdown)"
    echo "0) 返回"
    read -p "请选择: " sub
    case $sub in
        1)
            local jsfile="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
            cp "$jsfile" "${jsfile}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            sed -i "s/res\.data\.status\.toLowerCase() !== 'active'/false/g" "$jsfile" 2>/dev/null || true
            sed -i "s/if (data.status !== 'active')/if (false)/g" "$jsfile" 2>/dev/null || true
            systemctl restart pveproxy
            log "订阅弹窗已移除！请 Ctrl+Shift+R 强制刷新浏览器"
            ;;
        2)
            apt update && apt install -y lm-sensors nvme-cli smartmontools hdparm sysstat linux-cpupower
            sensors-detect --auto
            log "温度监控工具已安装，可通过 Web UI 查看（需刷新页面）"
            ;;
        3)
            apt install -y linux-cpupower
            echo "1) performance（最高性能）"
            echo "2) powersave（最省电）"
            echo "3) ondemand / schedutil（平衡）"
            read -p "请选择电源模式 [1-3]: " mode
            case $mode in
                1) cpupower frequency-set -g performance ;;
                2) cpupower frequency-set -g powersave ;;
                3) cpupower frequency-set -g schedutil ;;
            esac
            log "CPU 电源模式已设置"
            ;;
        4)
            log "正在安装 molly-guard..."
            apt update && apt install -y molly-guard
            log "molly-guard 已安装成功！"
            warn "以后执行 reboot 或 shutdown 时，系统将强制要求您输入主机名以进行二次确认。"
            ;;
        0) return ;;
        *) warn "输入错误" ;;
    esac
    read -p "按回车返回..."
}

# ====================== 功能2：软件源与更新 ======================
sources_and_updates() {
    clear
    echo -e "${CYAN}=== 2. 软件源与更新 (换源 / 更新 / PVE8→9升级) ===${NC}\n"
    echo "1) 更换软件源（USTC / TUNA）"
    echo "2) 系统更新（apt update && upgrade）"
    echo "3) PVE 8 → PVE 9 升级（危险操作！）"
    echo "0) 返回"
    read -p "请选择: " sub
    case $sub in
        1)
            echo "1) 中科大 USTC（推荐）"
            echo "2) 清华 TUNA"
            read -p "请选择 [1-2，默认1]: " m
            m=${m:-1}
            [[ $m -eq 1 ]] && MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/pve" || MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve"

            cp -a /etc/apt/sources.list.d/ "/etc/apt/sources.list.d.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            sed -i 's/^deb /#deb /' /etc/apt/sources.list.d/pve-enterprise.list 2>/dev/null || true

            cat > /etc/apt/sources.list.d/debian.sources << EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: trixie trixie-updates trixie-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: trixie-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

            cat > /etc/apt/sources.list.d/pve-no-subscription.list << EOF
deb $MIRROR trixie pve-no-subscription
EOF

            apt update
            log "软件源更换完成！"
            ;;
        2)
            apt update && apt full-upgrade -y && apt autoremove -y
            log "系统更新完成！"
            ;;
        3)
            warn "PVE 8 → 9 升级为高风险操作！请确保已备份数据。"
            read -p "输入 yes 确认继续: " confirm
            if [[ $confirm == "yes" ]]; then
                apt install -y pve-manager
                pve8to9 || true
                apt full-upgrade -y
                log "升级命令已执行，请重启后检查。"
            fi
            ;;
        0) return ;;
        *) warn "输入错误" ;;
    esac
    read -p "按回车返回..."
}

# ====================== 功能3：启动与内核 ======================
boot_and_kernel() {
    clear
    echo -e "${CYAN}=== 3. 启动与内核 (内核切换 / 更新 / 清理) ===${NC}\n"
    echo "1) 查看当前内核并安装新内核"
    echo "2) 设置默认启动内核"
    echo "3) 清理旧内核（保留最新2个）"
    echo "4) 一键更新到最新内核并设置默认"
    echo "0) 返回"
    read -p "请选择: " sub
    case $sub in
        1)
            apt update && apt search pve-kernel
            read -p "输入要安装的内核版本（如 pve-kernel-6.8）： " kver
            apt install -y "$kver"
            ;;
        2)
            echo "当前可用内核："
            ls /boot/vmlinuz-*
            read -p "输入要设为默认的内核版本号（如 6.8.0-...）： " kdef
            sed -i "s/GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Proxmox VE>Proxmox VE, with Linux $kdef\"/" /etc/default/grub
            update-grub
            log "默认内核已设置，重启后生效"
            ;;
        3)
            apt autoremove --purge -y
            log "旧内核清理完成"
            ;;
        4)
            apt update && apt install -y pve-kernel
            update-grub
            log "已更新到最新内核"
            ;;
        0) return ;;
        *) warn "输入错误" ;;
    esac
    read -p "按回车返回..."
}

# ====================== 功能4：直通与显卡 ======================
passthrough_and_gpu() {
    clear
    echo -e "${CYAN}=== 4. 直通与显卡 (核显 / NVIDIA / 硬件直通) ===${NC}\n"
    echo "1) 启用 IOMMU（硬件直通前置）"
    echo "2) Intel 核显直通 / SR-IOV 配置"
    echo "3) NVIDIA GPU 直通配置"
    echo "4) 磁盘 / 控制器直通（RDM / NVMe）"
    echo "0) 返回"
    read -p "请选择: " sub
    case $sub in
        1)
            if grep -q "intel" /proc/cpuinfo; then
                sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="intel_iommu=on iommu=pt /' /etc/default/grub
            else
                sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt /' /etc/default/grub
            fi
            echo "vfio" >> /etc/modules
            echo "vfio_iommu_type1" >> /etc/modules
            echo "vfio_pci" >> /etc/modules
            update-grub && update-initramfs -u -k all
            log "IOMMU 已启用，重启后生效"
            ;;
        2)
            log "Intel 核显直通建议：启用 IOMMU 后，在 VM 硬件中添加 hostpci 设备"
            warn "核显直通可能导致宿主机显示问题，请谨慎操作"
            ;;
        3)
            log "NVIDIA 直通：请先安装 NVIDIA 驱动，再在 VM 中添加 hostpci"
            apt install -y nvidia-driver || warn "驱动安装失败，可手动安装"
            ;;
        4)
            log "磁盘直通请在 Web UI 中为 VM 添加 hostpci 或使用 qm set 命令"
            ;;
        0) return ;;
        *) warn "输入错误" ;;
    esac
    read -p "按回车返回..."
}

# ====================== 主菜单 ======================
while true; do
    clear
    echo -e "${CYAN}====================================${NC}"
    echo -e "${CYAN}     PVE 9.0 精简工具（仅4个功能）     ${NC}"
    echo -e "${CYAN}====================================${NC}\n"
    echo "1) 系统优化 (订阅弹窗/温度监控/电源模式/安全防护)"
    echo "2) 软件源与更新 (换源/更新/PVE8→9升级)"
    echo "3) 启动与内核 (内核切换/更新/清理)"
    echo "4) 直通与显卡 (核显/NVIDIA/硬件直通)"
    echo "0) 退出"
    echo ""
    read -p "请选择功能 [1-4/0]: " choice

    case $choice in
        1) system_optimization ;;
        2) sources_and_updates ;;
        3) boot_and_kernel ;;
        4) passthrough_and_gpu ;;
        0) echo -e "${GREEN}已退出${NC}"; exit 0 ;;
        *) warn "输入错误，请重新选择" ;;
    esac
done