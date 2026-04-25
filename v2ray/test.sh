#!/bin/bash

# ==============================================================
#  自动安装V2Ray VLESS-WS-TLS 全自动安装脚本
#  基于 233boy/v2ray 一键脚本封装
#  功能：
#    1. 系统基础初始化（工具、时区、vnstat）
#    2. 自动安装 233boy/v2ray 脚本
#    3. 自动添加 VLESS-WS-TLS 配置
#    4. 输出完整连接信息
#
#  前置要求：
#    - root 权限运行
#    - 域名已 A 记录解析到本机 IP
#    - 80 / 443 端口未被占用
#    - 系统：Debian / Ubuntu（推荐 Ubuntu 22 / Debian 12）
# ==============================================================

# ── 颜色定义 ──────────────────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── 工具函数 ──────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*"; }
banner()  { echo -e "\n${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
            echo -e "${BLUE}${BOLD}  $*${NC}"; \
            echo -e "${BLUE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ── root 权限检查 ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "请使用 root 权限运行此脚本（sudo bash $0）"
    exit 1
fi

# ── 参数解析 ──────────────────────────────────────────────────
# 支持通过命令行参数传入，也支持交互输入
DOMAIN="${1:-}"
UUID="${2:-}"
WS_PATH="${3:-}"

# ==============================================================
#  STEP 0: 收集必要参数
# ==============================================================
banner "STEP 0 · 参数收集"

# 域名（必须）
if [[ -z "$DOMAIN" ]]; then
    read -rp "$(echo -e "${CYAN}请输入域名（已解析到本机 IP）：${NC}")" DOMAIN
fi

if [[ -z "$DOMAIN" ]]; then
    err "域名不能为空，退出。"
    exit 1
fi

# UUID（可选，留空则由 v2ray 脚本自动生成）
if [[ -z "$UUID" ]]; then
    read -rp "$(echo -e "${CYAN}请输入 UUID（留空则自动生成）：${NC}")" UUID
fi

# WS Path（可选，留空则由 v2ray 脚本自动生成）
if [[ -z "$WS_PATH" ]]; then
    read -rp "$(echo -e "${CYAN}请输入 WebSocket Path（留空则自动生成，示例 /ws）：${NC}")" WS_PATH
fi

# 将空值替换为 auto 关键字（233boy 脚本约定）
UUID_ARG="${UUID:-auto}"
PATH_ARG="${WS_PATH:-auto}"

info "域名   : ${BOLD}${DOMAIN}${NC}"
info "UUID   : ${BOLD}${UUID_ARG}${NC}"
info "WS Path: ${BOLD}${PATH_ARG}${NC}"

# ==============================================================
#  STEP 1: 域名解析预检
# ==============================================================
banner "STEP 1 · 域名解析预检"

SERVER_IP=$(curl -s4 --max-time 6 https://api.ipify.org 2>/dev/null \
         || curl -s4 --max-time 6 https://ifconfig.me 2>/dev/null \
         || curl -s4 --max-time 6 https://icanhazip.com 2>/dev/null)

if [[ -z "$SERVER_IP" ]]; then
    warn "无法自动获取本机公网 IP，跳过域名解析检查。"
else
    RESOLVED_IP=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1; exit}')
    if [[ -z "$RESOLVED_IP" ]]; then
        warn "无法解析域名 ${DOMAIN}，请确认 DNS A 记录已配置。"
        warn "继续安装，但 TLS 证书申请可能会失败。"
    elif [[ "$RESOLVED_IP" != "$SERVER_IP" ]]; then
        warn "域名解析 IP（${RESOLVED_IP}）与本机公网 IP（${SERVER_IP}）不一致。"
        warn "TLS 证书申请可能会失败，请检查 DNS A 记录。"
        read -rp "$(echo -e "${YELLOW}是否仍要继续？[y/N]：${NC}")" CONTINUE
        [[ "${CONTINUE,,}" != "y" ]] && { info "已取消安装。"; exit 0; }
    else
        ok "域名 ${DOMAIN} 正确解析到 ${SERVER_IP}"
    fi
fi

# ==============================================================
#  STEP 2: 端口占用检查（80 / 443）
# ==============================================================
banner "STEP 2 · 端口占用检查"

check_port() {
    local port=$1
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 0  # 端口被占用
    fi
    return 1
}

PORTS_BLOCKED=0
for PORT in 80 443; do
    if check_port "$PORT"; then
        warn "端口 ${PORT} 已被占用！"
        PORTS_BLOCKED=1
    else
        ok "端口 ${PORT} 可用"
    fi
done

if [[ $PORTS_BLOCKED -eq 1 ]]; then
    warn "Caddy 需要 80/443 端口申请 TLS 证书。请先释放被占用的端口。"
    read -rp "$(echo -e "${YELLOW}是否仍要继续？[y/N]：${NC}")" CONTINUE
    [[ "${CONTINUE,,}" != "y" ]] && { info "已取消安装。"; exit 0; }
fi

# ==============================================================
#  STEP 3: 系统基础初始化
# ==============================================================
banner "STEP 3 · 系统基础初始化"

info "更新包列表..."
apt-get update -y
ok "包列表更新完毕。"

info "安装基础工具 (net-tools, vnstat, vim, wget, curl)..."
apt-get install -y net-tools vnstat vim wget curl
ok "基础工具安装完毕。"

info "设置时区为 Asia/Shanghai..."
timedatectl set-timezone Asia/Shanghai
ok "时区已设置：$(date)"

info "配置 vnstat..."
IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [[ -n "$IFACE" ]]; then
    info "检测到主网卡接口: ${BOLD}${IFACE}${NC}"
    if [[ -f /etc/vnstat.conf ]]; then
        if grep -q '^Interface' /etc/vnstat.conf; then
            sed -i "s|^Interface .*|Interface \"$IFACE\"|" /etc/vnstat.conf
        else
            echo "Interface \"$IFACE\"" >> /etc/vnstat.conf
        fi
    fi
    vnstat --add -i "$IFACE" --force 2>/dev/null || true
    systemctl enable vnstat
    systemctl restart vnstat
    ok "vnstat 已绑定接口 ${IFACE} 并启动。"
fi

# ==============================================================
#  STEP 4: 安装 233boy/v2ray 脚本
# ==============================================================
banner "STEP 4 · 安装 233boy/v2ray 脚本"

if command -v v2ray &>/dev/null && [[ -f /usr/local/bin/v2ray ]]; then
    warn "检测到 v2ray 管理脚本已安装，跳过安装步骤。"
else
    info "开始下载并安装 v2ray 脚本..."

    # 下载到临时文件，便于审查（不直接 pipe 执行）
    V2RAY_INSTALLER="/tmp/v2ray_install_$(date +%s).sh"
    wget -qO "$V2RAY_INSTALLER" \
        https://github.com/233boy/v2ray/raw/master/install.sh

    if [[ ! -f "$V2RAY_INSTALLER" ]] || [[ ! -s "$V2RAY_INSTALLER" ]]; then
        err "下载 v2ray 安装脚本失败，请检查网络连接。"
        exit 1
    fi

    ok "安装脚本下载完成：${V2RAY_INSTALLER}"
    bash "$V2RAY_INSTALLER"
    rm -f "$V2RAY_INSTALLER"

    # 验证安装结果
    if ! command -v v2ray &>/dev/null; then
        err "v2ray 安装失败，请检查上方输出信息。"
        exit 1
    fi
    ok "v2ray 脚本安装成功，版本：$(v2ray v 2>/dev/null || echo '未知')"
fi

# ==============================================================
#  STEP 5: 添加 VLESS-WS-TLS 配置
# ==============================================================
banner "STEP 5 · 添加 VLESS-WS-TLS 配置"

info "执行命令：v2ray add vws ${DOMAIN} ${UUID_ARG} ${PATH_ARG}"
info "（Caddy 将自动向 Let's Encrypt 申请 TLS 证书，请确保端口 80/443 畅通）"
echo ""

# 执行添加配置
v2ray add vws "$DOMAIN" "$UUID_ARG" "$PATH_ARG"

ADD_EXIT=$?
if [[ $ADD_EXIT -ne 0 ]]; then
    err "VLESS-WS-TLS 配置添加失败（退出码：${ADD_EXIT}）。"
    err "常见原因："
    err "  1. 域名未正确解析到本机 IP"
    err "  2. 80/443 端口被防火墙或其他程序占用"
    err "  3. Let's Encrypt 申请证书失败（触发频率限制等）"
    exit 1
fi

# ==============================================================
#  STEP 6: 输出连接信息
# ==============================================================
banner "STEP 6 · 配置完成 · 连接信息"

echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║        VLESS-WS-TLS 安装完成！               ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# 显示配置详情
info "查看配置信息："
v2ray info vws 2>/dev/null || v2ray info 2>/dev/null

echo ""
info "获取分享链接："
v2ray url 2>/dev/null | grep -i vless | head -5 || true

echo ""
echo -e "${CYAN}${BOLD}── 常用管理命令 ─────────────────────────────────${NC}"
echo -e "  ${YELLOW}v2ray status${NC}          查看运行状态"
echo -e "  ${YELLOW}v2ray info${NC}            查看所有配置"
echo -e "  ${YELLOW}v2ray url${NC}             生成分享链接"
echo -e "  ${YELLOW}v2ray restart${NC}         重启服务"
echo -e "  ${YELLOW}v2ray log${NC}             查看运行日志"
echo -e "  ${YELLOW}v2ray add vws DOMAIN${NC}  继续添加新配置"
echo -e "${CYAN}${BOLD}─────────────────────────────────────────────────${NC}"
echo ""
ok "全部安装完成！"
