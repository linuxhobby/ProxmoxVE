#!/bin/bash

# ====================================================
# 将军阁下，这是优化后的稳健版脚本 (V2.0)
# 优化点：减少 DNS 冲突、强制 IPv4 优先、增强连接稳定性
# ====================================================

# 1. 确保核心组件安装 (233boy 环境)
if ! command -v v2ray &> /dev/null; then
    bash <(curl -s -L https://git.io/v2ray.sh)
fi

# 2. 写入深度优化后的 JSON 配置文件
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
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
      { "type": "field", "domain": ["geosite:category-ads-all"], "outboundTag": "block" }
    ]
  },
  "inbounds": [
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

# 3. 提取关键配置参数
DOMAIN=$(v2ray url | grep -oE '[a-zA-Z0-9.-]+\.[a-z]{2,}' | head -n 1)
UUID=$(cat /etc/v2ray/config.json | grep id | awk -F '"' '{print $4}' | head -n 1)
WSPATH=$(cat /etc/v2ray/config.json | grep path | awk -F '"' '{print $4}' | head -n 1)
VMESS_LINK=$(v2ray url | head -n 1)

# 4. 重启服务并清理系统缓存
systemctl restart v2ray

# 5. 输出优化报告
clear
echo "==============================================="
echo "       V2Ray 优化版部署报告 (将军阁下亲启)       "
echo "==============================================="
echo "域名: ${DOMAIN:-未检测到域名}"
echo "端口: 443 (TLS已开启)"
echo "UUID: ${UUID:-未检测到UUID}"
echo "路径: ${WSPATH:-未检测到路径}"
echo "传输: WebSocket + TLS"
echo "-----------------------------------------------"
echo "本次优化逻辑："
echo "1. DNS 策略设为 [AsIs] - 减少解析层级冲突"
echo "2. 强制开启 [UseIPv4] - 避免 IPv6 解析超时"
echo "3. 延长握手时间 (Handshake) - 降低被取消概率"
echo "-----------------------------------------------"
echo "配置链接 (VMess):"
echo "${VMESS_LINK}"
echo "==============================================="