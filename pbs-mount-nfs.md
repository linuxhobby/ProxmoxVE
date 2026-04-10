1. 安装NFS客户端
apt-get install nfs-common

2. 创建挂载点
mkdir -p /mnt/nas_storage

3. 测试手动挂载
mount -t nfs 192.168.2.11:/volume1/storage500GB1 /mnt/nas_storage
验证是否成功
df -h | grep nas_storage
ls /mnt/nas_storage

4. 设置开机自动挂载（/etc/fstab）
vi /etc/fstab
添加：
192.168.2.11:/volume1/storage500GB1  /mnt/nas_storage  nfs  defaults,_netdev,rw,hard,intr,timeo=30,retrans=3  0  0
关键参数说明：
_netdev — 等网络就绪后再挂载（PBS服务器重要）
hard,intr — 网络中断时不丢失任务
timeo=30 — 超时30秒重试
retrans=3 — 重试3次

验证fstab配置：
5. 在PBS中配置作业使用NFS路径
在PBS作业脚本中指定输出到NFS路径：
#!/bin/bash
#PBS -N my_job
#PBS -o /mnt/nas_storage/output/
#PBS -e /mnt/nas_storage/output/
#PBS -l nodes=1:ppn=4

cd /mnt/nas_storage/jobs/
# 你的计算命令
常见排查
# 检查NFS服务器是否可达
showmount -e 192.168.2.11

# 查看挂载状态
mount | grep nfs

# 检查权限
ls -la /mnt/nas_storage

如果 showmount -e 192.168.2.11 能看到 /volume1/storage500GB1，说明NFS共享配置正确，可以正常挂载。