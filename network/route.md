# 路由器刷机

## 解密配置文件

```bash
openssl aes-256-cbc -d -pbkdf2 -k '#RaX30O0M@!$' -in cfg_export_config_file.conf -out out.bin
```

## 解压

```bash
tar -zxvf out.bin
```
