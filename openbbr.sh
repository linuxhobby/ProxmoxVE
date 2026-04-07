#!/bin/bash

# ==============================================
# 一键开启 BBR (Debian 13)
# ==============================================

# 检查是否为 root
if [[ $EUID -ne 0 ]]; then
    echo "请使用 root 执行：sudo ./enable_bbr.sh"
    exit 1
fi

echo "=== 检查内核版本 ==="
KERNEL=$(uname -r | cut -d- -f1)
MAJOR=$(echo $KERNEL | cut -d. -f1)
MINOR=$(echo $KERNEL | cut -d. -f2)

if (( MAJOR < 4 || (MAJOR == 4 && MINOR < 9) )); then
    echo "内核版本过低 (当前: $KERNEL)，需要 >= 4.9 才能使用 BBR"
    exit 1
fi
echo "内核版本符合要求: $KERNEL"

echo "=== 临时开启 BBR ==="
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

echo "=== 永久生效设置 ==="
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

echo "=== 验证 BBR 是否生效 ==="
CURRENT=$(sysctl -n net.ipv4.tcp_congestion_control)
AVAILABLE=$(sysctl -n net.ipv4.tcp_available_congestion_control)

echo "当前 TCP 拥塞控制算法: $CURRENT"
echo "系统支持的拥塞算法: $AVAILABLE"

if [[ $CURRENT == "bbr" ]]; then
    echo "✅ BBR 已成功启用！"
else
    echo "❌ BBR 未启用，请检查内核或配置。"
fi
