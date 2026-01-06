
# 常用脚本合集
## SSL证书申请脚本
* 一键申请SSL证书\
* 关闭防火墙/放行端口\
* 选择SSL颁发机构（增加申请成功率）\
* 证书自动续期\
* 申请失败，删除残留文件，然后重新申请
#### 脚本源自:[slobys](https://github.com/slobys/SSL-Renewal])
```
bash <(curl -fsSL https://proxy.api.030101.xyz/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/ssl/acme_3.0.sh)
```
---
## 科技kejilion工具脚本
* 非常丰富的脚本合集

```
bash <(curl -sL https://proxy.api.030101.xyz/https://raw.githubusercontent.com/kejilion/sh/refs/heads/main/kejilion.sh)
```
## nodepass脚本安装
* np.sh: 一键部署 NodePass 主程序，提供高性能 TCP/UDP 隧道服务，支持多系统和灵活配置
* dash.sh: 一键部署 NodePassDash 控制面板，简化隧道管理和监控，支持容器化和 HTTPS 配置。
* 正式版: v1.14.1
* 开发版: v1.14.1-b1
* 经典版: v1.10.3
```
bash <(wget -qO- https://run.nodepass.eu/np.sh)

bash <(curl -sSL https://run.nodepass.eu/np.sh)
```
