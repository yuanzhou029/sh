#!/bin/bash

# --- 配置参数 ---
#  运行的用户
HA_USER="zych_ha"
#  的安装目录 (虚拟环境将在此处创建)
HA_INSTALL_DIR="/srv/$HA_USER"
# 的配置目录 
HA_CONFIG_DIR="/home/$HA_USER/.xoai"
# 您的 ha-mirror 仓库的 Git URL
HA_MIRROR_REPO="https://pxy.140407.xyz/https://github.com/yuanzhou029/ha-mirror.git"
# ha-mirror 仓库中包含配置文件的子目录名称
HA_MIRROR_CONFIG_SUBDIR="config"
HA_PYTHON3143_URL="https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/sh/releases/download/3.14.3/python-3.14.3-linux-x86_64.tar.gz"
# --- 国内镜像源配置 ---
# PyPI 镜像源 (选择一个稳定且速度快的)
# 推荐使用清华大学或阿里云
PIP_MIRROR_URL="https://repo.huaweicloud.com/repository/pypi/simple"

# GitHub Actions artifacts 下载 URL(安装程序主包)
HA_WHEEL_URL="https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/APK/releases/download/xoai-v20260321.2/xoai-2026.3.3-py3-none-any.zip"

# --- 函数定义 ---
log_info() {
    echo "INFO: $1"
}

log_warn() {
    echo "WARN: $1"
}

log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# 检查当前用户是否为 root
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本需要 root 权限运行。请使用 'sudo' 执行。"
fi

log_info "正在开始 小鸥智能 原生安装和自定义配置部署 (利用国内镜像)..."

