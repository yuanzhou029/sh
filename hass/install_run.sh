#!/bin/bash

ROOT_PASSWORD="yz,821009"  
HASS_USERNAME="hass"

echo "=== 脚本开始执行 ==="

# 确保脚本在任何命令失败时立即退出
set -e

# 检查当前 Debian 版本，避免混淆源
CURRENT_DEBIAN_CODENAME=$(lsb_release -cs 2>/dev/null || echo "unknown")
TARGET_DEBIAN_CODENAME="trixie" # 请确认这是否是你目标系统的版本

if [ "$CURRENT_DEBIAN_CODENAME" != "$TARGET_DEBIAN_CODENAME" ]; then
    echo "警告：当前 Debian 系统版本 ($CURRENT_DEBIAN_CODENAME) 与脚本目标版本 ($TARGET_DEBIAN_CODENAME) 不符！"
    echo "继续执行可能会导致系统包管理器损坏。建议手动检查或修改脚本。"
    read -p "是否继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "脚本已终止。"
        exit 1
    fi
fi

echo "$ROOT_PASSWORD" | su -c "
# === 以下所有命令都将以 root 身份执行 ===

# --- 开始：修改更新源 ---
echo '正在备份原始 sources.list...'
cp /etc/apt/sources.list /etc/apt/sources.list.bak

echo '正在写入新的 sources.list (清华 TUNA 镜像源)...'
cat <<EOF > /etc/apt/sources.list
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME} main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME} main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME}-updates main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME}-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security ${TARGET_DEBIAN_CODENAME}-security main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security ${TARGET_DEBIAN_CODENAME}-security main contrib non-free
# 对于 Debian Testing (${TARGET_DEBIAN_CODENAME})，不推荐 backports。如果你的确有额外需要，可以自行添加。
# deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME}-backports main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${TARGET_DEBIAN_CODENAME}-backports main contrib non-free
EOF
echo 'sources.list 修改完成。'
# --- 结束：修改更新源 ---

echo '正在更新包列表并安装sudo...'
apt update
apt install -y sudo

# 检查 hass 用户是否存在，如果不存在则创建（可选）
if ! id "$HASS_USERNAME" >/dev/null 2>&1; then
    echo "用户 $HASS_USERNAME 不存在，正在创建..."
    useradd -m -s /bin/bash "$HASS_USERNAME" # -m 创建家目录，-s /bin/bash 设置默认shell
    # 如果需要为新用户设置密码，这里会提示：passwd "$HASS_USERNAME"
fi

echo "正在将 $HASS_USERNAME 用户添加到 sudo 组..."
usermod -aG sudo "$HASS_USERNAME"
echo 'sudo已安装，并且 '$HASS_USERNAME' 已加入sudo组。'

echo '正在安装依赖库...'
apt install -y libpcap0.8 libpcap0.8-dev ffmpeg libturbojpeg0 rsync

# 注意：wget 和 bash 将在当前 shell (root) 环境下执行
echo '正在下载并执行 Home Assistant 安装脚本...'
wget -O install_ha_cn.sh \"https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/install_ha_cn.sh\"
chmod +x install_ha_cn.sh
bash install_ha_cn.sh

echo '正在下载并执行静态 IP 设置脚本...'
wget -O set_static_ip.sh \"https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/set_static_ip.sh\"
chmod +x set_static_ip.sh
bash set_static_ip.sh

# --- 警告：/etc/resolv.conf 的修改可能不是持久的 ---
echo '正在设置 DNS 服务器...'
echo \"nameserver 218.30.19.40\nnameserver 61.134.1.4\" > /etc/resolv.conf
echo \"DNS 设置已写入 /etc/resolv.conf。\"
echo \"请注意：在许多现代 Linux 系统中，此更改可能不是永久性的。\"
echo \"如需永久更改，请根据你的网络管理工具（如 systemd-resolved 或 NetworkManager）进行配置。\"

echo '正在清理临时脚本文件...'
rm -f set_static_ip.sh
# 你的脚本没有创建 install_run.sh，请确认是否需要删除这个文件。
rm -f install_run.sh
rm -f install_ha_cn.sh
" # su -c 命令块结束

echo "=== 脚本执行完毕 ==="
