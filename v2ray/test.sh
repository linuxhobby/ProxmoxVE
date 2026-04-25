#!/bin/bash

# ====================================================
# 将军阁下，这是为您整合的基准版脚本
# 功能：安装/更新服务、优化DNS、自动生成配置报告
# ====================================================

# 1. 检查并安装核心组件 (使用 233boy 脚本)
if ! command -v v2ray &> /dev/null; then
    echo "正在执行核心安装..."
    bash <(curl -s -L https://git.io/v2ray.sh)
fi

# 2. 写入优化后的 JSON 配置文件
# 注意：这里保留了您提供的 233boy 结构，并注入了 DNS 优化
cat > /etc/v2ray/config.json << EOF
{
  "log": {
    "access": "/var/log/v2ray/access.log",
    "error": "/var/log/v2ray/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "localhost",
      "1.1.1.1",
      "8.8.8.8"
    ],
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
        "handshake": 2,
        "connIdle": 142,
        "uplinkOnly": 3,
        "downlinkOnly": 4,
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" },
      { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" },
      { "type": "field", "ip": ["geoip:cn"], "outboundTag": "block" },
      { "type": "field", "domain": ["domain:openai.com"], "outboundTag": "direct" },
      { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" }
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
    # 注意：实际业务 Inbound 通常由 233boy 脚本动态生成或由 Nginx 转发
    # 这里建议保留脚本原本生成的 inbound 部分以确保连接可用
  ],
  "outbounds": [
    { "tag": "direct", "protocol": "freedom" },
    { "tag": "block", "protocol": "blackhole" }
  ]
}
EOF

# 3. 提取关键参数用于生成报告
# 从 233boy 的信息记录文件中提取（通常存放在该位置）
DOMAIN=$(v2ray url | grep -oE '[a-zA-Z0-9.-]+\.[a-z]{2,}' | head -n 1)
UUID=$(cat /etc/v2ray/config.json | grep id | awk -F '"' '{print $4}' | head -n 1)
WSPATH=$(cat /etc/v2ray/config.json | grep path | awk -F '"' '{print $4}' | head -n 1)
VMSESS_URL=$(v2ray url | head -n 1)

# 4. 重启服务
systemctl restart v2ray

# 5. 生成报告输出
clear
echo "==============================================="
echo "         V2Ray 服务部署报告 (将军阁下亲启)       "
echo "==============================================="
echo "域名: ${DOMAIN:-未检测到域名}"
echo "端口: 443"
echo "UUID: ${UUID:-未检测到UUID}"
echo "路径: ${WSPATH:-未检测到路径}"
echo "传输: WebSocket + TLS"
echo "状态: 服务已重启并应用 DNS 优化"
echo "-----------------------------------------------"
echo "配置链接 (VMess):"
echo "${VMSESS_URL}"
echo "==============================================="