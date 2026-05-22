#!/bin/bash

# 确保以 root 运行
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行此脚本"
   exit 1
fi

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 获取 Tailscale 运行状态的改进版
get_tailscale_status() {
    if ! command -v tailscaled >/dev/null 2>&1; then
        status_color=$RED
        echo "未安装"
    elif systemctl is-active --quiet tailscaled; then
        status_color=$GREEN
        echo "运行中"
    else
        status_color=$YELLOW
        echo "已停止"
    fi
}

# 依赖检查
command_exists() { command -v "$1" >/dev/null 2>&1; }
if ! command_exists curl; then apt-get update && apt-get install -y curl jq; fi

pause() { echo ""; read -p "按下回车键返回主菜单..." ; }

# 状态检测辅助函数
check_bbr() { 
	lsmod | grep -q "tcp_bbr" && echo -e "${GREEN}[已开启]${NC}" || echo -e "${RED}[未开启]${NC}"; 
}
check_forward() { 
        [ "$(sysctl -n net.ipv4.ip_forward)" -eq 1 ] && echo -e "${GREEN}[已开启]${NC}" || echo -e "${RED}[未开启]${NC}"
}

# 检测 Tailscale 是否已安装
check_tailscale_installed() {
    command -v tailscale >/dev/null 2>&1 && echo -e "${GREEN}[已安装]${NC}" || echo -e "${RED}[未安装]${NC}"
}

# 检查是否真正开启了 Exit Node 广播
check_exit_node() {
    if tailscale debug prefs 2>/dev/null | jq -e '.AdvertiseExitNode == true' >/dev/null; then
        echo -e "${GREEN}[已开启]${NC}"
    else
        echo -e "${RED}[未开启]${NC}"
    fi
}

# 检查是否真正开启了子网路由广播
check_subnet_route() {
    if tailscale debug prefs 2>/dev/null | jq -e '.AdvertiseRoutes | length > 0' >/dev/null; then
        echo -e "${GREEN}[已配置]${NC}"
    else
        echo -e "${RED}[未配置]${NC}"
    fi
}

# --- 功能函数 ---

# 统一的 Tailscale 更新函数，防止参数被覆盖
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
    
    # 检查命令是否存在
    if ! command -v tailscale >/dev/null 2>&1; then
        echo -e "${RED}安装失败，请检查网络连接。${NC}"
    else
        echo "启动 Tailscale 服务..."
        tailscale up
    fi
    pause
}

# 统一的配置引擎
apply_tailscale_config() {
    local enable_exit=$1
    local routes=$2
    
    # 强制 SSH 策略路由（这是防止掉线的关键）
    local ip_addr=$(hostname -I | awk '{print $1}')
    ip rule add from "$ip_addr" lookup main pref 100 2>/dev/null
    
    # 构造命令：Accept-routes 必须开启以防止路由失效，SNAT 保证转发稳定性
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
    
    # 获取当前路由以保持不变
    local current_routes=$(tailscale status --json 2>/dev/null | grep -o '"advertisedRoutes":\[.*\]' | cut -d'[' -f2 | cut -d']' -f1 | sed 's/"//g')
    apply_tailscale_config "true" "$current_routes"
    
    echo -e "${GREEN}出口节点已开启，SSH 策略路由已应用。${NC}"
    pause
}

setup_subnet_route() {
    read -p "请输入要转发的子网 CIDR (例如 192.168.1.0/24): " subnet
    if [[ -z "$subnet" ]]; then 
        echo "无效输入"
    else
        # 获取当前是否已开启出口节点
        local is_exit=$(tailscale status --json 2>/dev/null | grep -q '"ExitNode":true' && echo "true" || echo "false")
        apply_tailscale_config "$is_exit" "$subnet"
        echo -e "${GREEN}完成：已应用路由 $subnet。${NC}"
    fi
    pause
}

# 核心引擎：处理任何 sysctl 更新
update_sysctl_param() {
    local key=$1
    local value=$2
    if grep -q "^$key" /etc/sysctl.conf; then
        sed -i "s|^$key.*|$key=$value|" /etc/sysctl.conf
    else
        echo "$key=$value" >> /etc/sysctl.conf
    fi
    sysctl -w "$key=$value" >/dev/null 2>&1
}

# 选项 4 调用
enable_bbr() {
    update_sysctl_param "net.core.default_qdisc" "fq"
    update_sysctl_param "net.ipv4.tcp_congestion_control" "bbr"
    echo -e "${GREEN}BBR 已开启。${NC}"
    pause
}

# 选项 5 调用
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

# --- 主菜单循环 ---
while true; do
    clear
    ts_status=$(get_tailscale_status)
    echo -e "${GREEN}=== Tailscale 高级管理脚本 ===${NC}"
    echo -e "Tailscale 状态: [ ${status_color}${ts_status}${NC} ]"
    echo "--------------------------------"
    echo "1) 安装 Tailscale		$(check_tailscale_installed)"
    echo "2) 配置为 Exit Node (出口节点)	$(check_exit_node)"
    echo "3) 配置子网路由 (Subnet Router)	$(check_subnet_route)"
    echo -e "4) 开启 BBR 加速		$(check_bbr)"
    echo -e "5) 开启 IPv4/IPv6 转发		$(check_forward)"
    echo "6) 卸载 Tailscale (完全移除)"
    echo "Q) 退出"
    echo "--------------------------------"
    read -p "请选择操作 [1-6/q]: " choice

    case "$choice" in
        1) install_tailscale ;;
        2) setup_exit_node ;;
        3) setup_subnet_route ;;
        4) enable_bbr ;;
        5) enable_forward ;;
        6) uninstall_tailscale ;;
        [qQ]) echo -e "${GREEN}再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}错误：无效选项${NC}"; sleep 1 ;;
    esac
done
