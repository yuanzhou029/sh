#!/bin/bash
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║                                                              ║"
echo "  ║                           XOAI                               ║"
echo "  ║                      智能安装程序 v1.2                       ║"
echo "  ║                 开始设置安装主程序包括用户权限               ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  正在启动安装程序..."
echo ""

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

# 设置 trap，确保脚本退出时清理临时文件
TEMP_HA_SCRIPT="/tmp/install_ha_user_$(date +%s).sh"
cleanup() {
    log_info "正在清理临时文件: $TEMP_HA_SCRIPT"
    sudo rm -f "$TEMP_HA_SCRIPT"
}
trap cleanup EXIT

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
            local available_kb=$(df -k "$parent_dir" | tail -1 | awk '{print $4}')
        else
            local available_kb=$(df -k "/" | tail -1 | awk '{print $4}')
        fi
    else
        local available_kb=$(df -k "$target_dir" | tail -1 | awk '{print $4}')
    fi
    
    local available_gb=$((available_kb / 1024 / 1024))
    log_info "目标目录 ($target_dir) 可用磁盘空间: ${available_gb}GB (需要至少 ${required_gb}GB)"
    
    if [ "$available_gb" -lt "$required_gb" ]; then
        log_error "磁盘空间不足！需要至少 ${required_gb}GB，当前只有 ${available_gb}GB。"
    fi
}

log_info "正在检查磁盘空间..."
check_disk_space 4 "/srv/$HA_USER" # 提高磁盘空间要求，兼顾 ESPHome

# 0. 检查并安装必要工具
log_info "正在检查并安装必要的系统工具 (git, build-essential, wget, unzip, curl)..."
REQUIRED_TOOLS=("git" "build-essential" "wget" "unzip" "curl")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! dpkg -s "$tool" &>/dev/null; then
        log_info "$tool 未安装，正在尝试安装..."
        sudo apt update || log_error "apt update 失败，请检查网络或软件源。"
        sudo apt install -y "$tool" || log_error "无法安装 $tool。请手动安装或检查您的包管理器。"
    else
        log_info "$tool 已安装。"
    fi
done

# 1. 创建用户和组
log_info "正在创建或验证用户 '$HA_USER' 和组..."
if ! id -u "$HA_USER" >/dev/null 2>&1; then
    GROUPS_TO_ADD="input"
    getent group dialout >/dev/null && GROUPS_TO_ADD+=",dialout"
    getent group gpio >/dev/null && GROUPS_TO_ADD+=",gpio"
    log_info "将用户 '$HA_USER' 添加到组: $GROUPS_TO_ADD"
    sudo useradd -r -m -G "$GROUPS_TO_ADD" "$HA_USER" || log_error "无法创建用户 '$HA_USER'。"
    log_info "用户 '$HA_USER' 创建成功。"
else
    log_info "用户 '$HA_USER' 已存在。"
fi

# 2. 创建安装目录并设置权限
log_info "正在创建 小鸥智能 安装目录 '$HA_INSTALL_DIR'..."
sudo mkdir -p "$HA_INSTALL_DIR" || log_error "无法创建目录 '$HA_INSTALL_DIR'。"
sudo chown -R "$HA_USER":"$HA_USER" "$HA_INSTALL_DIR" || log_error "无法设置目录权限 '$HA_INSTALL_DIR'。"

# 3. 切换到 小鸥智能 用户，并执行后续操作 (内部脚本)
log_info "正在切换到用户 '$HA_USER' 以设置环境和安装 小鸥智能..."

