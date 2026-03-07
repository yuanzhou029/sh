#!/bin/sh
# 自动设置sudo权限脚本
# 设置root密码变量
ROOT_PASSWORD="yz,821009"
# 检查是否能够切换到root用户
echo "正在验证root用户密码..."
echo "$ROOT_PASSWORD" | su -c "whoami" >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo "错误: 无法使用提供的密码切换到root用户"
  exit 1
fi
# 使用su切换到root并执行后续命令
echo "正在切换到root用户并执行设置..."
SCRIPT_PATH="$0"
echo "$ROOT_PASSWORD" | su -c "
if command -v apt >/dev/null 2>&1; then
  apt update && apt install -y sudo
elif command -v yum >/dev/null 2>&1; then
  yum install -y sudo
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y sudo
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --noconfirm sudo
else
  echo '错误: 未找到包管理器'
  exit 1
fi
# 将hass用户添加到sudo组
if id hass >/dev/null 2>&1; then
  usermod -aG sudo hass
  echo '已将hass用户添加到sudo组'
else
  echo '警告: 用户hass不存在'
fi
# 删除此脚本
rm -f '$SCRIPT_PATH'
echo '脚本已执行完成并删除自身'
"
