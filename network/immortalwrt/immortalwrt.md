# ImmortalWrt 安装与配置

> 在 PVE 中部署 ImmortalWrt / OpenWrt 软路由的完整流程。

---

## 一、安装（PVE 导入镜像）

1. 在 PVE 中建立 bridge：`vmbr1`、`vmbr2`、`vmbr3`（很重要）
2. 加载镜像
```bash
qm importdisk 100 /var/lib/vz/template/iso/immortalwrt-23.05.7-x86-64-generic-ext4-combined-efi.img local-lvm
qm importdisk 900 /var/lib/vz/template/iso/immortalwrt-23.05.7-x86-64-generic-ext4-combined-efi-2g-swap.img local-lvm
# OpenWrt 版本：
qm importdisk 600 /var/lib/vz/template/iso/openwrt-23.05.6-x86-64-generic-ext4-combined-efi.img local-lvm
```
3. 修改 `/etc/config/network`，lan ip=192.168.2.1，重启网络：`service network restart`

---

## 二、修改软件源（国内镜像）

方法 1（sed 替换）：
```bash
sed -e 's,https://downloads.immortalwrt.org,https://mirrors.zju.edu.cn/immortalwrt,g' \
    -e 's,https://mirrors.vsean.net/openwrt,https://mirrors.zju.edu.cn/immortalwrt,g' \
    -i.bak /etc/opkg/distfeeds.conf
```
方法 2（直接在【系统】→【软件包】→【配置 opkg】替换）：
```
src/gz immortalwrt_core https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/targets/x86/64/packages
src/gz immortalwrt_base https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/packages/x86_64/base
src/gz immortalwrt_kmods https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/targets/x86/64/kmods/5.15.195-1-b43b3018862131fe596535b496468fb0
src/gz immortalwrt_luci https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/packages/x86_64/luci
src/gz immortalwrt_packages https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/packages/x86_64/packages
src/gz immortalwrt_routing https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/packages/x86_64/routing
src/gz immortalwrt_telephony https://mirrors.zju.edu.cn/immortalwrt/releases/23.05.7/packages/x86_64/telephony
```
OpenWrt 镜像：
```bash
sed -i 's_https\?://downloads.openwrt.org_https://mirrors.tuna.tsinghua.edu.cn/openwrt_' /etc/opkg/distfeeds.conf
```

---

## 三、增加交换分区
```bash
dd if=/dev/zero of=/overlay/swapfile bs=1M count=512
chmod 600 /overlay/swapfile
mkswap /overlay/swapfile
swapon /overlay/swapfile
sed -i '/^exit 0/i swapon /overlay/swapfile' /etc/rc.local
reboot
```

---

## 四、安装插件与工具
```bash
opkg update
opkg install luci-theme-argon qemu-ga ipset ipt2socks iptables \
  iptables-mod-conntrack-extra iptables-mod-iprange iptables-mod-socket \
  iptables-mod-tproxy kmod-ipt-nat luci-app-passwall luci-i18n-passwall-zh-cn \
  usbutils kmod-rtl8192cu wireless-tools kmod-mac80211 kmod-cfg80211 \
  hostapd-common wpad-openssl

uci set wireless.radio0.disabled='0'
uci commit wireless
wifi up
```

---

## 五、PassWall 设置
1. 新增节点
2. 更新规则
3. 启动

---

## 六、IPv4/IPv6 转发与 BBR
```bash
opkg install kmod-tcp-bbr
modprobe tcp_bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
# 检测
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding
sysctl net.ipv4.tcp_congestion_control
```

---

## 七、WAN / LAN 设置
（按实际网络规划配置 WAN 拨号与 LAN 网段，略）

---

## 八、防火墙配置

> 修改 synflood 变量名、WAN 增加 wwan 接口、添加 Tailscale P2P 规则。

```bash
# 1. synflood 变量名修正
uci set firewall.@defaults[0].synflood_protect='1'
uci delete firewall.@defaults[0].syn_flood

# 2. WAN 区域安全设置
uci set firewall.@zone[1].name='wan'
uci set firewall.@zone[1].input='REJECT'
uci set firewall.@zone[1].forward='REJECT'
uci set firewall.@zone[1].output='ACCEPT'
uci set firewall.@zone[1].masq='1'
uci set firewall.@zone[1].mtu_fix='1'
uci add_list firewall.@zone[1].network='wan'
uci add_list firewall.@zone[1].network='wan6'
uci add_list firewall.@zone[1].network='wwan'

# 3. LAN 区域保持内网正常
uci set firewall.@zone[0].name='lan'
uci set firewall.@zone[0].input='ACCEPT'
uci set firewall.@zone[0].forward='ACCEPT'
uci set firewall.@zone[0].output='ACCEPT'
uci set firewall.@zone[0].network='lan'

# 4. LAN -> WAN 允许转发
uci set firewall.@forwarding[0].src='lan'
uci set firewall.@forwarding[0].dest='wan'

# 5. 添加 Tailscale P2P 规则（先查重避免重复添加）
uci add firewall rule
uci set firewall.@rule[-1].name='Tailscale-P2P'
uci set firewall.@rule[-1].src='wan'
uci set firewall.@rule[-1].dest='lan'
uci set firewall.@rule[-1].dest_port='41641'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

# 6. 提交并重启防火墙
uci commit firewall
/etc/init.d/firewall restart
```

> 说明：原有规则（Allow-DHCP-Renew、Allow-Ping、Allow-IGMP、Allow-DHCPv6、Allow-MLD、Allow-ICMPv6-*、Allow-IPSec-ESP、Allow-ISAKMP、passwall、passwall_server）全部保留，不改动。

---

## 九、PassWall 名单
域名代理/拦截名单见 `passwall-lists.md`。
