#!/bin/bash
# 完整自动化设置脚本
# 功能：使用预设密码自动设置sudo权限，然后执行静态IP设置
# 设置root密码变量
ROOT_PASSWORD="yz,821009"
HASS_USERNAME="hass"
# 输出带颜色的信息
error_msg() {
    echo -e "\033[0;31mERROR: $1\033[0m" >&2
    exit 1
}
success_msg() {
    echo -e "\033[0;32mSUCCESS: $1\033[0m"
}
info_msg() {
    echo -e "\033[0;34mINFO: $1\033[0m"
}
warning_msg() {
    echo -e "\033[0;33mWARNING: $1\033[0m"
}
info_msg "开始执行完整自动化设置..."
# 检查是否能够切换到root用户
info_msg "正在验证root用户密码..."
echo "$ROOT_PASSWORD" | su -c "whoami" >/dev/null 2>&1
if [ $? -ne 0 ]; then
  error_msg "无法使用提供的密码切换到root用户"
fi
# 使用su切换到root并执行sudo和用户设置
info_msg "正在切换到root用户并执行设置..."
echo "$ROOT_PASSWORD" | su -c "
export PATH=\$PATH:/usr/sbin:/sbin:/usr/local/sbin
# 检查并安装sudo
if command -v apt >/dev/null 2>&1; then
  info_msg '检测到APT包管理器'
  apt update && apt install -y sudo
elif command -v yum >/dev/null 2>&1; then
  info_msg '检测到YUM包管理器'
  yum install -y sudo
elif command -v dnf >/dev/null 2>&1; then
  info_msg '检测到DNF包管理器'
  dnf install -y sudo
elif command -v pacman >/dev/null 2>&1; then
  info_msg '检测到Pacman包管理器'
  pacman -Sy --noconfirm sudo
else
  echo '错误: 未找到包管理器'
  exit 1
fi
# 将hass用户添加到sudo组
if id $HASS_USERNAME >/dev/null 2>&1; then
  usermod -aG sudo $HASS_USERNAME
  info_msg '已将hass用户添加到sudo组'
else
  warning_msg '警告: 用户hass不存在'
fi
info_msg 'sudo权限设置完成，正在返回到hass用户...'
"
# 检查是否成功设置了sudo权限
if id "$HASS_USERNAME" &> /dev/null && groups "$HASS_USERNAME" | grep -q '\bsudo\b'; then
    success_msg "sudo权限已成功设置"
    
    # 切换到hass用户并执行静态IP设置脚本
    info_msg "正在切换到hass用户并执行静态IP设置..."
    
    # 检查是否存在set_static_ip.sh脚本
    if [ -f "/home/$HASS_USERNAME/set_static_ip.sh" ]; then
        su - $HASS_USERNAME -c "cd && sudo ./set_static_ip.sh"
    else
        warning_msg "警告: 未找到set_static_ip.sh脚本"
        info_msg "正在下载set_static_ip.sh脚本..."
        su - $HASS_USERNAME -c "cd && wget -O set_static_ip.sh https://pxy.140407.xyz/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/set_static_ip.sh && chmod +x set_static_ip.sh && sudo ./set_static_ip.sh"
    fi
else
    error_msg "sudo权限设置失败，无法继续执行"
fi
# 删除此脚本自身
info_msg "正在删除自动化设置脚本..."
rm -f "$0"
info_msg "脚本已自动删除"
