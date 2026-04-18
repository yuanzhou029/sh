#!/bin/bash
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                                                              ║"
echo "  ║                           XOAI                               ║"
echo "  ║                      智能安装程序 v1.1                       ║"
echo "  ║                 开始设置安装主程序包括用户权限               ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  正在启动安装程序..."
echo ""
sleep 2

# --- 配置参数 ---
HA_USER="zych_ha"
HA_INSTALL_DIR="/srv/$HA_USER"
HA_CONFIG_DIR="/home/$HA_USER/.xoai"
HA_MIRROR_REPO="https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/ha-mirror.git"
HA_MIRROR_CONFIG_SUBDIR="config"
HA_PYTHON3143_URL="https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/sh/releases/download/3.14.3/python-3.14.3-linux-x86_64.tar.gz"
PIP_MIRROR_URL="https://repo.huaweicloud.com/repository/pypi/simple"
HA_WHEEL_URL="https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/APK/releases/download/xoai-20260409/xoai-all-in-one-amd64.zip"

# --- 函数定义 ---
log_info() { echo "INFO: $1"; }
log_warn() { echo "WARN: $1"; }
log_error() { echo "ERROR: $1" >&2; exit 1; }

# 检查当前用户是否为 root
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本需要 root 权限运行。请使用 'sudo' 执行。"
fi

log_info "正在开始 小鸥智能 原生安装和自定义配置部署 (含 ESPHome 独立环境)..."

# 检查磁盘空间
check_disk_space() {
    local required_gb=${1:-2}
    local target_dir="${2:-/srv}"
    local parent_dir=$(dirname "$target_dir")
    
    if [ ! -d "$target_dir" ]; then
        if [ -d "$parent_dir" ]; then
            local available_kb=$(df "$parent_dir" | tail -1 | awk '{print $4}')
        else
            local available_kb=$(df "/" | tail -1 | awk '{print $4}')
        fi
    else
        local available_kb=$(df "$target_dir" | tail -1 | awk '{print $4}')
    fi
    
    local available_gb=$((available_kb / 1024 / 1024))
    log_info "目标目录 ($target_dir) 可用磁盘空间: ${available_gb}GB (需要至少 ${required_gb}GB)"
    
    if [ $available_gb -lt $required_gb ]; then
        log_error "磁盘空间不足！需要至少 ${required_gb}GB，当前只有 ${available_gb}GB。"
    fi
}

log_info "正在检查磁盘空间..."
check_disk_space 4 "/srv/zych_ha"

