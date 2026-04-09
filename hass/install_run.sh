#!/bin/sh
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                                                              ║"
echo "  ║                           XOAI                               ║"
echo "  ║                      智能安装程序 v1.0                        ║"
echo "  ║                 开始设置系统源安装必要权限依赖                  ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  正在启动安装程序..."
echo ""
sleep 3

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
sleep 1
# 更新包列表并安装sudo
apt update
apt upgrade -y
sleep 1
apt install -y sudo

# 将hass用户添加到sudo组
export PATH=\$PATH:/usr/sbin:/sbin:/usr/local/sbin
sleep 1
# 你的原始脚本中 usermod 被注释掉了，如果需要执行请取消注释
sudo usermod -aG sudo $HASS_USERNAME
echo 'sudo已安装 hass已经加入sudo组'
sleep 1
sudo apt install libpcap0.8 libpcap0.8-dev -y
sleep 3
sudo apt install ffmpeg -y
sleep 3
sudo apt install libturbojpeg0 -y
sleep 3
sudo apt install rsync
sleep 3

# 以下是原始脚本的后续操作
wget -O 11.sh https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/11.sh && chmod +x 11.sh && bash 11.sh
sleep 5
#wget -O set_static_ip.sh https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/set_static_ip.sh && chmod +x set_static_ip.sh && bash set_static_ip.sh
rm -f set_static_ip.sh
rm -f install_run.sh
rm -f install_ha_cn.sh
"
