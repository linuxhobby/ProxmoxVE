# PBS 挂载 NAS 存储配置指南

> Proxmox Backup Server 对接 NAS（群晖 / 绿联）的存储挂载方案。
> 支持协议：CIFS/SMB（群晖、绿联）、NFS（绿联）。

---

## 一、通用：PVE 添加 PBS 存储

路径：**数据中心 → 存储 → 添加 → Proxmox Backup Server**

| 字段 | 填写值 |
|------|--------|
| ID | 见各方案（如 `storage-synology` / `storage-ugreen`） |
| 服务器 | PBS 服务器 IP（如 `192.168.2.125`） |
| Datastore | 见各方案 |
| 用户名 | `root@pam`（必须包含 `@pam`） |
| 密码 | PBS 的 root 密码 |
| 指纹 | 根据实际情况填写 |

后续配置：
- **PBS**：调整精简（Prune）& GC 作业策略
- **PVE**：设置备份计划（Backup Schedule）

---

## 二、群晖 NAS（CIFS/SMB）

### 1. 安装 CIFS 客户端
```bash
apt install cifs-utils -y
```

### 2. 创建密码文件
```bash
mkdir -p /etc/samba
cat > /etc/samba/pbs-creds-synology << EOF
username=your_username
password=your_password
EOF
chmod 600 /etc/samba/pbs-creds-synology
```

### 3. 创建挂载点
```bash
mkdir -p /mnt/storage_synology
```

### 4. 创建 Datastore 子目录
> ⚠️ 必须提前手动创建，PBS 不会自动创建此目录。
```bash
mkdir -p /mnt/storage_synology/pbs-datastore
```

### 5. 写入 fstab 并挂载
```bash
echo "//192.168.2.12/PVEbackup /mnt/storage_synology cifs credentials=/etc/samba/pbs-creds-synology,vers=3.0,uid=34,gid=34,file_mode=0770,dir_mode=0770,cache=none,_netdev 0 0" >> /etc/fstab
systemctl daemon-reload
mount -a
```
> 参数说明：`vers=3.0` 明确 SMB3 避免协商失败；`uid=34,gid=34` 对应 PBS 的 `backup` 用户；`cache=none` 保证备份数据一致性；`_netdev` 等网络就绪后再挂载。

### 6. 验证挂载
```bash
su -s /bin/bash backup -c "ls /mnt/storage_synology"
```

### 7. 创建 PBS Datastore
```bash
proxmox-backup-manager datastore create storage-synology /mnt/storage_synology/pbs-datastore --tuning "gc-atime-safety-check=0"
```

### 8. PVE 添加（见第一节）
- ID：`storage-synology`，Datastore：`storage-synology`

---

## 三、绿联 NAS（CIFS/SMB）

与群晖 SMB 流程一致，仅以下参数不同：

| 项 | 值 |
|----|----|
| 密码文件 | `/etc/samba/pbs-creds-ugreen` |
| 挂载点 | `/mnt/storage_ugreen` |
| 共享路径 | `//192.168.2.11/volume1/storage500GB1` |
| Datastore ID | `storage-ugreen` |

```bash
mkdir -p /etc/samba
cat > /etc/samba/pbs-creds-ugreen << EOF
username=your_username
password=your_password
EOF
chmod 600 /etc/samba/pbs-creds-ugreen

mkdir -p /mnt/storage_ugreen/pbs-datastore

echo "//192.168.2.11/volume1/storage500GB1 /mnt/storage_ugreen cifs credentials=/etc/samba/pbs-creds-ugreen,vers=3.0,uid=34,gid=34,file_mode=0770,dir_mode=0770,cache=none,_netdev 0 0" >> /etc/fstab
systemctl daemon-reload
mount -a

su -s /bin/bash backup -c "ls /mnt/storage_ugreen"
proxmox-backup-manager datastore create storage-ugreen /mnt/storage_ugreen/pbs-datastore --tuning "gc-atime-safety-check=0"
```

---

## 四、绿联 NAS（NFS）

### 1. 安装 NFS 客户端
```bash
apt-get install nfs-common
```

### 2. 创建挂载点
```bash
mkdir -p /mnt/storage_ugreen
```

### 3. 测试手动挂载
```bash
mount -t nfs 192.168.2.11:/volume1/storage500GB1 /mnt/storage_ugreen
df -h | grep storage_ugreen
ls /mnt/storage_ugreen
```

### 4. 配置 systemd 自动挂载
> 注意：文件名必须与挂载路径严格对应，`/mnt/storage_ugreen` → `mnt-storage_ugreen`

**4.1 mount 单元** `/etc/systemd/system/mnt-storage_ugreen.mount`：
```ini
[Unit]
Description=UGREEN NAS NFS Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=192.168.2.11:/volume1/storage500GB1
Where=/mnt/storage_ugreen
Type=nfs
Options=vers=3,tcp,rw,noatime,hard,timeo=600,retrans=5,retry=0,rsize=32768,wsize=32768

[Install]
WantedBy=multi-user.target
```

**4.2 automount 单元** `/etc/systemd/system/mnt-storage_ugreen.automount`：
```ini
[Unit]
Description=UGREEN NAS NFS Automount

[Automount]
Where=/mnt/storage_ugreen
TimeoutIdleSec=0

[Install]
WantedBy=multi-user.target
```

**4.3 触发单元** `/etc/systemd/system/trigger-ugreen-mount.service`：
```ini
[Unit]
Description=Trigger UGREEN NFS Mount
After=mnt-storage_ugreen.automount network-online.target
Wants=mnt-storage_ugreen.automount

[Service]
Type=oneshot
ExecStart=/bin/ls /mnt/storage_ugreen
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**4.4 启用并启动**
```bash
systemctl daemon-reload
systemctl enable mnt-storage_ugreen.automount
systemctl start mnt-storage_ugreen.automount
ls /mnt/storage_ugreen
```

**4.5 验证状态**
```bash
systemctl status mnt-storage_ugreen.automount
systemctl status mnt-storage_ugreen.mount
```

> NFS 关键参数：`vers=3` 用 NFS v3；`tcp` TCP 传输；`noatime`/`hard`；`timeo=600`/`retrans=5`；`rsize/wsize=32768`。

### 5. 创建 PBS Datastore
```bash
mkdir -p /mnt/storage_ugreen/pbs-datastore
proxmox-backup-manager datastore create storage-ugreen /mnt/storage_ugreen/pbs-datastore
chown -R backup:backup /mnt/storage_ugreen/pbs-datastore
chmod -R 755 /mnt/storage_ugreen/pbs-datastore
```
移除 Datastore（如需）：
```bash
proxmox-backup-manager datastore remove storage-ugreen
systemctl restart proxmox-backup
systemctl restart proxmox-backup-proxy
```

---

## 五、常见问题

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| `mount -a` 报错 | SMB 版本协商失败 | 检查 `vers=3.0` 是否写入 fstab |
| `ls` 提示权限拒绝 | uid/gid 不匹配 | 确认 `backup` 用户 uid/gid 为 34 |
| PBS Datastore 创建失败 | 子目录不存在 | 先手动创建 `pbs-datastore` |
| 重启后挂载丢失 | 缺少 `_netdev` | 检查 fstab 中 `_netdev` 是否存在 |
| NFS 挂载超时 | 网络/防火墙 | 检查 `timeo`/`retrans` 与联通性 |