cat > "$TEMP_HA_SCRIPT" << 'EOF_INNER_SCRIPT'
    set -e # 任何命令失败立即退出

    log_info() { echo "INFO (HA_USER): $1"; }
    log_warn() { echo "WARN (HA_USER): $1"; }
    log_error() { echo "ERROR (HA_USER): $1" >&2; exit 1; }

    # 定义从外部脚本继承的变量
    HA_INSTALL_DIR_INNER="{{HA_INSTALL_DIR}}"
    HA_CONFIG_DIR_INNER="{{HA_CONFIG_DIR}}"
    HA_MIRROR_REPO_INNER="{{HA_MIRROR_REPO}}"
    HA_MIRROR_CONFIG_SUBDIR_INNER="{{HA_MIRROR_CONFIG_SUBDIR}}"
    PIP_MIRROR_URL_INNER="{{PIP_MIRROR_URL}}"
    HA_WHEEL_URL_INNER="{{HA_WHEEL_URL}}"
    HA_USER_INNER="{{HA_USER}}"
    HA_PYTHON3143_URL_INNER="{{HA_PYTHON3143_URL}}"

    # 显式地将 /usr/bin 添加到 PATH (确保系统命令可用)
    export PATH="/usr/bin:$PATH"
    log_info "更新后 PATH 环境变量: $PATH"

    # 切换到安装目录
    cd "$HA_INSTALL_DIR_INNER" || log_error "用户 '$HA_USER_INNER' 无法切换到目录 '$HA_INSTALL_DIR_INNER'。"
    
    # --- Python 3.14 环境搭建 (增强版) ---
    log_info "正在准备 Python 3.14 环境..."
    mkdir -p python3.14 || log_error "无法创建 python3.14 目录。"
    wget --quiet --show-progress -O py3.14.tar.gz "$HA_PYTHON3143_URL_INNER" || log_error "Python 3.14 环境包下载失败。"
    tar -xzf py3.14.tar.gz -C python3.14 --strip-components=1 || log_error "Python 3.14 环境包解压失败。"
    rm py3.14.tar.gz

    # 设置环境变量以确保 Python 可用
    export PYTHON_ROOT="$HA_INSTALL_DIR_INNER/python3.14"
    export PATH="$PYTHON_ROOT/bin:$PATH"
    export LD_LIBRARY_PATH="$PYTHON_ROOT/lib:$LD_LIBRARY_PATH"
    export PYTHONHOME="$PYTHON_ROOT"

    log_info "验证 Python 3.14 解释器是否可用..."
    # 验证 Python 动态链接库依赖
    ldd "$PYTHON_ROOT/bin/python" || log_error "Python 3.14 动态链接库检查失败！请确保系统依赖（如 glibc）完整。"
    # 验证 Python 解释器是否能启动
    "$PYTHON_ROOT/bin/python" --version || log_error "Python 3.14 解释器无法启动！"
    log_info "Python 3.14 环境设置成功。"

    # --- 创建主程序虚拟环境 ---
    log_info "正在创建主程序虚拟环境..."
    "$PYTHON_ROOT/bin/python" -m venv . || log_error "无法创建主程序 Python 虚拟环境。"
    log_info "主程序虚拟环境创建成功。"
   
    # 激活虚拟环境
    log_info "正在激活主程序虚拟环境..."
    source bin/activate || log_error "无法激活主程序虚拟环境。"
    log_info "主程序虚拟环境激活成功。"

    # 配置 pip 使用国内镜像源
    log_info "正在配置 pip 使用国内镜像源: $PIP_MIRROR_URL_INNER"
    python -m pip install --upgrade pip || log_warn "pip 升级失败，继续安装。"
    python -m pip config set global.index-url "$PIP_MIRROR_URL_INNER" || log_error "无法设置 pip 镜像源。"
    TRUSTED_HOST_INNER=$(echo "$PIP_MIRROR_URL_INNER" | sed -E 's/https?:\/\/(.*)\/simple.*/\1/')
    python -m pip config set global.trusted-host "$TRUSTED_HOST_INNER" || log_error "无法设置 pip trusted-host。"
    log_info "pip 配置完成。"

    # --- [新增] 安装 ESPHome 独立虚拟环境 ---
    log_info "正在创建 ESPHome 独立虚拟环境..."
    ESPHOME_DIR_INNER="$HA_INSTALL_DIR_INNER/esphome_venv"
    mkdir -p "$ESPHOME_DIR_INNER" || log_error "无法创建 ESPHome 目录。"
    cd "$ESPHOME_DIR_INNER" || log_error "无法进入 ESPHome 目录。"

    # 使用当前的 Python 环境创建虚拟环境
    python -m venv venv || log_error "无法创建 ESPHome 虚拟环境。"
    
    # 激活并安装 ESPHome
    source venv/bin/activate || log_error "无法激活 ESPHome 虚拟环境。"
    
    log_info "正在通过华为镜像源安装 ESPHome 及其依赖..."
    python -m pip install --upgrade pip || log_warn "ESPHome pip 升级失败，继续安装。"
    # 再次确保镜像源配置，以防万一
    python -m pip config set global.index-url "$PIP_MIRROR_URL_INNER" || log_warn "无法设置 ESPHome pip 镜像源，尝试默认源。"
    python -m pip config set global.trusted-host "$TRUSTED_HOST_INNER" || log_warn "无法设置 ESPHome trusted-host。"
    python -m pip install esphome || log_warn "ESPHome 安装失败。请检查日志或手动尝试 'pip install esphome'。"
    
    log_info "ESPHome 环境安装完成。可执行文件路径: $ESPHOME_DIR_INNER/venv/bin/esphome"
    
    # 退出 ESPHome 虚拟环境，返回主程序虚拟环境
    deactivate
    cd "$HA_INSTALL_DIR_INNER" || log_error "无法返回安装目录。"
    # ---------------------------------------

    # --- 下载并安装从 GitHub Actions 构建的 小鸥智能 安装主包 ---
    log_info "正在从 GitHub 下载 小鸥智能 安装主包文件..."
    TEMP_DOWNLOAD_DIR="$HA_INSTALL_DIR_INNER/temp_download_$$"
    mkdir -p "$TEMP_DOWNLOAD_DIR" || log_error "无法创建临时下载目录。"
    cd "$TEMP_DOWNLOAD_DIR" || log_error "无法进入临时下载目录。"
    
    log_info "下载目录: $TEMP_DOWNLOAD_DIR"
    log_info "正在下载 小鸥智能 安装主包: $HA_WHEEL_URL_INNER"
    wget --quiet --show-progress "$HA_WHEEL_URL_INNER" -O xoai_artifacts.zip || log_error "无法下载 小鸥智能 安装主包文件。"
    
    # 解压 zip 文件
    log_info "正在解压 小鸥智能 安装主包..."
    unzip -q xoai_artifacts.zip || log_error "无法解压 小鸥智能 安装主包文件。"
    
    # 查找 小鸥智能 安装主包文件和依赖目录
    WHEEL_FILE=$(find . -name "xoai_core-*.whl" | head -n 1)
    DEPENDENCIES_DIR=$(find . -name "xoai_zych" -type d | head -n 1)
    
    if [ -z "$WHEEL_FILE" ]; then
        log_error "未找到 小鸥智能 安装主包文件。"
    fi
    log_info "找到 小鸥智能 安装主包文件: $WHEEL_FILE"
    
    # 返回到主程序虚拟环境目录
    cd "$HA_INSTALL_DIR_INNER" || log_error "无法返回安装目录。"
    
    # 创建 xoai_zych 目录并复制文件
    mkdir -p xoai_zych
    cp "$TEMP_DOWNLOAD_DIR/$WHEEL_FILE" . || log_error "无法复制 小鸥智能 安装主包文件。"
    log_info "已将 小鸥智能 安装主包文件复制到: $HA_INSTALL_DIR_INNER/$(basename "$WHEEL_FILE")"
    [ -n "$DEPENDENCIES_DIR" ] && cp -r "$TEMP_DOWNLOAD_DIR/$DEPENDENCIES_DIR" . && \
        log_info "已将 小鸥智能 依赖包文件夹复制到: $HA_INSTALL_DIR_INNER/$(basename "$DEPENDENCIES_DIR")"

    # 清理临时下载目录
    log_info "正在清理临时下载目录: $TEMP_DOWNLOAD_DIR"
    rm -rf "$TEMP_DOWNLOAD_DIR"
    
    # 安装 小鸥智能 安装主包文件
    log_info "正在安装 小鸥智能 安装主包: $(basename "$WHEEL_FILE")"
    python -m pip install "$(basename "$WHEEL_FILE")" --find-links xoai_zych/ --prefer-binary || log_error "无法安装 小鸥智能 安装主包。"
    log_info "小鸥智能 安装主包安装成功。"
    
    # 批量安装 小鸥智能 运行时可能需要的特定依赖
    log_info "正在批量安装 小鸥智能 额外依赖..."
    python -m pip install \
        "numpy==2.3.2" "xoai-frontend==20260409.1" "av==16.0.1" "openai==2.21.0" \
        "PyTurboJPEG==1.8.0" "colorlog==6.10.1" "home-assistant-intents==2026.3.3" \
        "hassil==3.5.0" "pyspeex-noise==1.0.2" "pymicro-vad==1.0.1" \
        "file-read-backwards==2.0.0" "aiodiscover==2.7.1" "aiodhcpwatcher==1.2.1" \
        "mutagen==1.47.0" "ha-ffmpeg==3.2.2" "matter-python-client==0.4.1" \
        "bleak==2.1.1" "RestrictedPython==8.1" "bleak-retry-connector==4.4.3" \
        "bluetooth-adapters==2.1.0" "habluetooth==5.8.0" "aiousbwatcher==1.1.1" \
        "pyserial==3.5" "async-upnp-client==0.46.2" "dbus-fast==3.1.2" "go2rtc-client==0.4.0" \
        || log_warn "部分额外依赖安装失败，可能不影响核心功能。"
    log_info "所有 小鸥智能 额外依赖安装完成。"

    # --- 克隆和部署配置 ---
    log_info "正在克隆或更新 小鸥智能 默认配置 '$HA_INSTALL_DIR_INNER/ha-mirror-repo'..."
    CLONE_URL_INNER="$HA_MIRROR_REPO_INNER"

    if [ ! -d "$HA_INSTALL_DIR_INNER/ha-mirror-repo" ]; then
        git clone "$CLONE_URL_INNER" "$HA_INSTALL_DIR_INNER/ha-mirror-repo" || log_error "无法克隆 默认配置。"
        log_info "默认配置克隆成功。"
    else
        log_info "ha-mirror 仓库已存在，正在执行 'git pull' 更新。"
        cd "$HA_INSTALL_DIR_INNER/ha-mirror-repo" || log_error "无法进入 ha-mirror 仓库目录。"
        git pull || log_error "无法更新 ha-mirror 仓库。"
        cd "$HA_INSTALL_DIR_INNER" # 返回到虚拟环境的根目录
        log_info "ha-mirror 仓库更新成功。"
    fi

    log_info "正在部署自定义配置和组件到 小鸥智能 配置目录 '$HA_CONFIG_DIR_INNER'..."
    mkdir -p "$HA_CONFIG_DIR_INNER" || log_error "无法创建 小鸥智能 配置目录。"
    # 复制 ha-mirror/config 中的内容到 HA_CONFIG_DIR_INNER
    cp -r "$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_MIRROR_CONFIG_SUBDIR_INNER"/* "$HA_CONFIG_DIR_INNER/" || log_error "无法复制自定义配置。"
    chown -R "$HA_USER_INNER":"$HA_USER_INNER" "$HA_CONFIG_DIR_INNER" || log_error "无法设置配置目录权限。"
    log_info "自定义配置和组件部署成功。"

    # --- 验证配置 ---
    log_info "正在验证 小鸥智能 配置..."
    # 确保环境变量已设置
    export LD_LIBRARY_PATH="$PYTHON_ROOT/lib:$LD_LIBRARY_PATH" # 再次确保 LD_LIBRARY_PATH 在这里生效
    "$HA_INSTALL_DIR_INNER/bin/hass" --script check_config -c "$HA_CONFIG_DIR_INNER" || {
        log_error "小鸥智能 配置验证失败。请检查配置错误。"
    }
    log_info "小鸥智能 基础配置验证完成。"

    log_info "小鸥智能 安装和自定义配置部署完成！"
    log_info "您可以现在激活虚拟环境并启动 小鸥智能： source $HA_INSTALL_DIR_INNER/bin/activate && $HA_INSTALL_DIR_INNER/bin/hass -c $HA_CONFIG_DIR_INNER"
EOF_INNER_SCRIPT

# 替换内部脚本中的占位符
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

# 赋予临时脚本执行权限
sudo chmod +x "$TEMP_HA_SCRIPT"

# 以 小鸥智能 用户身份执行临时脚本
sudo -u "$HA_USER" bash "$TEMP_HA_SCRIPT" || log_error "以用户 '$HA_USER' 执行内部脚本失败。"

# 4. 机器修改：配置 ldconfig 使系统全局能找到 Python 3.14 共享库
log_info "正在配置系统动态链接器以识别 Python 3.14 库..."
sudo sh -c "echo '$HA_INSTALL_DIR/python3.14/lib' > /etc/ld.so.conf.d/python3.14.conf"
sudo ldconfig || log_error "ldconfig 配置失败。"
log_info "系统动态链接器配置完成。"

# 5. 创建 systemd 服务
log_info "正在创建 systemd 服务以便 小鸥智能 开机自启..."
SYSTEMD_SERVICE_FILE="/etc/systemd/system/homeassistant@.service"

# 修改 systemd 服务文件以包含库路径设置
sudo bash -c "cat > '$SYSTEMD_SERVICE_FILE'" <<EOL
[Unit]
Description=Home Assistant
After=network-online.target

[Service]
Type=simple
User=%i
# 设置环境变量，确保系统服务能找到 Python 库
Environment="PATH=$HA_INSTALL_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=$HA_INSTALL_DIR/python3.14/lib"
Environment="PYTHONHOME=$HA_INSTALL_DIR/python3.14"
ExecStart=$HA_INSTALL_DIR/bin/hass -c "$HA_CONFIG_DIR"
RestartForceExitStatus=100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload || log_error "无法重新加载 systemd daemon。"
sudo systemctl enable homeassistant@"$HA_USER" || log_error "无法启用 小鸥智能 systemd 服务。"

# 检查服务是否已经启动，如果已启动则先停止再重启
if sudo systemctl is-active --quiet homeassistant@"$HA_USER"; then
    sudo systemctl stop homeassistant@"$HA_USER" || log_warn "停止现有服务失败。"
fi

sudo systemctl start homeassistant@"$HA_USER" || log_error "无法启动 小鸥智能 systemd 服务。"

log_info "小鸥智能 systemd 服务已创建并启动。您可以使用 'sudo systemctl status homeassistant@$HA_USER' 查看状态。"
log_info "整个 小鸥智能 环境已设置完毕，并应用了您的自定义配置。"
log_info "首次启动可能需要一些时间来下载依赖和初始化。"
log_info "ESPHome 可执行文件路径: $HA_INSTALL_DIR/esphome_venv/venv/bin/esphome"
log_info "您可以通过访问您服务器的 IP 地址:1404 来访问您的控制系统。"

# 等待启动并检查服务状态
log_info "等待 小鸥智能 启动并检查服务状态..."
# 短暂等待，然后进行多次检查，避免首次启动慢导致误判
for i in {1..3}; do
    sleep 20 # 每次等待 20 秒，共 60 秒
    if sudo systemctl is-active --quiet homeassistant@"$HA_USER"; then
        log_info "小鸥智能 服务正在运行。"
        log_info "您可以在浏览器中访问 http://$(hostname -I | awk '{print $1}'):1404 访问界面"
        exit 0 # 服务正常则直接退出
    fi
done

log_warn "小鸥智能 服务在预期时间内未能完全启动，请检查日志："
sudo journalctl -u homeassistant@"$HA_USER" -f # 持续显示日志，便于用户排查
