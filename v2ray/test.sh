#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray 综合管理脚本 (Vultr 深度兼容版)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 定义路径
V2RAY_BIN="/usr/local/bin/v2ray"
V2RAY_CONF_DIR="/usr/local/etc/v2ray"
CONFIG_FILE="$V2RAY_CONF_DIR/config.json"
CADDY_CONF_DIR="/etc/caddy"
CADDY_FILE="$CADDY_CONF_DIR/Caddyfile"

# 1. 环境准备与目录强制创建
prepare_env() {
    echo -e "${YELLOW}正在清理旧战场并准备环境...${NC}"
    apt update && apt install -y curl wget jq uuid-runtime caddy vnstat unzip
    
    # 强制创建所有必要目录，确保写入不会报错
    mkdir -p $V2RAY_CONF_DIR
    mkdir -p $CADDY_CONF_DIR
    mkdir -p /var/www/html
    
    # 彻底停止可能冲突的服务
    systemctl stop v2ray caddy nginx 2>/dev/null
}

# 2. 核心程序安装 (采用官方稳定源)
install_core() {
    echo -e "${GREEN}正在下载 V2Ray 核心程序...${NC}"
    # 获取最新版本并下载
    local latest_version=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest | jq -r .tag_name)
    echo -e "${BLUE}检测到最新版本: $latest_version${NC}"
    
    wget -q -O /tmp/v2ray.zip "https://github.com/v2fly/v2ray-core/releases/download/${latest_version}/v2ray-linux-64.zip"
    
    if [[ ! -f /tmp/v2ray.zip ]]; then
        echo -e "${RED}致命错误：下载 V2Ray 核心失败！请检查服务器网络。${NC}"
        exit 1
    fi
    
    unzip -o /tmp/v2ray.zip -d /tmp/v2ray_tmp
    cp /tmp/v2ray_tmp/v2ray /usr/local/bin/
    chmod +x /usr/local/bin/v2ray
    rm -rf /tmp/v2ray.zip /tmp/v2ray_tmp
    echo -e "${GREEN}核心程序安装成功。${NC}"
}

# 3. 配置文件写入
write_config() {
    local domain=$1
    local proto=$2
    local uuid=$(uuidgen)
    local wspath="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

    # 写入 V2Ray 配置
    cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "port": 10000, "listen":"127.0.0.1", "protocol": "$proto",
    "settings": { "clients": [{"id": "$uuid" $( [[ "$proto" == "vless" ]] && echo ',"decryption": "none"' ) }] },
    "streamSettings": { "network": "ws", "wsSettings": {"path": "$wspath"} }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

    # 写入 Caddyfile (加入 bind 0.0.0.0 容错)
    cat <<EOF > $CADDY_FILE
$domain {
    bind 0.0.0.0
    reverse_proxy $wspath localhost:10000
    file_server { root /var/www/html }
}
EOF

    # 写入 Systemd 服务
    cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -c $CONFIG_FILE
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable v2ray caddy
    systemctl restart v2ray caddy
    
    # 验证服务是否成功启动
    sleep 3
    if systemctl is-active --quiet v2ray && systemctl is-active --quiet caddy; then
        echo -e "${GREEN}所有服务已成功启动！${NC}"
        generate_output "$uuid" "$domain" "$wspath" "$proto"
    else
        echo -e "${RED}警告：服务启动异常，请检查 journalctl -xeu caddy/v2ray${NC}"
    fi
}

# --- 内部函数：分享链接生成 (同前) ---
generate_output() {
    local uuid=$1; local domain=$2; local path=$3; local proto=$4
    local safe_path=$(echo -n "$path" | sed 's/\//%2F/g')
    if [[ "$proto" == "vless" ]]; then
        URL="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=$safe_path#vpn-$domain"
    else
        VMESS_JSON=$(cat <<EOF
{ "v": "2", "ps": "vpn-$domain", "add": "$domain", "port": "443", "id": "$uuid", "aid": "0", "net": "ws", "type": "none", "host": "$domain", "path": "$path", "tls": "tls" }
EOF
        )
        URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)#$domain"
    fi
    echo -e "\n${YELLOW}---------- 阵地部署成功 ----------${NC}"
    echo -e "协议: $proto | 域名: $domain"
    echo -e "UUID: $uuid"
    echo -e "路径: $path"
    echo -e "链接: ${RED}$URL${NC}"
    echo -e "${YELLOW}----------------------------------${NC}"
}

# --- 主逻辑菜单 ---
clear
echo -e "${GREEN}   将军阁下的 V2Ray 管理面板 (版本: 2.0-STABLE) ${NC}"
echo -e "${GREEN}   随机号: 897 ${NC}"
echo -e "1) 开始全自动部署 (VLESS + WS + TLS)"
echo -e "2) 卸载并清空环境"
echo -e "q) 退出"
read -p "请选择: " opt

case $opt in
    1)
        read -p "请输入解析域名 (如 rc.myvpsworld.top): " DOMAIN
        [[ -z "$DOMAIN" ]] && exit 1
        prepare_env
        install_core
        write_config "$DOMAIN" "vless"
        ;;
    2)
        systemctl stop v2ray caddy
        rm -rf /usr/local/etc/v2ray /usr/local/bin/v2ray /etc/caddy
        echo "清理完毕"
        ;;
    *)
        exit 0
        ;;
esac