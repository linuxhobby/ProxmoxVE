#!/bin/bash

# ====================================================
# 将军阁下，这是增强了链接自动拼接功能的 V2.3 脚本
# 优化点：自动计算 UUID/Path 并输出完整分享链接
# ====================================================

CONFIG_FILE="/etc/v2ray/config.json"

# --- 1. 环境准备 ---
install_base() {
    apt update && apt install -y curl jq awk grep
    if ! command -v v2ray &> /dev/null; then
        bash <(curl -s -L https://git.io/v2ray.sh)
    fi
}

# --- 2. 核心配置写入与优化 ---
write_config() {
    local PROTOCOL=$1
    local UUID=$2
    local WSPATH=$3

    # 注入您要求的 DNS 优化与 IPv4 策略
    cat > $CONFIG_FILE << EOF
{
  "log": { "loglevel": "warning" },
  "dns": { "servers": ["localhost"], "queryStrategy": "UseIPv4" },
  "inbounds": [{
    "port": 12345,
    "listen": "127.0.0.1",
    "protocol": "$PROTOCOL",
    "settings": {
      "clients": [ { "id": "$UUID", "level": 0 } ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": { "path": "$WSPATH" }
    }
  }],
  "outbounds": [
    { "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" } }
  ]
}
EOF
    systemctl restart v2ray
}

# --- 3. 链接拼接逻辑 ---
generate_link() {
    local PROTOCOL=$(jq -r '.inbounds[0].protocol' $CONFIG_FILE)
    local UUID=$(jq -r '.inbounds[0].settings.clients[0].id' $CONFIG_FILE)
    local WSPATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' $CONFIG_FILE)
    # 获取域名
    local DOMAIN=$(v2ray info | grep "域名" | awk '{print $2}')
    [ -z "$DOMAIN" ] && DOMAIN=$(hostname -f)
    
    # 对路径进行 URL 编码处理
    local ENCODED_PATH=$(echo -n "$WSPATH" | jq -sRr @uri)
    local REMARK="Racknerd-Debian12"

    if [ "$PROTOCOL" == "vless" ]; then
        # VLESS 拼接格式
        echo "vless://${UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${ENCODED_PATH}#${REMARK}"
    else
        # VMess 拼接格式 (Base64)
        local VMESS_JSON=$(cat <<EOF
{ "v": "2", "ps": "${REMARK}", "add": "${DOMAIN}", "port": "443", "id": "${UUID}", "aid": "0", "net": "ws", "type": "none", "host": "${DOMAIN}", "path": "${WSPATH}", "tls": "tls" }
EOF
)
        echo "vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"
    fi
}

# --- 4. 交互菜单 ---
show_menu() {
    clear
    echo "==============================================="
    echo "       V2Ray 增强链接面板 (将军阁下亲启)       "
    echo "==============================================="
    echo " 1) 安装/重置为: VLESS-WS-TLS"
    echo " 2) 安装/重置为: VMess-WS-TLS"
    echo " 3) 查看当前配置报告与链接"
    echo " 4) 增加一条新 UUID (多用户)"
    echo " 5) 彻底删除配置"
    echo " 0) 退出"
    echo "-----------------------------------------------"
    read -p "选择指令: " num

    case "$num" in
        1|2)
            install_base
            local PROT="vless"
            [ "$num" == "2" ] && PROT="vmess"
            local NEW_ID=$(cat /proc/sys/kernel/random/uuid)
            local NEW_PATH="/$(cat /proc/sys/kernel/random/uuid | cut -c1-8)"
            write_config "$PROT" "$NEW_ID" "$NEW_PATH"
            echo "部署完成！"
            view_report
            ;;
        3) view_report ;;
        4) add_user ;;
        5) rm -f $CONFIG_FILE && systemctl stop v2ray && echo "已清理。" ;;
        0) exit 0 ;;
    esac
}

# --- 5. 报告输出 ---
view_report() {
    if [ ! -f "$CONFIG_FILE" ]; then echo "请先安装！"; return; fi
    echo "-----------------------------------------------"
    echo "配置生成的分享链接如下："
    generate_link
    echo "-----------------------------------------------"
    read -p "回车返回..."
}

# --- 6. 增加用户 ---
add_user() {
    local NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
    jq ".inbounds[0].settings.clients += [{\"id\": \"$NEW_UUID\", \"level\": 0}]" $CONFIG_FILE > tmp.json && mv tmp.json $CONFIG_FILE
    systemctl restart v2ray
    echo "新 UUID 已添加: $NEW_UUID"
    read -p "回车返回..."
}

while true; do show_menu; done