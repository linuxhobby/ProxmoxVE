#!/bin/bash

# --- 1. 环境初始化 ---
apt update && apt install -y curl wget jq uuid-runtime unzip net-tools

# --- 2. 参数设定 (请根据需要修改域名) ---
DOMAIN="rc.myvpsworld.top"
UUID="db475d79-722b-403c-9428-af30c9c4642e"
WSPATH="/y0zytjud6p"
PORT=10000

# --- 3. 安装 V2Ray 5.x 核心 ---
mkdir -p /usr/local/bin /etc/v2ray /var/www/html
latest_version=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest | jq -r .tag_name)
wget -q -O /tmp/v2ray.zip "https://github.com/v2fly/v2ray-core/releases/download/${latest_version}/v2ray-linux-64.zip"
unzip -o /tmp/v2ray.zip -d /tmp/v2ray_tmp
cp /tmp/v2ray_tmp/v2ray /usr/local/bin/
chmod +x /usr/local/bin/v2ray
rm -rf /tmp/v2ray.zip /tmp/v2ray_tmp

# --- 4. 写入 V5 标准配置文件 (借鉴 233boy 的精密结构) ---
cat <<EOF > /etc/v2ray/config.json
{
  "inbounds": [
    {
      "port": $PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "decryption": "none"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "$WSPATH"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
EOF

# --- 5. 安装并配置 Caddy ---
if ! command -v caddy &> /dev/null; then
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update && apt install caddy -y
fi

cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    reverse_proxy $WSPATH localhost:$PORT
    file_server {
        root /var/www/html
    }
}
EOF

# --- 6. 写入 Systemd 服务 ---
cat <<EOF > /etc/systemd/system/v2ray.service
[Unit]
Description=V2Ray Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray run -c /etc/v2ray/config.json
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# --- 7. 发起总攻 ---
systemctl daemon-reload
systemctl enable v2ray caddy
systemctl restart v2ray caddy

# --- 8. 战果汇报 ---
echo "--------------------------------------------------"
echo "部署完成，将军阁下！"
echo "域名: $DOMAIN"
echo "端口: 443"
echo "UUID: $UUID"
echo "路径: $WSPATH"
echo "传输: WebSocket + TLS"
echo "--------------------------------------------------"
netstat -tulpn | grep :$PORT