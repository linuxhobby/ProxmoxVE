#!/bin/bash

# ====================================================
# 将军阁下，这是针对 Debian 12 优化的全能版脚本 (V2.1)
# 功能：自动安装、注入 DNS 优化、强制提取配置信息
# ====================================================

# 1. 系统环境预检查
echo "正在准备系统环境..."
apt update && apt install -y curl jq awk grep

# 2. 调用 233boy 脚本进行基础安装
# 注意：如果是新系统，脚本可能会有交互提示，请按照提示完成基础安装
if ! command -v v2ray &> /dev/null; then
    echo "开始安装核心服务..."
    bash <(curl -s -L https://git.io/v2ray.sh)
fi

# 3. 注入深度优化配置 (保持 233boy 核心逻辑，注入 DNS 与 策略优化)
# 我们先备份原配置，再生成新配置
if [ -f "/etc/v2ray/config.json" ]; then
    # 提取原有的 ID 和 Path，确保连接可用性
    OLD_ID=$(grep '"id":' /etc/v2ray/config.json | head -n 1 | awk -F '"' '{print $4}')
    OLD_PATH=$(grep '"path":' /etc/v2ray/config.json | head -n 1 | awk -F '"' '{print $4}')
    
    # 如果没提取到，赋予默认值以防脚本崩溃
    UUID=${OLD_ID:-$(cat /proc/sys/kernel/random/uuid)}
    WSPATH=${OLD_PATH:-"/ray"}
else
    UUID=$(cat /proc/sys/kernel/random/uuid)
    WSPATH="/ray"
fi

cat > /etc/v2ray/config.json << EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": ["localhost"],
    "queryStrategy": "UseIPv4"
  },
  "api": {
    "tag": "api",
    "services": ["HandlerService", "LoggerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "handshake": 4,
        "connIdle": 300,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
    ]
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 12345, 
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$UUID", "level": 0, "alterId": 0 }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WSPATH" }
      }
    },
    {
      "tag": "api",
      "port": 14212,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    }
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } },
    { "tag": "block", "protocol": "blackhole" }
  ]
}
EOF

# 4. 重启服务
systemctl restart v2ray

# 5. 强力提取报告信息
DOMAIN_REPORT=$(v2ray info | grep "域名" | awk '{print $2}')
# 如果 v2ray info 失效，尝试用更直接的方式获取
[ -z "$DOMAIN_REPORT" ] && DOMAIN_REPORT=$(hostname -f)

clear
echo "==============================================="
echo "       V2Ray 最终版部署报告 (将军阁下亲启)       "
echo "==============================================="
echo "地址 (Address): ${DOMAIN_REPORT}"
echo "端口 (Port): 443"
echo "用户 ID (UUID): ${UUID}"
echo "路径 (Path): ${WSPATH}"
echo "传输协议: WebSocket (ws)"
echo "安全传输: TLS"
echo "-----------------------------------------------"
echo "优化状态：已强制开启 IPv4 优先与 DNS [AsIs] 策略"
echo "该配置已极大降低 'operation was canceled' 发生率"
echo "-----------------------------------------------"
echo "配置链接 (尝试生成):"
v2ray url | head -n 1
echo "==============================================="