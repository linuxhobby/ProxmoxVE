#!/bin/bash
# ==============================================================
#  Linux Tools 整合脚本
#  功能整合：Debian 13 初始化 + Tailscale 高级管理 + PVE 9.0 精简工具
#  作者：MARCO CHAN
#  更新：2026/04/08
#  基于原脚本整合：
#    - debianinstall.sh (Debian 13 一键初始化)
#    - install_tailscale.sh (Tailscale 高级管理)
#    - pve-tools2.sh (PVE 9.0 精简工具)
# ==============================================================

set -e

# ---------------- 颜色定义 (统一三脚本) ----------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log()     { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }

# 通用暂停（供各子菜单使用）
pause() { echo ""; read -p "按下回车键继续..." ; }

# 依赖检查
command_exists() { command -v "$1" >/dev/null 2>&1; }

# 共享：sysctl 参数更新（来自 install_tailscale.sh，供多处复用）
update_sysctl_param() {
    local key=$1
    local value=$2
    if grep -q "^$key" /etc/sysctl.conf 2>/dev/null; then
        sed -i "s|^$key.*|$key=$value|" /etc/sysctl.conf
    else
        echo "$key=$value" >> /etc/sysctl.conf
    fi
    sysctl -w "$key=$value" >/dev/null 2>&1
}

