#!/bin/bash
# 建议使用 /bin/bash 以获得更全面的shell功能


ROOT_PASSWORD="ouiw0l#W7@h3gX#9fzmx" 
HASS_USERNAME="hass"


echo "$ROOT_PASSWORD" | su -c "


# --- 辅助函数 ---
# 在 root 环境下，可以直接使用这些函数，无需再判断权限
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

info_msg '正在更新包列表并安装sudo...'
apt update
apt install -y sudo # apt install -y sudo 依然可以执行，尽管已经以 root 身份运行

# 检查 hass 用户是否存在，如果不存在则创建
if ! id "$HASS_USERNAME_INTERNAL" >/dev/null 2>&1; then
    info_msg "用户 $HASS_USERNAME_INTERNAL 不存在，正在创建..."
    useradd -m -s /bin/bash "$HASS_USERNAME_INTERNAL" # 已是 root，无需 sudo
    success_msg "用户 $HASS_USERNAME_INTERNAL 已创建。"
    # 如果需要为新用户设置密码，这里可以添加 `echo "新密码" | passwd --stdin "$HASS_USERNAME_INTERNAL"`
else
    info_msg "用户 $HASS_USERNAME_INTERNAL 已存在。"
fi

info_msg "正在将 $HASS_USERNAME_INTERNAL 用户添加到 sudo 组..."
if ! groups "$HASS_USERNAME_INTERNAL" | grep -q '\bsudo\b'; then
    usermod -aG sudo "$HASS_USERNAME_INTERNAL" # 已是 root，无需 sudo
    success_msg "用户 $HASS_USERNAME_INTERNAL 已加入sudo组。"
else
    info_msg "用户 $HASS_USERNAME_INTERNAL 已在sudo组中。"
fi

info_msg '正在安装依赖库...'
apt install -y libpcap0.8 libpcap0.8-dev ffmpeg libturbojpeg0 rsync # 已是 root，无需 sudo
success_msg '依赖库安装完成。'

# --- 警告：下载并执行外部脚本存在严重安全风险！ ---
# 请务必在执行前检查这些脚本的内容，或将其内容集成到此主脚本中。
info_msg '正在下载并执行 Home Assistant 安装脚本...'
wget -O install_ha_cn.sh "https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/install_ha_cn.sh"
chmod +x install_ha_cn.sh
bash install_ha_cn.sh
success_msg 'Home Assistant 安装脚本执行完毕。'

info_msg '正在下载并执行静态 IP 设置脚本...'
wget -O set_static_ip.sh "https://url.yh-iot.cloudns.org/https://raw.githubusercontent.com/yuanzhou029/sh/refs/heads/main/hass/set_static_ip.sh"
chmod +x set_static_ip.sh
bash set_static_ip.sh
success_msg '静态 IP 设置脚本执行完毕。'

# --- 警告：/etc/resolv.conf 的修改可能不是持久的 ---
info_msg '正在设置 DNS 服务器...'
# 使用 here-document 直接写入 /etc/resolv.conf，这是最安全和简洁的方式。
cat <<'RESOLV_CONF_HERE' > /etc/resolv.conf
nameserver 218.30.19.40
nameserver 61.134.1.4
RESOLV_CONF_HERE
success_msg "DNS 设置已写入 /etc/resolv.conf。"
warning_msg "请注意：在许多现代 Linux 系统中，此更改可能不是永久性的。"
warning_msg "如需永久更改，请根据你的网络管理工具（如 systemd-resolved 或 NetworkManager）进行配置。"

info_msg '正在清理临时脚本文件...'
rm -f set_static_ip.sh
rm -f install_ha_cn.sh
# 警告：请勿删除当前正在运行的 install_run.sh 脚本自身。
# 除非你确定此处的 install_run.sh 指的是另一个文件。
# rm -f install_run.sh
success_msg '临时文件清理完毕。'

echo "=== 脚本执行完毕 ==="
EOF_SU_SCRIPT
)"

# 在执行 `su -c` 之前，将 HASS_USERNAME_INTERNAL 占位符替换为实际的 HASS_USERNAME 值
# 这一步必须在 `su -c` 命令被 shell 解析和执行之前完成。
SU_SCRIPT_FINAL="${SU_SCRIPT//<PLACEHOLDER_HASS_USERNAME>/$HASS_USERNAME}"

# 最终执行 `su -c` 命令。
# 使用 `printf "%s"` 来输出密码，以避免 `echo` 对反斜杠的解释。
printf "%s" "$ROOT_PASSWORD" | su -c "$SU_SCRIPT_FINAL"
