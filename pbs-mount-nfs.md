一、去掉登录订阅弹窗（适用于 PBS 4.1.0）
# 备份原文件
cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
   /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak

# 去掉弹窗
sed -i "s/res.data.status.toLowerCase() !== 'active'/false/" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

######## 重新来一遍

# PBS 端

1. 安装NFS客户端
apt-get install nfs-common

2. 创建挂载点
mkdir -p /mnt/storage_ugreen

3. 测试手动挂载
mount -t nfs 192.168.2.11:/volume1/storage500GB1 /mnt/storage_ugreen

验证是否成功
df -h | grep storage_ugreen

ls /mnt/storage_ugreen

4. 设置开机自动挂载（/etc/fstab）systemctl daemon-reload
vi /etc/fstab
添加：
echo "192.168.2.11:/volume1/storage500GB1 /mnt/storage_ugreen nfs vers=3,tcp,rw,nolock,noatime,hard,intr,timeo=30,retrans=3,rsize=32768,wsize=32768 0 0" >> /etc/fstab

关键参数说明：
_netdev — 等网络就绪后再挂载（PBS服务器重要）
hard,intr — 网络中断时不丢失任务
timeo=30 — 超时30秒重试
retrans=3 — 重试3次

5.PBS Datastore创建
# 创建空目录
mkdir -p /mnt/storage_ugreen/pbs-datastore
# 创建Datastore
proxmox-backup-manager datastore create storage-ugreen /mnt/storage_ugreen/pbs-datastore
chown -R backup:backup /mnt/storage_ugreen/pbs-datastore
chmod -R 755 /mnt/storage_ugreen/pbs-datastore

#移除Datastore
proxmox-backup-manager datastore remove storage_ugreen

systemctl restart proxmox-backup
systemctl restart proxmox-backup-proxy

6.PVE Web界面 → 数据中心 → 存储 → 添加 → Proxmox Backup Server
ID：nas-backup
服务器：pbs服务器ip，根据实际情况填写
Datastore：nas-storage
用户名：root@pam，必须加上@pam
密码：PBS的root密码，根据实际情况填写
指纹：根据实际情况填写


PBS：调整精简&GC作业即可。
PVE：设置备份计划即可。