# 共享检查函数（来自 install_tailscale.sh）
check_bbr() { 
    lsmod | grep -q "tcp_bbr" && echo -e "${GREEN}[已开启]${NC}" || echo -e "${RED}[未开启]${NC}"; 
}
check_forward() { 
    [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" -eq 1 ] && echo -e "${GREEN}[已开启]${NC}" || echo -e "${RED}[未开启]${NC}"
}

# 检查 root 权限（整合脚本入口）
[[ $EUID -ne 0 ]] && error "请使用 root 权限运行此脚本：sudo bash $0"

# ==============================================================
#  模块 1: Debian 13 初始化 (改编自 debianinstall.sh)
#  支持多选 + 执行摘要，网络优化复用共享 sysctl
# ==============================================================

DEBIAN_MENU_ITEMS=(
    "安装常用工具（curl wget vim net-tools ntpsec-ntpdate molly-guard）"
    "设置时区（Asia/Shanghai）"
    "配置 Locale（英文界面 + 中文支持）"
    "启用 IPv4/IPv6 转发 + 开启BBR"
    "修改 apt 源为清华镜像源"
    "安装 Docker（官方源 + 清华镜像加速）"
    "修改主机名称（Hostname）"
)
DEBIAN_SELECTED=(0 0 0 0 0 0 0)

print_debian_menu() {
    clear
    echo -e "\n${BOLD}=====================================================${NC}"
    echo -e "${BOLD}   Debian 13 初始化脚本 — 选择要执行的功能${NC}"
    echo -e "${BOLD}=====================================================${NC}"
    echo -e "  ${GREEN}输入序号切换选中/取消，a=全选，n=全不选，b=返回主菜单，回车确认执行${NC}\n"
    for i in "${!DEBIAN_MENU_ITEMS[@]}"; do
        local idx=$((i + 1))
        if [[ "${DEBIAN_SELECTED[$i]}" == "1" ]]; then
            echo -e "  ${GREEN}[✔] ${idx}. ${DEBIAN_MENU_ITEMS[$i]}${NC}"
        else
            echo -e "  ${RED}[ ] ${idx}. ${DEBIAN_MENU_ITEMS[$i]}${NC}"
        fi
    done
    echo ""
    echo -e "  ${GREEN}a${NC} 全选   ${GREEN}n${NC} 全不选   ${RED}b${NC} 返回主菜单   ${CYAN}回车${NC} 开始执行"
    echo -e "${BOLD}=====================================================${NC}"
    echo -n "  请输入【序号】，然后回车（Enter）: "
}

run_debian_init() {
    DEBIAN_SELECTED=(0 0 0 0 0 0 0)
    while true; do
        print_debian_menu
        read -r input

        case "$input" in
            "")
                any=0
                for s in "${DEBIAN_SELECTED[@]}"; do [[ "$s" == "1" ]] && any=1; done
                if [[ $any -eq 0 ]]; then
                    echo -e "\n  ${YELLOW}[WARN]${NC}  至少需要选择一项，请重新选择"
                    sleep 1
                else
                    break
                fi
                ;;
            a|A) DEBIAN_SELECTED=(1 1 1 1 1 1 0) ;;
            n|N) DEBIAN_SELECTED=(0 0 0 0 0 0 0) ;;
            b|B)
                return 0
                ;;
            [1-7])
                idx=$((input - 1))
                [[ "${DEBIAN_SELECTED[$idx]}" == "1" ]] && DEBIAN_SELECTED[$idx]=0 || DEBIAN_SELECTED[$idx]=1
                ;;
            *)
                echo -e "\n  ${YELLOW}[WARN]${NC}  无效输入，请输入 1-7 / a / n / b / 回车"
                sleep 1
                ;;
        esac
    done

    clear
    echo ""
    echo -e "${BOLD}=====================================================${NC}"
    echo -e "${BOLD}   开始执行 Debian 初始化...${NC}"
    echo -e "${BOLD}=====================================================${NC}"
    echo ""

    SUMMARY=()

    # --- 1. 安装工具 ---
    if [[ "${DEBIAN_SELECTED[0]}" == "1" ]]; then
        info "安装常用工具..."
        apt-get install -y -q curl wget vim net-tools ntpsec-ntpdate molly-guard
        success "工具安装完成"
        SUMMARY+=("  安装工具        : curl wget vim net-tools ntpsec-ntpdate molly-guard")
    else
        SUMMARY+=("  安装工具        : 未安装（跳过）")
    fi

    # --- 2. 修改时区 ---
    if [[ "${DEBIAN_SELECTED[1]}" == "1" ]]; then
        info "设置时区为 Asia/Shanghai ..."
        timedatectl set-timezone Asia/Shanghai
        ntpdate pool.ntp.org 2>/dev/null || true
        TZ_RESULT="$(timedatectl | grep 'Time zone' | awk '{print $3}')"
        success "时区已设置为：$TZ_RESULT"
        SUMMARY+=("  时区            : $TZ_RESULT")
    else
        SUMMARY+=("  时区            : 未修改（跳过）")
    fi

    # --- 3. Locale ---
    if [[ "${DEBIAN_SELECTED[2]}" == "1" ]]; then
        info "配置 Locale..."
        apt-get update -qq && apt-get install -y -qq locales
        sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
        sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
        locale-gen > /dev/null 2>&1
        update-locale LANG=en_US.UTF-8 LC_CTYPE=zh_CN.UTF-8
        success "Locale 配置完成"
        SUMMARY+=("  系统语言        : en_US.UTF-8（支持中文）")
    else
        SUMMARY+=("  系统语言        : 未修改（跳过）")
    fi

    # --- 4. 网络优化 (复用共享 update_sysctl_param) ---
    if [[ "${DEBIAN_SELECTED[3]}" == "1" ]]; then
        info "配置 IPv4/IPv6 转发 + BBR ..."
        update_sysctl_param "net.ipv4.ip_forward" "1"
        update_sysctl_param "net.ipv6.conf.all.forwarding" "1"
        update_sysctl_param "net.core.default_qdisc" "fq"
        update_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"
        # 额外持久化文件（兼容原脚本）
        cat > "/etc/sysctl.d/99-debian-init.conf" <<EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl --system > /dev/null 2>&1
        BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        success "BBR 已启用: $BBR_STATUS"
        SUMMARY+=("  网络优化        : 转发+BBR已开启")
    else
        SUMMARY+=("  网络优化        : 未配置（跳过）")
    fi

    # --- 5. 清华源 (Debian 专用) ---
    if [[ "${DEBIAN_SELECTED[4]}" == "1" ]]; then
        info "修改 apt 源为清华镜像源..."
        CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 || echo "trixie")
        [[ -f /etc/apt/sources.list ]] && mv /etc/apt/sources.list /etc/apt/sources.list.disabled 2>/dev/null || true
        cat > /etc/apt/sources.list.d/tuna.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian
