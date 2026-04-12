# Proxmox Virtual Environment 笔记

> 最后更新：2026/04/07

---

## 目录

- [安装 Debian 13 后执行自动化脚本](#安装-debian-13-后执行自动化脚本)
- [PVE Tools 自动化脚本](#pve-tools-自动化脚本)
  - [pve_source](#pve_source)
  - [pve-tools](#pve-tools)
  - [更改 CT 模板源](#更改-ct-模板源)
  - [关闭订阅弹窗](#关闭订阅弹窗)
- [虚拟机安装和配置](#虚拟机安装和配置)
- [PVE 配置备份与恢复](#pve-配置备份与恢复)
  - [备份步骤](#一备份步骤)
  - [恢复步骤](#二恢复步骤)

---

## 安装 Debian 13 后执行自动化脚本

```bash
apt update
apt install curl -y
bash <(curl -fsSL https://raw.githubusercontent.com/linuxhobby/ProxmoxVEDocumentation/refs/heads/main/debianinstall.sh)
```

---

## PVE Tools 自动化脚本

### pve_source

```bash
wget -q -O /root/pve_source.tar.gz 'http://szrq.hkfree.work/pve-source/pve_source.tar.gz' \
  && tar zxvf /root/pve_source.tar.gz \
  && /root/./pve_source
```

### pve-tools

```bash
bash <(curl -sSL https://ghfast.top/raw.githubusercontent.com/Mapleawaa/PVE-Tools-9/main/PVE-Tools.sh)
```

### 更改 CT 模板源

将 CT 模板下载源替换为清华大学镜像：

```bash
cp /usr/share/perl5/PVE/APLInfo.pm /usr/share/perl5/PVE/APLInfo.pm_back
sed -i 's|http://download.proxmox.com|https://mirrors.tuna.tsinghua.edu.cn/proxmox|g' \
  /usr/share/perl5/PVE/APLInfo.pm
```

### 关闭订阅弹窗(同样适用关闭【PBS】)  

```bash
sed -Ezi.bak \
  "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
  && systemctl restart pveproxy.service
```
如果是pbs，执行以下指令
```bash
sed -Ezi.bak \
  "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" \
  /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js \
  && systemctl restart proxmox-backup
  && systemctl restart proxmox-backup-proxy
```
---

## 虚拟机安装和配置

| 脚本 / 文件 | 说明 |
|---|---|
| `install-immortalwrt` | 安装 ImmortalWrt 的步骤 |
| `setup-v2ray` | V2Ray 的配置 |
| `pve-backup.sh` | PVE 配置文件备份 |
| `pve-tools.sh` | PVE 美化脚本 |

---

## PVE 配置备份与恢复

### 一、备份步骤

在 PVE 中添加计划任务，将 `pve-backup.sh` 脚本放入 `/usr/local/bin/` 目录，然后添加 cron 任务：

```bash
crontab -e
```

在编辑器中添加以下一行（每周四凌晨 3 点执行一次）：

```
0 3 * * 4 /usr/local/bin/pve-backup.sh
```

---

### 二、恢复步骤

**第 1 步：解压备份**

```bash
tar xzf pveconfig-20261212.tar.gz -C /   # 根据实际文件名修改
```

**第 2 步：恢复网络配置（重要！先不要重启）**

检查 `/etc/network/interfaces` 是否适配新机器的网卡名：

```bash
ip link show                        # 查看当前网卡名
nano /etc/network/interfaces        # 确认网卡名一致
```

**第 3 步：重启集群服务**

```bash
systemctl restart pve-cluster
systemctl restart pvedaemon
systemctl restart pveproxy
```

**第 4 步：恢复 SSH**

```bash
systemctl restart ssh
```

**第 5 步：重启宿主机**

```bash
reboot
```