# Tailscale CLI Reference

## 连接

| 命令 | 描述 |
|------|------|
| `up` | 连接到 Tailscale，如需时进行登录 |
| `down` | 从 Tailscale 断开连接 |
| `set` | 更改指定的首选项 |

## 账号

| 命令 | 描述 |
|------|------|
| `login` | 登录到 Tailscale 账户 |
| `logout` | 断开连接并使当前节点密钥失效 |
| `switch` | 切换到不同的 Tailscale 账户 |

## 网络诊断

| 命令 | 描述 |
|------|------|
| `netcheck` | 显示本地网络条件分析 |
| `ping` | 在 Tailscale 层 ping 主机，查看路由情况 |
| `status` | 显示 tailscaled 及其连接的状态 |
| `ip` | 显示 Tailscale IP 地址 |

## 连接工具

| 命令 | 描述 |
|------|------|
| `nc` | 连接到主机上的端口，接入 stdin/stdout |
| `ssh` | SSH 到 Tailscale 机器 |
| `file` | 发送或接收文件 |

## 对外服务

| 命令 | 描述 |
|------|------|
| `funnel` | 在公网上暴露内容和本地服务器 |
| `serve` | 在 tailnet 内部提供内容和本地服务器 |
| `cert` | 获取 TLS 证书 |

## 系统管理

| 命令 | 描述 |
|------|------|
| `configure` | 配置主机以启用更多 Tailscale 功能 |
| `lock` | 管理 tailnet 锁定 |
| `update` | 将 Tailscale 更新到最新或指定版本 |
| `web` | 运行用于控制 Tailscale 的 Web 服务器 |

## 其他

| 命令 | 描述 |
|------|------|
| `version` | 显示 Tailscale 版本 |
| `bugreport` | 显示可共享的标识符以帮助诊断问题 |
| `licenses` | 获取开源许可信息 |
