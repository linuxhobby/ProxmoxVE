#!/bin/bash

# ====================================================
# 将军阁下的专属 V2Ray 独立安装脚本 (UI 完美定制版)
# ====================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 权限运行!${NC}" && exit 1

# 1. 协议选择
clear
echo -e "${YELLOW}请选择要部署的协议：${NC}"
echo -e "1) vless"
echo -e "2) vmess"
read -p "请输入数字 [1-2]: " PROTO_CHOICE

case $PROTO_CHOICE in
    2) PROTOCOL="vmess" ;;
    *) PROTOCOL="vless" ;;
esac

read -p "请输入您的解析域名 (例如: cc.myvpsworld.top): " DOMAIN
[[ -z "$DOMAIN" ]] && echo -e "${RED}域名不能为空！${NC}" && exit 1

echo -e "${GREEN}正在准备环境...${NC}"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
apt update && apt install -y curl wget jq uuid-runtime debian-keyring debian-archive-keyring apt-transport-https vnstat

# 2. 安装核心与 Caddy
echo -e "${GREEN}安装 V2Ray 官方核心...${NC}"
bash <(curl -L https://raw.githubusercontent.com/v2fly/fscript/master/install-release.sh)

echo -e "${GREEN}安装 Caddy 2...${NC}"
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install caddy -y

# 3. 参数生成
UUID=$(uuidgen)
WSPATH="/$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 10)"

# 4. 配置文件写入
mkdir -p /usr/local/etc/v2ray
cat <<EOF > /usr/local/etc/v2ray/config.json
{
  "inbounds": [{
    "port": 10000,
    "listen":"127.0.0.1",
    "protocol": "$PROTOCOL",
    "settings": {
      "clients": [{"id": "$UUID" $( [[ "$PROTOCOL" == "vless" ]] && echo ',"decryption": "none"' ) }]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {"path": "$WSPATH"}
    }
  }],
  "outbounds": [{"protocol": "freedom"}]
}
EOF

# 5. Caddyfile 写入
cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    reverse_proxy $WSPATH localhost:10000
    file_server {
        root /var/www/html
    }
}
EOF

# 6. 服务重启
cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
After=network.target nss-lookup.target
[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -c /usr/local/etc/v2ray/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable v2ray caddy
systemctl restart v2ray caddy

# 7. 链接生成逻辑
SAFE_PATH=$(echo -n "$WSPATH" | sed 's/\//%2F/g')

if [[ "$PROTOCOL" == "vless" ]]; then
    URL="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&type=ws&host=$DOMAIN&path=$SAFE_PATH#vpn-ws-$DOMAIN"
else
    VMESS_JSON=$(cat <<EOF
{
  "v": "2", "ps": "vpn-ws-$DOMAIN", "add": "$DOMAIN", "port": "443", "id": "$UUID",
  "aid": "0", "net": "ws", "type": "none", "host": "$DOMAIN", "path": "$WSPATH", "tls": "tls"
}
EOF
    )
    URL="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)#$DOMAIN"
fi

# 8. 格式化输出安装结果
clear
echo -e "${GREEN}V2Ray 安装成功！${NC}"
echo -e "-------------------------------------------------------"
echo -e "协议 (protocol) \t= ${BLUE}${PROTOCOL}${NC}"
echo -e "地址 (address) \t\t= ${BLUE}${DOMAIN}${NC}"
echo -e "端口 (port) \t\t= ${BLUE}443${NC}"
echo -e "用户ID (id) \t\t= ${BLUE}${UUID}${NC}"
echo -e "传输协议 (network) \t= ${BLUE}ws${NC}"
echo -e "伪装域名 (host) \t= ${BLUE}${DOMAIN}${NC}"
echo -e "路径 (path) \t\t= ${BLUE}${WSPATH}${NC}"
echo -e "传输层安全 (TLS) \t= ${BLUE}tls${NC}"
echo -e "------------- 链接 (URL) -------------"
echo -e "${RED}${URL}${NC}"
echo -e "-------------------------------------------------------"