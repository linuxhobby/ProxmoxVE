# PBS 挂载绿联 NAS（CIFS/SMB）配置指南

---

## 步骤 1：安装 CIFS 客户端

```bash
apt install cifs-utils -y
```

---

## 步骤 2：创建密码文件

```bash
# 确保目录存在
mkdir -p /etc/samba

cat > /etc/samba/pbs-creds-ugreen << EOF
username=your_username
password=your_password
EOF

chmod 600 /etc/samba/pbs-creds-ugreen
```

---

## 步骤 3：创建挂载点

```bash
mkdir -p /mnt/storage_ugreen
```

---

## 步骤 4：创建 PBS Datastore 子目录

> ⚠️ 必须提前手动创建，PBS 不会自动创建此目录。

```bash
mkdir -p /mnt/storage_ugreen/pbs-datastore
```

---

## 步骤 5：写入 fstab 并挂载

```bash
# 写入 fstab（明确指定 SMB 版本，避免协商失败）
echo "//192.168.2.11/volume1/storage500GB1 /mnt/storage_ugreen cifs credentials=/etc/samba/pbs-creds-ugreen,vers=3.0,uid=34,gid=34,file_mode=0770,dir_mode=0770,cache=none,_netdev 0 0" >> /etc/fstab

systemctl daemon-reload

# 挂载
mount -a
```

> **参数说明：**
> - `vers=3.0`：明确使用 SMB3 协议，避免版本协商失败
> - `uid=34,gid=34`：对应 PBS 的 `backup` 用户，确保有读写权限
> - `file_mode=0770,dir_mode=0770`：owner/group 可读写，其他用户无权限
> - `cache=none`：禁用客户端缓存，保证数据一致性（备份场景推荐）
> - `_netdev`：等待网络就绪后再挂载，防止开机失败

---

## 步骤 6：验证挂载

```bash
# 用 backup 用户身份验证权限
su -s /bin/bash backup -c "ls /mnt/storage_ugreen"
```

---

## 步骤 7：创建 PBS Datastore

```bash
proxmox-backup-manager datastore create storage-ugreen /mnt/storage_ugreen/pbs-datastore --tuning "gc-atime-safety-check=0"
```

---

## 步骤 8：PVE 添加 PBS 存储

路径：**数据中心 → 存储 → 添加 → Proxmox Backup Server**

| 字段 | 填写值 |
|------|--------|
| ID | `storage-ugreen` |
| 服务器 | `192.168.2.125`（PBS 的 IP） |
| 用户名 | `root@pam` |
| 密码 | PBS 的 root 密码 |
| 数据存储 | `storage-ugreen` |

---

## 常见问题

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| `mount -a` 报错 | SMB 版本协商失败 | 检查 `vers=3.0` 是否写入 fstab |
| `ls` 提示权限拒绝 | uid/gid 不匹配 | 确认 `backup` 用户 uid/gid 为 34 |
| PBS Datastore 创建失败 | 子目录不存在 | 执行步骤 4 手动创建目录 |
| 重启后挂载丢失 | 缺少 `_netdev` | 检查 fstab 中 `_netdev` 是否存在 |