# 0. 检查并安装必要工具
log_info "正在检查系统工具..."
REQUIRED_TOOLS=("git" "build-essential" "wget" "unzip" "curl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! dpkg -s "$tool" &>/dev/null; then
        log_info "$tool 未安装，正在安装..."
        sudo apt update && sudo apt install -y "$tool" || log_error "无法安装 $tool"
    else
        log_info "$tool 已安装。"
    fi
done

# 1. 创建用户和组
log_info "正在管理用户 '$HA_USER'..."
if ! id -u "$HA_USER" >/dev/null 2>&1; then
    GROUPS_TO_ADD="input"
    getent group dialout >/dev/null && GROUPS_TO_ADD+=",dialout"
    getent group gpio >/dev/null && GROUPS_TO_ADD+=",gpio"
    log_info "添加用户到组: $GROUPS_TO_ADD"
    sudo useradd -r -m -G "$GROUPS_TO_ADD" "$HA_USER" || log_error "无法创建用户"
else
    log_info "用户已存在。"
fi

# 2. 创建安装目录
log_info "正在设置目录权限 '$HA_INSTALL_DIR'..."
sudo mkdir -p "$HA_INSTALL_DIR"
sudo chown -R "$HA_USER":"$HA_USER" "$HA_INSTALL_DIR"

# 3. 执行内部用户安装脚本
log_info "启动用户级安装流程..."
TEMP_HA_SCRIPT="/tmp/install_ha_user_$(date +%s).sh"

cat > "$TEMP_HA_SCRIPT" << 'EOF_INNER_SCRIPT'
    set -e

    log_info() { echo "INFO (HA_USER): $1"; }
    log_warn() { echo "WARN (HA_USER): $1"; }
    log_error() { echo "ERROR (HA_USER): $1" >&2; exit 1; }

    # 变量注入
    HA_INSTALL_DIR_INNER="{{HA_INSTALL_DIR}}"
    HA_CONFIG_DIR_INNER="{{HA_CONFIG_DIR}}"
    HA_MIRROR_REPO_INNER="{{HA_MIRROR_REPO}}"
    HA_MIRROR_CONFIG_SUBDIR_INNER="{{HA_MIRROR_CONFIG_SUBDIR}}"
    PIP_MIRROR_URL_INNER="{{PIP_MIRROR_URL}}"
    HA_WHEEL_URL_INNER="{{HA_WHEEL_URL}}"
    HA_USER_INNER="{{HA_USER}}"
    HA_PYTHON3143_URL_INNER="{{HA_PYTHON3143_URL}}"
    ESPHOME_DIR_INNER="$HA_INSTALL_DIR_INNER/esphome_venv"

    export PATH="/usr/bin:$PATH"
    cd "$HA_INSTALL_DIR_INNER" || log_error "无法进入目录"

    # --- Python 3.14 环境搭建 ---
    log_info "正在准备 Python 3.14 环境..."
    mkdir -p python3.14
    wget --quiet --show-progress -O py3.14.tar.gz "$HA_PYTHON3143_URL_INNER"
    tar -xzf py3.14.tar.gz -C python3.14 --strip-components=1
    rm py3.14.tar.gz
    
    export PATH=$(pwd)/python3.14/bin:$PATH
    export LD_LIBRARY_PATH=$(pwd)/python3.14/lib:$LD_LIBRARY_PATH
    export PYTHONHOME=$(pwd)/python3.14
    python --version

    # --- 创建主程序虚拟环境 ---
    log_info "创建主程序虚拟环境..."
    python -m venv .
    source bin/activate
    
    # 配置 pip
    pip install --upgrade pip
    pip config set global.index-url "$PIP_MIRROR_URL_INNER"
    TRUSTED_HOST_INNER=$(echo "$PIP_MIRROR_URL_INNER" | sed -E 's/https?:\/\/(.*)\/simple.*/\1/')
    pip config set global.trusted-host "$TRUSTED_HOST_INNER"

    # --- [新增] 安装 ESPHome 独立虚拟环境 ---
    log_info "正在创建 ESPHome 独立虚拟环境..."
    mkdir -p "$ESPHOME_DIR_INNER"
    cd "$ESPHOME_DIR_INNER"
    python -m venv venv
    source venv/bin/activate
    log_info "正在通过镜像源安装 ESPHome..."
    pip install --upgrade pip
    pip install esphome || log_warn "ESPHome 安装可能存在部分依赖缺失"
    log_info "ESPHome 环境就绪: $ESPHOME_DIR_INNER/venv/bin/esphome"
    deactivate
    cd "$HA_INSTALL_DIR_INNER"

    # --- 下载并安装小鸥智能主包 ---
    log_info "正在下载安装主包..."
    TEMP_DOWNLOAD_DIR="$HA_INSTALL_DIR_INNER/temp_dl_$$"
    mkdir -p "$TEMP_DOWNLOAD_DIR"
    cd "$TEMP_DOWNLOAD_DIR"
    wget --quiet --show-progress "$HA_WHEEL_URL_INNER" -O xoai_artifacts.zip
    unzip -q xoai_artifacts.zip
    
    WHEEL_FILE=$(find . -name "xoai_core-*.whl" | head -n 1)
    DEP_DIR=$(find . -name "xoai_zych" -type d | head -n 1)
    
    if [ -z "$WHEEL_FILE" ]; then log_error "未找到主包 Wheel 文件"; fi

    cd "$HA_INSTALL_DIR_INNER"
    mkdir -p xoai_zych
    cp "$TEMP_DOWNLOAD_DIR/$WHEEL_FILE" .
    [ -n "$DEP_DIR" ] && cp -r "$TEMP_DOWNLOAD_DIR/$DEP_DIR" .
    rm -rf "$TEMP_DOWNLOAD_DIR"

    log_info "正在安装主程序包..."
    pip install "$(basename "$WHEEL_FILE")" --find-links xoai_zych/ --prefer-binary

    # 批量安装额外依赖 (优化：合并为一个命令以提高速度并减少冲突)
    log_info "正在批量安装核心依赖..."
    pip install \
        "numpy==2.3.2" "xoai-frontend==20260409.1" "av==16.0.1" "openai==2.21.0" \
        "PyTurboJPEG==1.8.0" "colorlog==6.10.1" "home-assistant-intents==2026.3.3" \
        "hassil==3.5.0" "pyspeex-noise==1.0.2" "pymicro-vad==1.0.1" \
        "file-read-backwards==2.0.0" "aiodiscover==2.7.1" "aiodhcpwatcher==1.2.1" \
        "mutagen==1.47.0" "ha-ffmpeg==3.2.2" "matter-python-client==0.4.1" \
        "bleak==2.1.1" "RestrictedPython==8.1" "bleak-retry-connector==4.4.3" \
        "bluetooth-adapters==2.1.0" "habluetooth==5.8.0" "aiousbwatcher==1.1.1" \
        "pyserial==3.5" "async-upnp-client==0.46.2" "dbus-fast==3.1.2" "go2rtc-client==0.4.0"

    # --- 配置与验证 ---
    log_info "正在同步远程配置..."
    if [ ! -d "$HA_INSTALL_DIR_INNER/ha-mirror-repo" ]; then
        git clone "$HA_MIRROR_REPO_INNER" "$HA_INSTALL_DIR_INNER/ha-mirror-repo"
    else
        cd "$HA_INSTALL_DIR_INNER/ha-mirror-repo" && git pull && cd "$HA_INSTALL_DIR_INNER"
    fi

    mkdir -p "$HA_CONFIG_DIR_INNER"
    cp -r "$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_MIRROR_CONFIG_SUBDIR_INNER"/* "$HA_CONFIG_DIR_INNER/"
    chown -R "$HA_USER_INNER":"$HA_USER_INNER" "$HA_CONFIG_DIR_INNER"

    log_info "正在验证配置..."
    export LD_LIBRARY_PATH=$(pwd)/python3.14/lib:$LD_LIBRARY_PATH
    "$HA_INSTALL_DIR_INNER/bin/hass" --script check_config -c "$HA_CONFIG_DIR_INNER"

    log_info "安装成功！"
EOF_INNER_SCRIPT

# 注入变量
sed -i \
    -e "s|{{HA_INSTALL_DIR}}|$HA_INSTALL_DIR|g" \
    -e "s|{{HA_CONFIG_DIR}}|$HA_CONFIG_DIR|g" \
    -e "s|{{HA_USER}}|$HA_USER|g" \
    -e "s|{{HA_MIRROR_REPO}}|$HA_MIRROR_REPO|g" \
    -e "s|{{HA_MIRROR_CONFIG_SUBDIR}}|$HA_MIRROR_CONFIG_SUBDIR|g" \
    -e "s|{{PIP_MIRROR_URL}}|$PIP_MIRROR_URL|g" \
    -e "s|{{HA_WHEEL_URL}}|$HA_WHEEL_URL|g" \
    -e "s|{{HA_PYTHON3143_URL}}|$HA_PYTHON3143_URL|g" \
    "$TEMP_HA_SCRIPT"

sudo chmod +x "$TEMP_HA_SCRIPT"
sudo -u "$HA_USER" bash "$TEMP_HA_SCRIPT" || log_error "用户级安装失败"
sudo rm -f "$TEMP_HA_SCRIPT"

# 4. 系统级配置 (ldconfig & systemd)
log_info "配置系统库与服务..."
sudo sh -c "echo '$HA_INSTALL_DIR/python3.14/lib' > /etc/ld.so.conf.d/python3.14.conf"
sudo ldconfig

SYSTEMD_SERVICE_FILE="/etc/systemd/system/homeassistant@.service"
sudo bash -c "cat > '$SYSTEMD_SERVICE_FILE'" <<EOL
[Unit]
Description=Home Assistant
After=network-online.target

[Service]
Type=simple
User=%i
Environment="PATH=$HA_INSTALL_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=$HA_INSTALL_DIR/python3.14/lib"
Environment="PYTHONHOME=$HA_INSTALL_DIR/python3.14"
ExecStart=$HA_INSTALL_DIR/bin/hass -c "$HA_CONFIG_DIR"
RestartForceExitStatus=100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload
sudo systemctl enable homeassistant@"$HA_USER"
sudo systemctl restart homeassistant@"$HA_USER" || log_error "服务启动失败"

log_info "安装完成！"
log_info "ESPHome 路径: $HA_INSTALL_DIR/esphome_venv/venv/bin/esphome"
log_info "访问地址: http://$(hostname -I | awk '{print $1}'):1404"

# 检查状态
sleep 20
if sudo systemctl is-active --quiet homeassistant@"$HA_USER"; then
    log_info "服务运行状态: 正常"
else
    log_warn "服务运行状态: 异常，请使用 'sudo journalctl -u homeassistant@$HA_USER' 查看日志"
fi