Suites: ${CODENAME} ${CODENAME}-updates ${CODENAME}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/debian-security
Suites: ${CODENAME}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
        apt-get update -qq && success "apt 源已切换" || warn "源更新失败"
        SUMMARY+=("  apt 源          : 清华镜像源")
    else
        SUMMARY+=("  apt 源          : 未修改（跳过）")
    fi

    # --- 6. Docker ---
    if [[ "${DEBIAN_SELECTED[5]}" == "1" ]]; then
        info "安装 Docker..."
        if command -v docker &>/dev/null; then
            warn "Docker 已安装，跳过"
            SUMMARY+=("  Docker          : 已存在（跳过）")
        else
            apt-get update -qq && apt-get install -y -qq ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
            CODENAME=$(lsb_release -cs 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 || echo "trixie")
            ARCH=$(dpkg --print-architecture)
            cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
            apt-get update -qq && apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.mirrors.tuna.tsinghua.edu.cn"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
            systemctl enable docker --now && systemctl restart docker
            success "Docker 安装完成"
            SUMMARY+=("  Docker          : 已安装并开启加速")
        fi
    else
        SUMMARY+=("  Docker          : 未安装（跳过）")
    fi

    # --- 7. 主机名 ---
    if [[ "${DEBIAN_SELECTED[6]}" == "1" ]]; then
        CURRENT_HOSTNAME=$(hostname)
        echo -e "\n${CYAN}[INPUT]${NC} 当前主机名 (Hostname) 为: ${RED}$CURRENT_HOSTNAME${NC}"
        echo -e "${CYAN}[INPUT]${NC} 请输入新的主机名 (Hostname):"
        read -r NEW_HOSTNAME
        if [[ -n "$NEW_HOSTNAME" && "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]]; then
            hostnamectl set-hostname "$NEW_HOSTNAME"
            sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts
            success "主机名已修改为: $NEW_HOSTNAME"
            echo -e "${RED}${BOLD}[!] 提示: 主机名已更改，建议稍后重启系统生效。${NC}"
            SUMMARY+=("  主机名          : $CURRENT_HOSTNAME -> $NEW_HOSTNAME")
        else
            SUMMARY+=("  主机名          : 未修改")
        fi
    else
        SUMMARY+=("  主机名          : 未修改（跳过）")
    fi

    # 汇总展示
    echo ""
    echo -e "${BOLD}=====================================================${NC}"
    echo -e "${GREEN}${BOLD}   执行完成！汇总如下：${NC}"
    echo -e "${BOLD}=====================================================${NC}"
    for line in "${SUMMARY[@]}"; do
        echo -e "$line"
    done
    echo -e "${BOLD}=====================================================${NC}"
    echo ""
    pause
}

# ==============================================================
#  模块 2: Tailscale 高级管理 (改编自 install_tailscale.sh)
#  修复了原脚本 subshell 导致 status_color 不生效的问题
#  复用共享 update_sysctl_param / check_bbr / check_forward
# ==============================================================

get_tailscale_status() {
    if ! command -v tailscaled >/dev/null 2>&1; then
        echo "未安装|${RED}"
    elif systemctl is-active --quiet tailscaled; then
        echo "运行中|${GREEN}"
    else
        echo "已停止|${YELLOW}"
    fi
}

check_tailscale_installed() {
    command -v tailscale >/dev/null 2>&1 && echo -e "${GREEN}[已安装]${NC}" || echo -e "${RED}[未安装]${NC}"
}

check_exit_node() {
    if tailscale debug prefs 2>/dev/null | grep -q '"AdvertiseExitNode": true'; then
        echo -e "${GREEN}[已开启]${NC}"
    else
        echo -e "${RED}[未开启]${NC}"
    fi
}

check_subnet_route() {
    if tailscale debug prefs 2>/dev/null | grep -q '"AdvertiseRoutes":'; then
        echo -e "${GREEN}[已配置]${NC}"
    else
        echo -e "${RED}[未配置]${NC}"
    fi
}

update_tailscale_config() {
    local exit_node=$1
    local routes=$2
    local cmd="tailscale up --accept-routes"
    
    [[ "$exit_node" == "true" ]] && cmd="$cmd --advertise-exit-node"
    [[ -n "$routes" ]] && cmd="$cmd --advertise-routes=$routes"
    
    echo "正在执行配置: $cmd"
    eval $cmd
}

install_tailscale() {
    # 强制检查仓库健康
    if ! apt-get update >/dev/null 2>&1; then
        echo -e "${RED}检测到 Tailscale 源可能异常，正在清理...${NC}"
        find /etc/apt/sources.list.d/ -type f | grep -i tailscale | xargs rm -f
        apt-get update
    fi

    if command -v tailscale >/dev/null 2>&1; then
        echo -e "${YELLOW}检测到 Tailscale 已安装，跳过安装步骤。${NC}"
    else
        echo "正在安装 Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    fi
    
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "${RED}安装失败，请检查网络连接。${NC}"
    else
        echo "启动 Tailscale 服务..."
        tailscale up
    fi
    pause
}

apply_tailscale_config() {
    local enable_exit=$1
    local routes=$2
    
    # 强制 SSH 策略路由（防止掉线关键）
    local ip_addr=$(hostname -I | awk '{print $1}')
    ip rule add from "$ip_addr" lookup main pref 100 2>/dev/null || true
    
    local cmd=(
    tailscale up
    --accept-routes
    --snat-subnet-routes=true
    )

    [[ "$enable_exit" == "true" ]] && cmd+=(--advertise-exit-node)
    [[ -n "$routes" ]] && cmd+=(--advertise-routes="$routes")

    echo "正在执行配置: ${cmd[*]}"
    "${cmd[@]}"
}

setup_exit_node() {
    echo "正在配置出口节点模式..."
    NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    if [[ -n "$NIC" ]]; then
        echo "检测到主网卡: $NIC"
        ethtool -K "$NIC" rx-udp-gro-forwarding on 2>/dev/null \
            && echo "UDP GRO 已开启" \
            || echo "UDP GRO 开启失败（可能网卡不支持）"
    fi
    
    local current_routes=$(tailscale status --json 2>/dev/null | grep -o '"advertisedRoutes":\[.*\]' | cut -d'[' -f2 | cut -d']' -f1 | sed 's/"//g' || true)
    apply_tailscale_config "true" "$current_routes"
    
    echo -e "${GREEN}出口节点已开启，SSH 策略路由已应用。${NC}"
    pause
}

setup_subnet_route() {
    read -p "请输入要转发的子网 CIDR (例如 192.168.1.0/24): " subnet
    if [[ -z "$subnet" ]]; then 
        echo "无效输入"
    else
        local is_exit=$(tailscale status --json 2>/dev/null | grep -q '"ExitNode":true' && echo "true" || echo "false")
        apply_tailscale_config "$is_exit" "$subnet"
        echo -e "${GREEN}完成：已应用路由 $subnet。${NC}"
    fi
    pause
}

enable_bbr() {
    update_sysctl_param "net.core.default_qdisc" "fq"
    update_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"
    echo -e "${GREEN}BBR 已开启。${NC}"
    pause
}

enable_forward() {
    update_sysctl_param "net.ipv4.ip_forward" "1"
    update_sysctl_param "net.ipv6.conf.all.forwarding" "1"
    echo -e "${GREEN}IPv4/IPv6 转发已开启。${NC}"
    pause
}

uninstall_tailscale() {
    echo -e "${RED}警告：将彻底卸载 Tailscale...${NC}"
    systemctl stop tailscaled && systemctl disable tailscaled
    apt-get remove --purge -y tailscale tailscaled
    rm -rf /var/lib/tailscale /etc/tailscale
    echo -e "${GREEN}卸载完成。${NC}"
    pause
}

run_tailscale_menu() {
    # 确保 curl / jq 可用（原脚本逻辑）
    if ! command_exists curl || ! command_exists jq; then 
        apt-get update >/dev/null 2>&1
        ! command_exists curl && apt-get install -y curl
        ! command_exists jq && apt-get install -y jq
    fi

    while true; do
        clear
        status_info=$(get_tailscale_status)
        ts_status="${status_info%%|*}"
        status_color="${status_info##*|}"
        echo -e "${GREEN}=== Tailscale 高级管理脚本 (整合版) ===${NC}"
        echo -e "Tailscale 状态: [ ${status_color}${ts_status}${NC} ]"
        echo "--------------------------------"
        echo "1) 安装 Tailscale		$(check_tailscale_installed)"
        echo "2) 配置为 Exit Node (出口节点)	$(check_exit_node)"
        echo "3) 配置子网路由 (Subnet Router)	$(check_subnet_route)"
        echo -e "4) 开启 BBR 加速		$(check_bbr)"
        echo -e "5) 开启 IPv4/IPv6 转发		$(check_forward)"
        echo "6) 卸载 Tailscale (完全移除)"
        echo "b) 返回主菜单"
        echo "--------------------------------"
        read -p "请选择操作 [1-6/b]: " choice

        case "$choice" in
            1) install_tailscale ;;
            2) setup_exit_node ;;
            3) setup_subnet_route ;;
            4) enable_bbr ;;
            5) enable_forward ;;
            6) uninstall_tailscale ;;
            b|B) return 0 ;;
            *) echo -e "${RED}错误：无效选项${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================
