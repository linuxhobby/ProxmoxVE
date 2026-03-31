#!/bin/bash

# PVE 配置文件备份 #
# ========== 配置 ==========
BACKUP_DIR="/var/lib/vz/dump/"   # 备份存放目录，按需修改
KEEP_DAYS=30                           # 保留天数
LOG="/var/log/pve-backup.log"

# ========== 开始备份 ==========
DATE=$(date +%Y%m%d)
FILENAME="pve-config-${DATE}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始备份..." >> "$LOG"

tar czf "${BACKUP_DIR}/${FILENAME}" \
  /etc/pve \
  /etc/network/interfaces \
  /etc/hosts \
  /etc/hostname \
  /etc/fstab \
  /etc/ssh \
  /root 2>> "$LOG"

if [ $? -eq 0 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份成功：${FILENAME}" >> "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] 备份失败！" >> "$LOG"
  exit 1
fi

# ========== 清理旧备份 ==========
find "$BACKUP_DIR" -name "pve-config-*.tar.gz" -mtime +${KEEP_DAYS} -delete
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已清理 ${KEEP_DAYS} 天前的旧备份" >> "$LOG"
