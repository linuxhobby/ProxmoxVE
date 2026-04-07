#!/bin/bash
# 这是一个精简版 PVE 9.0 工具 - 只保留换源 + 删除订阅弹窗
# 使用前请备份重要文件
# ============ 颜色 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数（简化）
log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[$(date +'%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[$(date +'%H:%M:%S')]${NC} $1" >&2; }

# 检查 root
if [[ $EUID -ne 0 ]]; then
    error "请使用 root 权限运行此脚本 (sudo bash ...)"
    exit 1
fi

# 功能1：更换软件源
change_sources() {
    clear
    echo -e "${CYAN}=== 功能1：更换 Proxmox VE 9.0 软件源 ===${NC}"
    echo ""
    echo "请选择镜像源："
    echo "1) 中科大 (USTC)"
    echo "2) 清华 (TUNA)"
    echo "3) 官方源（不推荐，速度慢）"
    read -p "请输入选项 [1-3，默认1]: " mirror_choice
    mirror_choice=${mirror_choice:-1}

    case $mirror_choice in
        1) MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/pve" ;;
        2) MIRROR="https://mirrors.tuna.tsinghua.edu.cn/proxmox/debian/pve" ;;
        3) MIRROR="http://download.proxmox.com/debian/pve" ;;
        *) MIRROR="https://mirrors.ustc.edu.cn/proxmox/debian/pve" ;;
    esac

    log "正在备份原有源文件..."
    cp -a /etc/apt/sources.list.d/ /etc/apt/sources.list.d.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

    log "正在更换软件源为：$MIRROR"

    # Debian 主源（Trixie / Debian 13）
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

    # 关闭企业源
    if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
        sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list
    fi

    # PVE 无订阅源
    cat > /etc/apt/sources.list.d/pve-no-subscription.list << EOF
deb $MIRROR bookworm pve-no-subscription
EOF

    log "更新软件源列表..."
    apt update

    log_success "软件源更换完成！"
    echo -e "${GREEN}建议执行：apt upgrade -y${NC}"
}

# 功能2：删除订阅弹窗
remove_subscription_popup() {
    clear
    echo -e "${CYAN}=== 功能2：删除 Proxmox VE 订阅弹窗 ===${NC}"
    echo ""

    local jsfile="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    local backup="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak.$(date +%Y%m%d_%H%M%S)"

    if [ ! -f "$jsfile" ]; then
        error "未找到 proxmoxlib.js 文件，可能是 PVE 版本不匹配"
        exit 1
    fi

    log "正在备份 $jsfile"
    cp "$jsfile" "$backup"

    log "正在修改订阅检查逻辑..."

    # 主要修改方式（PVE 9 常用）
    if grep -q "res.data.status.toLowerCase() !== 'active'" "$jsfile"; then
        sed -i "s/res.data.status.toLowerCase() !== 'active'/res.data.status.toLowerCase() === 'active'/" "$jsfile"
        log "已使用方式1修改订阅判断"
    else
        # 备用方式
        perl -i -pe 's/Ext\.Msg\.show\(\{.*title:\s*gettext\(.No\s*Subscription.*?\}\);/Ext.Msg.show({title: gettext("Info"), message: gettext("Subscription check bypassed"), buttons: Ext.Msg.OK, icon: Ext.Msg.INFO});/' "$jsfile" 2>/dev/null || true
        log "已使用备用方式修改"
    fi

    # 额外常见补丁
    sed -i '/subscription.*active/d' "$jsfile" 2>/dev/null || true
    sed -i 's/if (data.status !== "active")/if (false)/' "$jsfile" 2>/dev/null || true

    log "重启 pveproxy 服务使修改生效..."
    systemctl restart pveproxy

    log_success "订阅弹窗已移除！"
    echo -e "${GREEN}请在浏览器按 Ctrl + Shift + R 强制刷新页面${NC}"
}

# 主菜单
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}=======================================${NC}"
        echo -e "${CYAN}   PVE 9.0 精简工具（仅功能1+2）   ${NC}"
        echo -e "${CYAN}=======================================${NC}"
        echo ""
        echo "1) 更换软件源（推荐中科大或清华）"
        echo "2) 删除订阅弹窗"
        echo "0) 退出"
        echo ""
        read -p "请选择功能 [1/2/0]: " choice

        case $choice in
            1) change_sources ;;
            2) remove_subscription_popup ;;
            0) echo -e "${GREEN}已退出${NC}"; exit 0 ;;
            *) echo -e "${YELLOW}输入错误，请重新选择${NC}" ;;
        esac

        echo ""
        read -p "按回车键返回主菜单..."
    done
}

# 启动
main_menu