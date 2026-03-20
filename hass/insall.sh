#!/bin/sh
ROOT_PASSWORD="yuanzhou,821009"  # <--- 就在这里设置！
HASS_USERNAME="hass"

# 使用su和预设密码执行设置
echo "$ROOT_PASSWORD" | su -c "
# --- 开始：修改更新源 ---
echo '正在备份原始 sources.list...'
cp /etc/apt/sources.list /etc/apt/sources.list.bak

echo '正在写入新的 sources.list (清华 TUNA 镜像源)...'
cat <<EOF > /etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-updates main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security trixie-security main contrib non-free
# 对于 Debian Testing (trixie)，不推荐 backports。如果你的确有额外需要，可以自行添加。
# deb https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-backports main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ trixie-backports main contrib non-free
EOF
echo 'sources.list 修改完成。'
# --- 结束：修改更新源 ---
# 更新包列表并安装sudo
apt update && apt install -y sudo

wget -O python3.14.3.sh https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/python3.14.3.sh && chmod +x python3.14.3.sh && bash python3.14.3.sh
"
