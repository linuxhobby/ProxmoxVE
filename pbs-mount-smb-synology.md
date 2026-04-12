# PBS 挂载群晖 NAS（CIFS）配置指南

---

## 步骤 1：安装 CIFS 客户端

```bash
apt install cifs-utils -y
```

---

## 步骤 2：创建密码文件

```bash
cat > /etc/samba/pbs-creds << EOF
username=username
password=password
EOF
chmod 600 /etc/samba/pbs-creds
```

---

## 步骤 3：创建挂载点

```bash
mkdir -p /mnt/storage_synology
```

---

## 步骤 4：写入 fstab 并挂载

```bash
# 写入 fstab
echo "//192.168.2.12/PVEbackup /mnt/storage_synology cifs credentials=/etc/samba/pbs-creds,uid=34,gid=34,file_mode=0770,dir_mode=0770,cache=none,_netdev 0 0" >> /etc/fstab

# 挂载
mount -a
```

---

## 步骤 5：验证挂载

```bash
su -s /bin/bash backup -c "ls /mnt/storage_synology"
```

---

## 步骤 6：创建 PBS Datastore

```bash
proxmox-backup-manager datastore create storage-synology /mnt/storage_synology/pbs-datastore --tuning "gc-atime-safety-check=0"
```

---

## 步骤 7：PVE 添加 PBS 存储

路径：**数据中心 → 存储 → 添加 → Proxmox Backup Server**

| 字段 | 填写值 |
|------|--------|
| ID | `storage-synology` |
| 服务器 | `192.168.2.125`（PBS 的 IP） |
| 用户名 | `root@pam` |
| 密码 | PBS 的 root 密码 |
| 数据存储 | `storage-synology` |
