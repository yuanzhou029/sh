#!/bin/sh
# 简单自动化设置脚本
# 功能：使用su root密码yz,821009，安装sudo，将hass用户添加到sudo组，
# 然后退回hass用户根目录，使用sudo执行其他功能
ROOT_PASSWORD="yz,821009"
HASS_USERNAME="hass"
# 使用su和预设密码执行设置
echo "$ROOT_PASSWORD" | su -c "
# 更新包列表并安装sudo
apt update && apt install -y sudo usermod
# 将hass用户添加到sudo组
export PATH=\$PATH:/usr/sbin:/sbin:/usr/local/sbin
usermod -aG sudo $HASS_USERNAME
echo 'sudo已安装，hass用户已添加到sudo组'
"
# 切换回hass用户，进入其根目录并执行其他功能
if [ -f "/home/$HASS_USERNAME/set_static_ip.sh" ]; then
    # 如果set_static_ip.sh存在，则使用sudo运行它
    su - $HASS_USERNAME -c "cd && sudo ./set_static_ip.sh"
else
    echo "set_static_ip.sh 不存在于hass用户根目录"
fi
# 删除此脚本
rm -f "$0"
echo "脚本已自动删除"
