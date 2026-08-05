# PassWall 名单（代理 / 拦截）

> 用于 ImmortalWrt 的 PassWall 插件的代理放行名单与广告/追踪拦截名单。

---

## 一、代理放行名单（Proxy List）

```text
# --- [ AI Core Services ] ---
openai.com
chatgpt.com
chat.com
ai.com
sora.com
oaistatic.com
oaiusercontent.com
anthropic.com
claude.ai
claude.com

# --- [ Microsoft & Azure Infrastructure ] ---
msauth.net
msftauth.net
microsoftonline.com
auth0.com
azureedge.net
azurefd.net
windows.net
livekit.cloud
bing.com
bing.net
bingapis.com
microsoft.com
live.com
msn.com
office.com
office.net
sharepoint.com
sharepoint-df.com
1drv.com
1drv.ms

# --- [ CDN & Network Support ] ---
cloudflare.com
cloudflare.net
akamaized.net
akamaihd.net
imgix.net
lencr.org
gvt2.com
ip-only.net
telenorcdn.net

# --- [ Security, Analytics & Captcha ] ---
hcaptcha.com
recaptcha.net
sentry.io
sentry-cdn.com
statsigapi.net
intercom.io

# --- [ 其他规则列表 ] ---
engage.cloudflareclient.com
github.com
bing.com
c.mi.com
apple-relay.apple.com
googleapis.cn
googleapis.com
google.com.tw
google.com.hk
gstatic.com
xn--ngstr-lra8j.com
```

---

## 二、拦截名单（Block List）

```text
# 黑名单列表 blocklist
# baidu
360.cn
www.360.cn
qhimg.com
360safe.com
so.com
haosou.com
360totalsecurity.com
# baidu
cpro.baidustatic.com
cpro.baidu.com
union.baidu.com
eiv.baidu.com
pos.baidu.com
push.baidu.com
dup.baidustatic.com
hm.baidu.com
cbjs.baidu.com
cb.baidu.com
mobads.baidu.com
tanx.com
tanx.union.alimama.com   # 阿里妈妈，但常与百度混用
bdimg.com               # 有时用于广告图片，可选
bdstatic.com            # 部分静态广告资源，可选屏蔽
bs.baidu.com
wn.pos.baidu.com
entry.baidu.com
# end
```