#  模块 3: PVE 9.0 精简工具 (改编自 pve-tools2.sh)
#  保留原 4 个子功能 + 返回主菜单
# ==============================================================

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
            ls /boot/vmlinuz-* 2>/dev/null || true
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

run_pve_menu() {
    while true; do
        clear
        echo -e "${CYAN}====================================${NC}"
        echo -e "${CYAN}     PVE 9.0 精简工具（整合版）     ${NC}"
        echo -e "${CYAN}====================================${NC}\n"
        echo "1) 系统优化 (订阅弹窗/温度监控/电源模式/安全防护)"
        echo "2) 软件源与更新 (换源/更新/PVE8→9升级)"
        echo "3) 启动与内核 (内核切换/更新/清理)"
        echo "4) 直通与显卡 (核显/NVIDIA/硬件直通)"
        echo "b) 返回主菜单"
        echo ""
        read -p "请选择功能 [1-4/b]: " choice

        case $choice in
            1) system_optimization ;;
            2) sources_and_updates ;;
            3) boot_and_kernel ;;
            4) passthrough_and_gpu ;;
            b|B) return 0 ;;
            *) warn "输入错误，请重新选择" ;;
        esac
    done
}

# ==============================================================
#  主菜单 (统一入口)
# ==============================================================

main_menu() {
    while true; do
        clear
        echo -e "${BOLD}=====================================================${NC}"
        echo -e "${BOLD}     Linux 工具箱 (整合版)     ${NC}"
        echo -e "${BOLD}  Debian初始化 | Tailscale管理 | PVE工具  ${NC}"
        echo -e "${BOLD}  作者：Linuxhobby   更新：2026/06/05${NC}"
        echo -e "${BOLD}=====================================================${NC}"
        echo ""
        echo "1) Debian 13 一键初始化"
        echo "2) Tailscale 高级管理"
        echo "3) PVE 9.0 精简工具"
        echo "0) 退出"
        echo ""
        read -p "请选择 [1-3/0]: " choice

        case "$choice" in
            1) run_debian_init ;;
            2) run_tailscale_menu ;;
            3) run_pve_menu ;;
            0) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
            *) warn "无效选项，请重新选择"; sleep 1 ;;
        esac
    done
}

# 启动主菜单
main_menu
