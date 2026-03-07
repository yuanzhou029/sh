#!/bin/bash

# 检查是否以root身份运行
if [ "$EUID" -ne 0 ]; then
  echo "此脚本必须以root身份运行"
  exit 1
fi

# 安装sudo（如果未安装）
if ! command -v sudo &> /dev/null; then
  echo "正在安装sudo..."
  apt update
  apt install -y sudo
  if [ $? -ne 0 ]; then
    echo "安装sudo失败，请检查APT源配置"
    exit 1
  fi
  echo "sudo安装完成"
else
  echo "sudo已安装"
fi

# 将当前用户添加到sudo组
USERNAME=$(logname)
if id "$USERNAME" &>/dev/null; then
  if ! groups "$USERNAME" | grep -q '\bsudo\b'; then
    usermod -aG sudo "$USERNAME"
    echo "用户 $USERNAME 已添加到sudo组"
    echo "请重新登录以使sudo权限生效"
  else
    echo "用户 $USERNAME 已在sudo组中"
  fi
else
  echo "警告：用户 $USERNAME 不存在"
fi

# 设置脚本权限并运行原脚本
chmod +x ./set_static_ip.sh
echo "正在运行set_static_ip.sh..."
./set_static_ip.sh
