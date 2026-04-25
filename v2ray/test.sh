#!/bin/bash

# ====================================================
# 将军阁下，这是修正了语法闭合问题的 V3.2 脚本
# 修复：EOF 标记对齐、循环闭合、Debian 12 环境包名
# ====================================================

CONFIG_FILE="/etc/v2ray/config.json"

# --- 1. 环境准备 ---
prepare_env() {
    echo "正在安装必要依赖..."
    apt update && apt install -y curl jq gawk grep base64 python3-minimal
    if ! command -v v2ray &> /dev/null; then
        echo "正在安装 V2Ray 核心..."
        bash <(curl -s -L https://git.io/v2ray.sh)
    fi
}

# --- 2. 写入配置 ---
apply_config() {
    local PROTO=$1
    local UUID=$2
    local PATH_STR=$3

    # 注意：EOF 后面不能有任何空格
    cat > $CONFIG_FILE <<EOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": ["localhost"], "queryStrategy": "UseIPv4" },
  "policy": { "levels": { "0": { "handshake": 5, "connIdle": 300 } } },
  "inbounds": [{
    "port": 12345,
    "listen": "127.0.0.1",
    "protocol": "$PROTO",
    "settings": { "clients": [ { "id": "$UUID", "level": 0 } ], "decryption": "none" },
    "streamSettings": { "network": "ws", "wsSettings": { "path": "$PATH_STR" } }
  }],
  "outbounds": [{ "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }]
}
EOF
    systemctl restart v2ray
}

# --- 3. 生成链接 ---
output_links() {
    if [ ! -f "$CONFIG_FILE" ]; then echo "配置文件不存在！"; return; fi
    
    local PROTO=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local ID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    local PR=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    local ADDR=$(hostname -f)
    local P_ENC=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PR', safe=''))")
    
    echo "-----------------------------------------------"
    if [ "$PROTO" == "vless" ]; then
        echo "VLESS 链接: vless://${ID}@${ADDR}:443?encryption=none&security=tls&type=ws&host=${ADDR}&path=${P_ENC}#Racknerd_V3"
    else
        local VM_J=$(cat <<EOF
{ "v": "2", "ps": "Racknerd_V3", "add": "${ADDR}", "port": "443", "id": "${ID}", "aid": "0", "net": "ws", "type": "none", "host": "${ADDR}", "path": "${PR}", "tls": "tls" }
EOF
)
        echo "VMess 链接: vmess://$(echo -n "$VM_J" | base64 -w 0)"
    fi
    echo "-----------------------------------------------"
}

# --- 4. 主循环 ---
while true; do
    echo "1) 部署 VLESS-WS-TLS"
    echo "2) 部署 VMess-WS-TLS"
    echo "3) 查看链接"
    echo "4) 清理并退出"
    read -p "选择 [1-4]: " opt
    case \$opt in
        1|2)
            prepare_env
            P="vless"; [ "\$opt" == "2" ] && P="vmess"
            U=\$(cat /proc/sys/kernel/random/uuid)
            W="/ray\$(cat /proc/sys/kernel/random/uuid | cut -c1-4)"
            apply_config "\$P" "\$U" "\$W"
            output_links
            ;;
        3) output_links ;;
        4) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done