# 检查磁盘空间
check_disk_space() {
    local required_gb=${1:-2}  # 默认需要 2GB
    local target_dir="${2:-/srv}"
    local parent_dir=$(dirname "$target_dir")
    
    # 如果目标目录不存在，检查其父目录的磁盘空间
    if [ ! -d "$target_dir" ]; then
        if [ -d "$parent_dir" ]; then
            log_info "目标目录 $target_dir 不存在，检查父目录 $parent_dir 的空间..."
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
check_disk_space 3 "/srv/zych_ha"  # 需要至少 3GB 空间

# 0. 检查并安装必要工具
log_info "正在检查并安装必要的系统工具 (python3-venv, git, build-essential, python3-dev, wget, unzip)..."
REQUIRED_TOOLS=("git" "build-essential" "python3-dev" "wget" "unzip")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! dpkg -s "$tool" &>/dev/null; then
        log_info "$tool 未安装，正在尝试安装..."
        sudo apt update || log_error "apt update 失败，请检查网络或软件源。"
        sudo apt install -y "$tool" || log_error "无法安装 $tool。请手动安装或检查您的包管理器。"
    else
        log_info "$tool 已安装。"
    fi
done

# 1. 创建  用户和组
log_info "正在创建 小鸥智能 用户和组 '$HA_USER'..."
if ! id -u "$HA_USER" >/dev/null 2>&1; then
    GROUPS_TO_ADD=""
    if getent group dialout >/dev/null; then
        GROUPS_TO_ADD+="dialout,"
    else
        log_info "系统无 'dialout' 组，跳过添加。"
    fi
    if getent group gpio >/dev/null; then
        GROUPS_TO_ADD+="gpio,"
    else
        log_info "系统无 'gpio' 组，跳过添加。"
    fi
    GROUPS_TO_ADD+="input"
    GROUPS_TO_ADD=$(echo "$GROUPS_TO_ADD" | sed 's/,$//')

    log_info "将用户 '$HA_USER' 添加到组: $GROUPS_TO_ADD"
    sudo useradd -r -m -G "$GROUPS_TO_ADD" "$HA_USER" || log_error "无法创建用户 '$HA_USER'。请检查日志。"
    sleep 3 
    log_info "用户 '$HA_USER' 创建成功。"
else
    log_info "用户 '$HA_USER' 已存在。"
fi

# 2. 创建安装目录并设置权限
log_info "正在创建 小鸥智能 安装目录 '$HA_INSTALL_DIR'..."
sudo mkdir -p "$HA_INSTALL_DIR" || log_error "无法创建目录 '$HA_INSTALL_DIR'。"
sudo chown -R "$HA_USER":"$HA_USER" "$HA_INSTALL_DIR" || log_error "无法设置目录权限 '$HA_INSTALL_DIR'。"

# 3. 切换到 小鸥智能 用户，并执行后续操作
log_info "正在切换到用户 '$HA_USER' 以设置虚拟环境和安装 小鸥智能..."

# 将内部脚本内容写入临时文件
TEMP_HA_SCRIPT="/tmp/install_ha_user_script.sh"
cat > "$TEMP_HA_SCRIPT" << 'EOF_INNER_SCRIPT'
    set -e # 任何命令失败立即退出

    log_info() { echo "INFO (HA_USER): $1"; }
    log_warn() { echo "WARN (HA_USER): $1"; }
    log_error() { echo "ERROR (HA_USER): $1" >&2; exit 1; }

    log_info "当前用户: $(whoami)"
    log_info "当前工作目录: $(pwd)"

    # 定义从外部脚本继承的变量
    HA_INSTALL_DIR_INNER="{{HA_INSTALL_DIR}}"
    HA_CONFIG_DIR_INNER="{{HA_CONFIG_DIR}}"
    HA_MIRROR_REPO_INNER="{{HA_MIRROR_REPO}}"
    HA_MIRROR_CONFIG_SUBDIR_INNER="{{HA_MIRROR_CONFIG_SUBDIR}}"
    PIP_MIRROR_URL_INNER="{{PIP_MIRROR_URL}}"
    HA_WHEEL_URL_INNER="{{HA_WHEEL_URL}}"
    HA_USER_INNER="{{HA_USER}}"
    HA_PYTHON="{{HA_PYTHON3143_URL}}"

    # 显式地将 /usr/bin 添加到 PATH
    export PATH="/usr/bin:$PATH"
    log_info "更新后 PATH 环境变量: $PATH"

    # 切换到安装目录
    cd "$HA_INSTALL_DIR_INNER" || log_error "用户 '$HA_USER_INNER' 无法切换到目录 '$HA_INSTALL_DIR_INNER'。"
    
    # 安装python3.14环境
    log_info "正在创建 Python3.14环境 目前python3.14不需要安装虚拟环境依赖包......"
    wget -O py3.14.tar.gz "$HA_PYTHON" || log_error "环境包无法下载"
    log_info "环境包下载成功准备解压包.."
    tar -xzf py3.14.tar.gz -C python3.14 --strip-components=1
    log_info "环境包解压成功......"
    log_info "...............开始设置环境..............."
    export PATH=$(pwd)/python3.14/bin:$PATH
    export LD_LIBRARY_PATH=$(pwd)/python3.14/lib:$LD_LIBRARY_PATH
    export PYTHONHOME=$(pwd)/python3.14
    log_info "...............环境设置成功..............."
    
    
    # 3.1 创建 Python 虚拟环境
    log_info "正在创建 Python 虚拟环境 目前python3.14不需要安装虚拟环境依赖包......"
    python3.14 -m venv . || log_error "无法创建 Python 虚拟环境。"
    log_info "虚拟环境创建成功。"

    # 3.2 激活虚拟环境
    log_info "正在激活虚拟环境......."
    source bin/activate || log_error "无法激活虚拟环境。"
    log_info "虚拟环境激活成功。"

    # 3.3 配置 pip 使用国内镜像源
    log_info "正在配置 pip 使用国内镜像源: $PIP_MIRROR_URL_INNER"
    pip config set global.index-url "$PIP_MIRROR_URL_INNER" || log_error "无法设置 pip 镜像源。"
    TRUSTED_HOST_INNER=$(echo "$PIP_MIRROR_URL_INNER" | sed -E 's/https?:\/\/(.*)\/simple.*/\1/')
    pip config set global.trusted-host "$TRUSTED_HOST_INNER" || log_error "无法设置 pip trusted-host。"
    log_info "pip 配置完成。"

    # 3.4 下载并安装从 GitHub Actions 构建的 小鸥智能 安装主包...............
    log_info "正在从 GitHub 下载 小鸥智能 安装主包 文件.........."
    
    # 使用安装目录下的临时子目录，避免占用 /tmp 空间
    TEMP_DOWNLOAD_DIR="$HA_INSTALL_DIR_INNER/temp_download_$$"
    mkdir -p "$TEMP_DOWNLOAD_DIR"
    cd "$TEMP_DOWNLOAD_DIR"
    
    log_info "下载目录: $TEMP_DOWNLOAD_DIR"
    log_info "下载 ZIP 文件到: $TEMP_DOWNLOAD_DIR/xoai_artifacts.zip"
    
    # 检查临时目录的可用空间
    AVAILABLE_SPACE_KB=$(df "$TEMP_DOWNLOAD_DIR" | tail -1 | awk '{print $4}')
    AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))
    log_info "临时下载目录可用空间: ${AVAILABLE_SPACE_GB}GB"
    
    if [ $AVAILABLE_SPACE_GB -lt 2 ]; then
        log_error "临时目录空间不足！需要至少 2GB，当前只有 ${AVAILABLE_SPACE_GB}GB。"
    fi
    
    # 下载 zip 文件
    log_info "正在下载 小鸥智能 安装主包: $HA_WHEEL_URL_INNER"
    wget --no-check-certificate "$HA_WHEEL_URL_INNER" -O homeassistant_artifacts.zip || log_error "无法下载 小鸥智能 安装主包 文件。"
    
    # 获取下载文件大小
    FILE_SIZE=$(du -h xoai_artifacts.zip | cut -f1)
    log_info "下载的 ZIP 文件大小: $FILE_SIZE"
    
    # 解压 zip 文件
    log_info "正在解压 小鸥智能 安装主包............"
    unzip -q xoait_artifacts.zip || log_error "无法解压 小鸥智能 安装主包 文件。"
    
    # 查找 小鸥智能 安装主包 文件
    WHEEL_FILE=$(find . -name "*.whl" | head -n 1)
    DEPENDENCIES_DIR=$(find . -name "dependencies" -type d | head -n 1)
    
    if [ -z "$WHEEL_FILE" ]; then
        log_error "未找到 小鸥智能 安装主包 文件。"
    fi
    
    log_info "找到 小鸥智能 安装主包 文件: $WHEEL_FILE"
    
    if [ -n "$DEPENDENCIES_DIR" ]; then
        DEP_COUNT=$(ls "$DEPENDENCIES_DIR"/*.whl 2>/dev/null | wc -l)
        log_info "找到 dependencies 目录: $DEPENDENCIES_DIR (包含 $DEP_COUNT 个 wheel 文件)"
    else
        log_warn "未找到 dependencies 目录，可能不需要额外依赖。"
        mkdir -p dependencies
        DEPENDENCIES_DIR="dependencies"
    fi
    
    # 返回到虚拟环境目录
    cd "$HA_INSTALL_DIR_INNER"
    
    # 创建 dependencies 目录并复制文件
    if [ ! -d "dependencies" ]; then
        mkdir -p dependencies
    fi
    
    # 复制 小鸥智能 安装主包 文件到虚拟环境目录
    cp "$TEMP_DOWNLOAD_DIR/$WHEEL_FILE" . || log_error "无法复制 小鸥智能 安装主包 文件。"
    log_info "已将 小鸥智能 安装主包 文件复制到: $HA_INSTALL_DIR_INNER/$(basename "$WHEEL_FILE")"
    
    # 复制 dependencies 目录中的文件（逐个复制以节省空间）
    log_info "正在复制依赖文件..."
    if [ -d "$TEMP_DOWNLOAD_DIR/$DEPENDENCIES_DIR" ]; then
        cp -r "$TEMP_DOWNLOAD_DIR/$DEPENDENCIES_DIR"/* dependencies/ 2>/dev/null || true
        log_info "已将依赖文件复制到: $HA_INSTALL_DIR_INNER/dependencies/"
    fi
    
    # 清理临时下载目录
    log_info "正在清理临时下载目录: $TEMP_DOWNLOAD_DIR"
    rm -rf "$TEMP_DOWNLOAD_DIR"
    # pip 检测升级
    pip install --upgrade pip
    
    # 安装 小鸥智能 安装主包 文件
    log_info "正在安装 小鸥智能 安装主包: $(basename "$WHEEL_FILE")"
    pip install "$(basename "$WHEEL_FILE")" --find-links dependencies/ --prefer-binary || log_error "无法安装 小鸥智能 安装主包。"
    
    log_info "小鸥智能 安装主包 安装成功。"

    # 新增步骤：预安装 小鸥智能 安装主包 运行时可能需要的特定依赖
    log_info "正在预安装 小鸥智能 安装主包 配置验证时可能需要的额外依赖..............."
    ADDITIONAL_PACKAGES=(
        "colorlog==6.10.1"
        "PyQRCode==1.2.1"
        "xoai-frontend==20260319.1"
        "pymicro-vad==1.0.1"
        "pyspeex-noise==1.0.2"
        "mutagen==1.47.0"
        "ha-ffmpeg==3.2.2"
        "hassil==3.5.0"
        "home-assistant-intents==2026.3.3"
        "PyTurboJPEG==1.8.0"
        "av==16.0.1"
        "go2rtc-client==0.4.0"
        "PyNaCl==1.6.2"
        "openai==2.15.0"
        "RestrictedPython==8.1"
        "numpy==2.3.2"
        "bleak-retry-connector==4.4.3"
        "habluetooth==5.8.0"
        "aiousbwatcher==1.1.1"
        "pyserial==3.5"
        "python-matter-server==8.1.2"
        "aiodhcpwatcher==1.2.1"
        "aiodiscover==2.7.1"
        "file-read-backwards==2.0.0"
        "async-upnp-client==0.46.2"
        "bluetooth-adapters==2.1.0"
        "aiodns==4.0.0"
        "aiogithubapi==26.0.0"
        "aiohttp-asyncmdnsresolver==0.1.1"
        "aiohttp-fast-zlib==0.3.0"
        "aiohttp==3.13.3"
        "aiohttp_cors==0.8.1"
        "aiozoneinfo==0.2.3"
        "annotatedyaml==1.0.2"
        "astral==2.2"
        "async-interrupt==1.2.2"
        "atomicwrites-homeassistant==1.4.1"
        "attrs==25.4.0"
        "audioop-lts==0.2.1"
        "awesomeversion==25.8.0"
        "bcrypt==5.0.0"
        "bleak-retry-connector==4.6.0"
        "openai==2.21.0"
        "matter-python-client==0.4.1"
        "dbus-fast==3.1.2"
        "habluetooth==5.10.2"
    )
    
    for pkg in "${ADDITIONAL_PACKAGES[@]}"; do
        log_info "正在安装 $pkg..."
        pip install "$pkg" || log_warn "无法安装依赖包 '$pkg'，继续安装其他包。"
    done
    log_info "所有 小鸥智能 安装主包 额外依赖预安装完成。"

    # 3.5 验证 小鸥智能 脚本是否存在和可执行
    HASS_VENV_PATH_INNER="$HA_INSTALL_DIR_INNER/bin/hass"
    if [ ! -f "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：小鸥智能  的  可执行文件未找到于 '$HASS_VENV_PATH_INNER'。小鸥智能 可能安装失败。"
    fi
    if [ ! -x "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：小鸥智能  的 可执行文件在 '$HASS_VENV_PATH_INNER' 没有执行权限。"
    fi
    log_info "可执行文件存在并有执行权限: $HASS_VENV_PATH_INNER"

    # 3.6 克隆 ha-mirror 仓库 (用于获取自定义配置)
    log_info "正在克隆或更新 小鸥智能 默认配置  '$HA_INSTALL_DIR_INNER/远程仓库'.........."
    CLONE_URL_INNER="$HA_MIRROR_REPO_INNER"

    if [ ! -d "$HA_INSTALL_DIR_INNER/ha-mirror-repo" ]; then
        git clone "$CLONE_URL_INNER" "$HA_INSTALL_DIR_INNER/ha-mirror-repo" || log_error "无法克隆 默认配置 。请检查 Git 代理或仓库地址。"
        log_info "默认配置 克隆成功。"
    else
        log_info "ha-mirror 仓库已存在，正在执行 'git pull' 更新。"
        cd "$HA_INSTALL_DIR_INNER/ha-mirror-repo"
        git pull || log_error "无法更新 ha-mirror 仓库。请检查 Git 代理或仓库地址。"
        cd "$HA_INSTALL_DIR_INNER" # 返回到虚拟环境的根目录
        log_info "ha-mirror 仓库更新成功。"
    fi

    # 3.7 部署自定义配置和组件 (来自 默认配置 的 config 目录)
    log_info "正在部署自定义配置和组件到 小鸥智能  配置目录 '$HA_CONFIG_DIR_INNER'..."
    mkdir -p "$HA_CONFIG_DIR_INNER" || log_error "无法创建 小鸥智能 配置目录。"
    
    # 复制 ha-mirror/config 中的内容到 HA_CONFIG_DIR_INNER
    cp -r "$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_MIRROR_CONFIG_SUBDIR_INNER"/* "$HA_CONFIG_DIR_INNER/" || log_error "无法复制自定义配置。"
    
    # 确保配置目录的权限正确
    chown -R "$HA_USER_INNER":"$HA_USER_INNER" "$HA_CONFIG_DIR_INNER" || log_error "无法设置配置目录权限。"
    log_info "自定义配置和组件部署成功。"

    # 3.8 验证配置 (可选，但强烈推荐)
    log_info "正在验证 小鸥智能 配置..."
    "$HASS_VENV_PATH_INNER" --script check_config -c "$HA_CONFIG_DIR_INNER" || {
        log_error "小鸥智能 配置验证失败。请检查配置错误。您可能需要手动检查日志。"
    }
    log_info "小鸥智能 基础配置验证完成。"

    log_info "小鸥智能 安装和自定义配置部署完成！"
    log_info "您可以现在激活虚拟环境并启动 小鸥智能： source $HA_INSTALL_DIR_INNER/bin/activate && $HASS_VENV_PATH_INNER -c $HA_CONFIG_DIR_INNER"
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
    "$TEMP_HA_SCRIPT"

# 赋予临时脚本执行权限
sudo chmod +x "$TEMP_HA_SCRIPT"

# 以 小鸥智能 用户身份执行临时脚本
sudo -u "$HA_USER" bash "$TEMP_HA_SCRIPT" || log_error "以用户 '$HA_USER' 执行内部脚本失败。"

# 清理临时脚本文件
sudo rm -f "$TEMP_HA_SCRIPT"

# 4. 创建 systemd 服务
log_info "正在创建 systemd 服务以便 小鸥智能 开机自启............."
SYSTEMD_SERVICE_FILE="/etc/systemd/system/homeassistant@.service"
sudo bash -c "cat > '$SYSTEMD_SERVICE_FILE'" <<EOL
[Unit]
Description=Home Assistant
After=network-online.target

[Service]
Type=simple
User=%i
ExecStart=$HA_INSTALL_DIR/bin/hass -c "$HA_CONFIG_DIR"
RestartForceExitStatus=100
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl daemon-reload || log_error "无法重新加载 systemd daemon。"
sudo systemctl enable homeassistant@"$HA_USER" || log_error "无法启用 小鸥智能 systemd 服务。"
sudo systemctl start homeassistant@"$HA_USER" || log_error "无法启动 小鸥智能 systemd 服务。"

log_info "小鸥智能 systemd 服务已创建并启动。您可以使用 'sudo systemctl status homeassistant@$HA_USER' 查看状态。"
log_info "整个 小鸥智能 环境已设置完毕，并应用了您的自定义配置。"
log_info "首次启动可能需要一些时间来下载依赖和初始化。"
log_info "您可以通过访问您服务器的 IP 地址:1404 来访问您的控制系统。"

# 等待启动并检查服务状态
log_info "等待 小鸥智能 启动并检查服务状态..........."
sleep 40  # 等待启动
if sudo systemctl is-active --quiet homeassistant@"$HA_USER"; then
    log_info "小鸥智能 服务正在运行。"
    log_info "您可以在浏览器中访问 http://$(hostname -I | awk '{print $1}'):1404 访问界面"
else
    log_warn "小鸥智能 服务可能仍在启动中或遇到问题，请检查日志："
    sudo journalctl -u homeassistant@"$HA_USER" -f
fi
