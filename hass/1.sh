#!/bin/bash

# --- 配置参数 ---
# Home Assistant 运行的用户
HA_USER="zych_ha"
# Home Assistant 的安装目录 (虚拟环境将在此处创建)
HA_INSTALL_DIR="/srv/$HA_USER"
# Home Assistant 的配置目录 (通常是 ~/.homeassistant，我们会使用这个)
HA_CONFIG_DIR="/home/$HA_USER/.homeassistant"
# 您的 ha-mirror 仓库的 Git URL
# IMPORTANT: 建议使用原始的 GitHub URL，并通过 GIT_PROXY 变量进行代理。
#            如果您的 "url.yh-iot.cloudns.org" 是一个 GitHub 镜像，并且期望将原始 GitHub URL 作为其路径一部分，
#            请将其修改为正确的镜像地址格式，例如：
#            HA_MIRROR_REPO="https://url.yh-iot.cloudns.org/yuanzhou029/ha-mirror.git"
HA_MIRROR_REPO="https://gitee.com/xahwkj/hass-mirror.git" # <--- **强烈建议使用原始 GitHub URL**

# ha-mirror 仓库中包含 Home Assistant 配置文件的子目录名称
HA_MIRROR_CONFIG_SUBDIR="config"

# Home Assistant 的固定安装版本。例如："2024.1.0"
# 如果您想安装最新版本，可以将其留空，但为了固定版本，建议指定。
# 示例：HA_VERSION="2024.1.0"
HA_VERSION="2026.2.3" # <--- **** 请在这里指定您需要的 Home Assistant 版本 ****

# --- PIP 包源配置 ---
# 是否使用您的 GitHub 仓库作为 PIP 包的本地镜像。
# 如果设置为 "true"，脚本将尝试从 HA_MIRROR_REPO_INNER/HA_LOCAL_PIP_MIRROR_SUBDIR_INNER 路径安装所有包。
# 这要求您已手动将所有 Home Assistant 及其依赖的 .whl 文件下载并上传到该 GitHub 仓库子目录。
# 如果设置为 "false"，脚本将使用 PIP_MIRROR_URL 进行安装。
USE_LOCAL_PIP_MIRROR="true" # <--- **根据您的需求设置 "true" 或 "false"**

# 如果 USE_LOCAL_PIP_MIRROR 为 "true"，此变量指定您的 ha-mirror 仓库中存放 .whl 文件的子目录。
HA_LOCAL_PIP_MIRROR_SUBDIR="pypi_packages" # <--- **请确保此目录在您的 Git 仓库中存在且包含所有 .whl 文件**

# 如果 USE_LOCAL_PIP_MIRROR 为 "false"，则使用此 PyPI 镜像源
PIP_MIRROR_URL="https://repo.huaweicloud.com/repository/pypi/simple" # <--- **您可以选择其他镜像源**

# GitHub 代理/镜像 (可选，如果直接连接 GitHub 困难)
# 例如: http://proxy.example.com:port 或 https://proxy.example.com:port
# 如果您不需要代理，请留空：GIT_PROXY=""
GIT_PROXY="" # <--- **如果需要，请填写您的代理地址，例如 "http://192.168.1.1:7890"**

# --- 函数定义 ---
log_info() {
    echo "INFO: $1"
}

log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# 检查当前用户是否为 root
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本需要 root 权限运行。请使用 'sudo' 执行。"
fi

log_info "正在开始 Hass 原生安装和自定义配置部署..."
if [ "$USE_LOCAL_PIP_MIRROR" = "true" ]; then
    log_info "PIP 将尝试从您的 GitHub 仓库本地镜像获取包。"
    log_info "重要：请确保您的 GitHub 仓库的 '$HA_LOCAL_PIP_MIRROR_SUBDIR' 目录中包含了所有 Home Assistant 及其依赖的 .whl 文件，并且文件名正确、内容完整。"
    log_info "如果您曾遇到 'setuptools-82.0.0' 的错误，请务必先检查并删除本地镜像中任何名为 'setuptools-82.0.0-py3-none-any.whl' 的文件，因为它是一个不存在的、可能已损坏的版本。"
else
    log_info "PIP 将使用 PyPI 镜像源获取包。"
fi

# 0. 检查并安装必要工具 (python3-venv, git, build-essential, python3-dev, git-lfs)
log_info "正在检查并安装必要的系统工具 (python3-venv, git, build-essential, python3-dev, git-lfs)..."
# 注意：git-lfs 的包名可能因发行版而异。在 Debian/Ubuntu 上是 git-lfs。
REQUIRED_TOOLS=("python3-venv" "git" "build-essential" "python3-dev" "git-lfs") 
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! dpkg -s "$tool" &>/dev/null; then # 适用于 Debian/Ubuntu
        log_info "$tool 未安装，正在尝试安装..."
        sudo apt update || log_error "apt update 失败，请检查网络或软件源。"
        sudo apt install -y "$tool" || log_error "无法安装 $tool。请手动安装或检查您的包管理器。"
    else
        log_info "$tool 已安装。"
    fi
done

# 1. 创建 Home Assistant 用户和组
log_info "正在创建 Hass 用户和组 '$HA_USER'..."
if ! id -u "$HA_USER" >/dev/null 2>&1; then
    # 动态构建 groupadd 命令，只添加存在的组
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
    # input 组通常都存在
    GROUPS_TO_ADD+="input"
    
    # 移除末尾可能的逗号
    GROUPS_TO_ADD=$(echo "$GROUPS_TO_ADD" | sed 's/,$//')

    log_info "将用户 '$HA_USER' 添加到组: $GROUPS_TO_ADD"
    sudo useradd -r -m -G "$GROUPS_TO_ADD" "$HA_USER" || log_error "无法创建用户 '$HA_USER'。请检查日志。"
    
    # 稍作等待，确保系统完全识别新用户
    sleep 3 
    log_info "用户 '$HA_USER' 创建成功。"
else
    log_info "用户 '$HA_USER' 已存在。"
fi

# 2. 创建安装目录并设置权限
log_info "正在创建 Hass 安装目录 '$HA_INSTALL_DIR'..."
sudo mkdir -p "$HA_INSTALL_DIR" || log_error "无法创建目录 '$HA_INSTALL_DIR'。"

# 再次检查用户是否存在，以防 systemd 还在加载
if ! id -u "$HA_USER" >/dev/null 2>&1; then
    log_error "用户 '$HA_USER' 似乎未完全创建或识别。请尝试手动运行 'id $HA_USER'。"
fi

sudo chown -R "$HA_USER":"$HA_USER" "$HA_INSTALL_DIR" || log_error "无法设置目录权限 '$HA_INSTALL_DIR'。请检查用户 '$HA_USER' 是否已成功创建并被系统识别。"

# 3. 切换到 Home Assistant 用户，并执行后续操作 (使用临时脚本文件)
log_info "正在切换到用户 '$HA_USER' 以设置虚拟环境和安装 Home Assistant..."

# 将内部脚本内容写入临时文件
TEMP_HA_SCRIPT="/tmp/install_ha_user_script.sh"
cat > "$TEMP_HA_SCRIPT" << 'EOF_INNER_SCRIPT'
    set -e # 任何命令失败立即退出

    log_info() { echo "INFO (HA_USER): $1"; }
    log_error() { echo "ERROR (HA_USER): $1" >&2; exit 1; }

    # 定义从外部脚本继承的变量 (需要替换)
    HA_INSTALL_DIR_INNER="{{HA_INSTALL_DIR}}"
    HA_CONFIG_DIR_INNER="{{HA_CONFIG_DIR}}"
    HA_MIRROR_REPO_INNER="{{HA_MIRROR_REPO}}"
    HA_MIRROR_CONFIG_SUBDIR_INNER="{{HA_MIRROR_CONFIG_SUBDIR}}"
    PIP_MIRROR_URL_INNER="{{PIP_MIRROR_URL}}"
    GIT_PROXY_INNER="{{GIT_PROXY}}"
    HA_USER_INNER="{{HA_USER}}" # 也需要传递用于 chown
    HA_VERSION_INNER="{{HA_VERSION}}" # Home Assistant 版本变量
    USE_LOCAL_PIP_MIRROR_INNER="{{USE_LOCAL_PIP_MIRROR}}" # 是否使用本地 PIP 镜像
    HA_LOCAL_PIP_MIRROR_SUBDIR_INNER="{{HA_LOCAL_PIP_MIRROR_SUBDIR}}" # 本地 PIP 镜像子目录

    log_info "当前用户: $(whoami)"
    log_info "当前工作目录: $(pwd)"
    log_info "PATH 环境变量: $PATH"

    # 显式地将 /usr/bin 添加到 PATH，确保可以找到 gcc 等编译工具
    export PATH="/usr/bin:$PATH"
    log_info "更新后 PATH 环境变量: $PATH"

    # 切换到安装目录
    cd "$HA_INSTALL_DIR_INNER" || log_error "用户 '$HA_USER_INNER' 无法切换到目录 '$HA_INSTALL_DIR_INNER'。"

    # 3.1 创建 Python 虚拟环境
    log_info "正在创建 Python 虚拟环境..."
    # 明确使用 python3 -m venv
    python3 -m venv . || log_error "无法创建 Python 虚拟环境。请确保 'python3-venv' 已安装。"
    log_info "虚拟环境创建成功。"

    # 3.2 激活虚拟环境
    log_info "正在激活虚拟环境..."
    # 确保使用 bash 来 source
    source bin/activate || log_error "无法激活虚拟环境。请检查虚拟环境是否完整或您的 shell是否支持 'source' 命令。"
    log_info "虚拟环境激活成功。"
    log_info "激活后 PATH 环境变量: $PATH"

    # 3.3 配置 pip 使用国内镜像源 或 本地镜像
    # 我们先克隆仓库，确保本地镜像文件存在
    
    # --- Git Clone/Pull 增强 ---
    MAX_RETRIES=5
    RETRY_DELAY=10 # seconds

    log_info "正在克隆或更新 ha-mirror 仓库到 '$HA_INSTALL_DIR_INNER/ha-mirror-repo'..."
    CLONE_URL_INNER="$HA_MIRROR_REPO_INNER"
    HA_MIRROR_REPO_PATH="$HA_INSTALL_DIR_INNER/ha-mirror-repo"

    # 设置 Git 代理环境变量
    if [ -n "$GIT_PROXY_INNER" ]; then
        log_info "正在设置 Git 环境变量代理: $GIT_PROXY_INNER"
        export ALL_PROXY="$GIT_PROXY_INNER"
        export HTTPS_PROXY="$GIT_PROXY_INNER"
        export HTTP_PROXY="$GIT_PROXY_INNER"
    fi

    clone_or_pull_repo() {
        local attempt=1
        while [ $attempt -le $MAX_RETRIES ]; do
            log_info "Git 操作尝试 $attempt/$MAX_RETRIES..."
            local success=0
            if [ ! -d "$HA_MIRROR_REPO_PATH" ]; then
                log_info "尝试克隆 ha-mirror 仓库..."
                if git clone "$CLONE_URL_INNER" "$HA_MIRROR_REPO_PATH"; then
                    log_info "ha-mirror 仓库克隆成功。"
                    success=1
                fi
            else
                log_info "ha-mirror 仓库已存在，尝试执行 'git pull' 更新。"
                # 切换到仓库目录执行 pull
                cd "$HA_MIRROR_REPO_PATH" || log_error "无法进入 $HA_MIRROR_REPO_PATH"
                if git pull; then
                    log_info "ha-mirror 仓库更新成功。"
                    success=1
                fi
                cd "$HA_INSTALL_DIR_INNER" # 即使失败也要返回
            fi

            if [ "$success" -eq 1 ]; then
                # 在 Git clone/pull 成功后，初始化并拉取 Git LFS 文件
                log_info "执行 Git LFS 初始化和拉取..."
                # 先进入仓库目录
                cd "$HA_MIRROR_REPO_PATH" || log_error "无法进入 $HA_MIRROR_REPO_PATH"
                git lfs install || { log_error "Git LFS 安装失败。请确保 git-lfs 已正确安装。"; return 1; } # LFS install 只需运行一次
                if git lfs pull; then
                    log_info "Git LFS 文件拉取成功。"
                    cd "$HA_INSTALL_DIR_INNER" # 返回到虚拟环境的根目录
                    return 0 # Git 和 Git LFS 都成功
                else
                    log_info "Git LFS 文件拉取失败。可能网络不稳定或代理问题。将在 $RETRY_DELAY 秒后重试..."
                    cd "$HA_INSTALL_DIR_INNER" # 返回到虚拟环境的根目录
                fi
            fi

            log_info "Git 或 Git LFS 操作失败，将在 $RETRY_DELAY 秒后重试..."
            sleep $RETRY_DELAY
            attempt=$((attempt + 1))
        done
        log_error "多次尝试后无法克隆/更新 ha-mirror 仓库或拉取 Git LFS 文件。请检查 Git 代理、LFS 配置、仓库地址或网络连接。"
    }

    clone_or_pull_repo

    # 清除 Git 代理环境变量，以免影响后续操作
    if [ -n "$GIT_PROXY_INNER" ]; then
        unset ALL_PROXY HTTPS_PROXY HTTP_PROXY
        log_info "Git 代理环境变量已清除。"
    fi

    # --- 增强的文件完整性检查 ---
    # 整体仓库大小的粗略检查 (你可能需要根据你的 GitHub 仓库的实际大小来调整这个值)
    # 这个值应该能容纳除了那个100MB大文件之外的所有文件，或者所有文件都下载完整后的总大小。
    MIN_EXPECTED_REPO_SIZE_MB=80 # 例如，如果你的100MB文件是HA核心，那么总大小应该在100MB以上
    REPO_SIZE_MB=$(du -sm "$HA_MIRROR_REPO_PATH" | awk '{print $1}')
    if [ "$REPO_SIZE_MB" -lt "$MIN_EXPECTED_REPO_SIZE_MB" ]; then
        log_error "ha-mirror 仓库 ($REPO_SIZE_MB MB) 小于预期大小 ($MIN_EXPECTED_REPO_SIZE_MB MB)。可能未完全下载或内容不完整。请检查仓库内容并确保网络稳定。"
    else
        log_info "ha-mirror 仓库整体大小检查通过 ($REPO_SIZE_MB MB)。"
    fi

    # 针对 100MB 大文件的特定检查
    # 假设这个 100MB 文件是 homeassistant 核心的 .whl 文件
    # 请根据你的实际情况调整文件名模式和预期大小！
    if [ "$USE_LOCAL_PIP_MIRROR_INNER" = "true" ]; then
        LOCAL_WHEEL_DIR="$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_LOCAL_PIP_MIRROR_SUBDIR_INNER"
        if [ -n "$HA_VERSION_INNER" ]; then
            HA_CORE_WHL_FILENAME_PATTERN="homeassistant-$HA_VERSION_INNER-*.whl" # 例如：homeassistant-2026.2.3-py3-none-any.whl
            HA_CORE_WHL_PATH=$(find "$LOCAL_WHEEL_DIR" -maxdepth 1 -name "$HA_CORE_WHL_FILENAME_PATTERN" -print -quit)
            
            if [ -f "$HA_CORE_WHL_PATH" ]; then
                # 获取文件大小 (字节)
                HA_CORE_WHL_SIZE_BYTES=$(stat -c%s "$HA_CORE_WHL_PATH")
                # 预期大小 (字节) - 假设是 100MB，换算成字节
                # 请将 100 替换为你的大文件实际 MB 大小，并考虑稍微的浮动范围
                MIN_EXPECTED_HA_WHL_SIZE_BYTES=$((100 * 1024 * 1024)) # 示例：100MB
                
                log_info "检查 Home Assistant 核心安装包 '$HA_CORE_WHL_PATH' 的大小..."
                log_info "实际大小: $(($HA_CORE_WHL_SIZE_BYTES / (1024*1024))) MB, 预期最小大小: $(($MIN_EXPECTED_HA_WHL_SIZE_BYTES / (1024*1024))) MB。"

                if [ "$HA_CORE_WHL_SIZE_BYTES" -lt "$MIN_EXPECTED_HA_WHL_SIZE_BYTES" ]; then
                    log_error "错误：Home Assistant 核心安装包 '$HA_CORE_WHL_PATH' 大小 ($HA_CORE_WHL_SIZE_BYTES 字节) 小于预期最小大小 ($MIN_EXPECTED_HA_WHL_SIZE_BYTES 字节)。这表示大文件未完整下载。请检查 Git LFS 配置、网络连接或代理设置。"
                else
                    log_info "Home Assistant 核心安装包大小检查通过。"
                fi
            else
                log_error "错误：本地 PIP 镜像目录 '$LOCAL_WHEEL_DIR' 中未找到 Home Assistant 版本 '$HA_VERSION_INNER' 的 .whl 文件。请确保已包含该包，且文件名符合 '$HA_CORE_WHL_FILENAME_PATTERN' 模式。"
            fi
        else
            log_info "HA_VERSION 未指定，跳过特定 Home Assistant 核心 .whl 文件大小检查。"
        fi
    fi
    # --- 增强的文件完整性检查结束 ---


    # --- PIP 配置和本地镜像文件检查 ---
    if [ "$USE_LOCAL_PIP_MIRROR_INNER" = "true" ]; then
        log_info "正在配置 pip 使用本地镜像源: $HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_LOCAL_PIP_MIRROR_SUBDIR_INNER"
        
        LOCAL_WHEEL_DIR="$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_LOCAL_PIP_MIRROR_SUBDIR_INNER"
        # 目录存在性已在 Git LFS 检查中隐式处理，但再次强调一下
        if [ ! -d "$LOCAL_WHEEL_DIR" ]; then
             log_error "错误：启用了本地 PIP 镜像，但本地镜像目录 '$LOCAL_WHEEL_DIR' 不存在。这不应该发生，请检查之前的 Git 克隆步骤。"
        fi

        log_info "检查本地 PIP 镜像中核心包的存在性..."
        
        # 检查 setuptools
        if ! ls "$LOCAL_WHEEL_DIR"/setuptools-*.whl 1>/dev/null 2>&1; then
            log_error "错误：本地 PIP 镜像目录 '$LOCAL_WHEEL_DIR' 中未找到 'setuptools' 的 .whl 文件。请确保已包含该包。"
        fi
        
        # 检查 wheel
        if ! ls "$LOCAL_WHEEL_DIR"/wheel-*.whl 1>/dev/null 2>&1; then
            log_error "错误：本地 PIP 镜像目录 '$LOCAL_WHEEL_DIR' 中未找到 'wheel' 的 .whl 文件。请确保已包含该包。"
        fi

        # 检查 homeassistant (如果指定了固定版本) - 存在性检查，大小已在前面检查
        if [ -n "$HA_VERSION_INNER" ]; then
            HA_CORE_WHL_FILENAME_PATTERN="homeassistant-$HA_VERSION_INNER-*.whl"
            if ! ls "$LOCAL_WHEEL_DIR"/$HA_CORE_WHL_FILENAME_PATTERN 1>/dev/null 2>&1; then
                log_error "错误：本地 PIP 镜像目录 '$LOCAL_WHEEL_DIR' 中未找到 Home Assistant 版本 '$HA_VERSION_INNER' 的 .whl 文件。请确保已包含该包，且文件名符合 '$HA_CORE_WHL_FILENAME_PATTERN' 模式。"
            fi
        else
            log_info "Home Assistant 将安装最新版，跳过特定版本 .whl 文件检查。但仍会检查是否存在任意 Home Assistant 包。"
            if ! ls "$LOCAL_WHEEL_DIR"/homeassistant-*.whl 1>/dev/null 2>&1; then
                log_error "错误：启用了本地 PIP 镜像，但本地镜像目录 '$LOCAL_WHEEL_DIR' 中未找到任何 'homeassistant' 的 .whl 文件。请确保已包含该包。"
            fi
        fi

        log_info "本地 PIP 镜像核心包检查通过。所有其他 Home Assistant 依赖包也必须存在于此目录。如果您在安装过程中遇到 '找不到满足要求的版本' 的错误，请仔细检查 '$LOCAL_WHEEL_DIR' 目录中的所有依赖 .whl 文件是否完整且正确。"
        
        PIP_INSTALL_OPTS="--no-index --find-links=$LOCAL_WHEEL_DIR"
    else
        log_info "正在配置 pip 使用国内镜像源: $PIP_MIRROR_URL_INNER"
        python3 -m pip config set global.index-url "$PIP_MIRROR_URL_INNER" || log_error "无法设置 pip 镜像源。"
        TRUSTED_HOST_INNER=$(echo "$PIP_MIRROR_URL_INNER" | sed -E 's/https?:\/\/(.*)\/simple.*/\1/')
        python3 -m pip config set global.trusted-host "$TRUSTED_HOST_INNER" || log_error "无法设置 pip trusted-host。"
        PIP_INSTALL_OPTS="" # 无特殊选项，使用全局配置的 PyPI 镜像
    fi
    log_info "pip 配置完成。"
    # --- PIP 配置和本地镜像文件检查结束 ---

    # 3.4 安装 Home Assistant 核心
    log_info "正在安装官方 Hass 核心..."
    # 优先安装 setuptools 和 wheel 以确保构建依赖正常
    python3 -m pip install --upgrade setuptools wheel $PIP_INSTALL_OPTS || log_error "无法升级 setuptools/wheel。请检查您的本地镜像文件是否损坏或缺失。"
    
    HA_INSTALL_TARGET="homeassistant"
    if [ -n "$HA_VERSION_INNER" ]; then
        HA_INSTALL_TARGET="homeassistant==$HA_VERSION_INNER"
        log_info "正在安装 Home Assistant 固定版本: $HA_INSTALL_TARGET"
    else
        log_info "HA_VERSION 未指定，正在安装 Home Assistant 最新版本。"
    fi

    # 使用 PIP_INSTALL_OPTS 来控制包源
    python3 -m pip install $PIP_INSTALL_OPTS "$HA_INSTALL_TARGET" || log_error "无法安装 Home Assistant '$HA_INSTALL_TARGET'。请检查网络连接、PyPI 镜像源/本地镜像内容、Python 开发文件 (python3-dev) 或编译工具 (build-essential)。"
    log_info "官方 Home Assistant 核心安装成功。"

    # 新增步骤：预安装 Home Assistant 运行时可能需要的特定依赖
    log_info "正在预安装 Home Assistant 配置验证时可能需要的额外依赖..."
    ADDITIONAL_PACKAGES=(
        "colorlog==6.10.1"
        "home-assistant-frontend==20260128.6"
        "pymicro-vad==1.0.1"
        "pyspeex-noise==1.0.2"
        "mutagen==1.47.0"
        "ha-ffmpeg==3.2.2"
        "hassil==3.5.0"
        "home-assistant-intents==2026.1.28"
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
)
    
    for pkg in "${ADDITIONAL_PACKAGES[@]}"; do
        log_info "正在安装 $pkg..."
        # 同样使用 PIP_INSTALL_OPTS 来控制包源
        python3 -m pip install $PIP_INSTALL_OPTS "$pkg" || log_error "无法安装依赖包 '$pkg'。请检查网络连接、本地镜像内容或包名是否正确。"
    done
    log_info "所有额外依赖预安装完成。"


    # 3.5 验证 hass 脚本是否存在和可执行
    HASS_VENV_PATH_INNER="$HA_INSTALL_DIR_INNER/bin/hass"
    if [ ! -f "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：Home Assistant 的 'hass' 可执行文件未找到于 '$HASS_VENV_PATH_INNER'。Home Assistant 可能安装失败。"
    fi
    if [ ! -x "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：Home Assistant 的 'hass' 可执行文件在 '$HASS_VENV_PATH_INNER' 没有执行权限。"
    fi
    log_info "'hass' 可执行文件存在并有执行权限: $HASS_VENV_PATH_INNER"

    # 3.6 部署自定义配置和组件 (来自 ha-mirror 的 config 目录)
    log_info "正在部署自定义配置和组件到 Home Assistant 配置目录 '$HA_CONFIG_DIR_INNER'..."
    mkdir -p "$HA_CONFIG_DIR_INNER" || log_error "无法创建 Home Assistant 配置目录。"
    
    # 复制 ha-mirror/config 中的内容到 HA_CONFIG_DIR_INNER
    cp -r "$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_MIRROR_CONFIG_SUBDIR_INNER"/* "$HA_CONFIG_DIR_INNER/" || log_error "无法复制自定义配置。"
    
    # 确保配置目录的权限正确
    chown -R "$HA_USER_INNER":"$HA_USER_INNER" "$HA_CONFIG_DIR_INNER" || log_error "无法设置配置目录权限。"
    log_info "自定义配置和组件部署成功。"

    # 3.7 验证配置 (可选，但强烈推荐)
    log_info "正在验证 Home Assistant 配置..."
    "$HASS_VENV_PATH_INNER" --script check_config -c "$HA_CONFIG_DIR_INNER" || {
        log_error "Home Assistant 配置验证失败。请检查配置错误。您可能需要手动检查日志。"
    }
    log_info "Home Assistant 基础配置验证完成。"

    log_info "Home Assistant 安装和自定义配置部署完成！"
    log_info "您可以现在激活虚拟环境并启动 Home Assistant： source $HA_INSTALL_DIR_INNER/bin/activate && $HASS_VENV_PATH_INNER -c $HA_CONFIG_DIR_INNER"
EOF_INNER_SCRIPT

# 替换内部脚本中的占位符
sed -i \
    -e "s|{{HA_INSTALL_DIR}}|$HA_INSTALL_DIR|g" \
    -e "s|{{HA_CONFIG_DIR}}|$HA_CONFIG_DIR|g" \
    -e "s|{{HA_USER}}|$HA_USER|g" \
    -e "s|{{HA_MIRROR_REPO}}|$HA_MIRROR_REPO|g" \
    -e "s|{{HA_MIRROR_CONFIG_SUBDIR}}|$HA_MIRROR_CONFIG_SUBDIR|g" \
    -e "s|{{PIP_MIRROR_URL}}|$PIP_MIRROR_URL|g" \
    -e "s|{{GIT_PROXY}}|$GIT_PROXY|g" \
    -e "s|{{HA_VERSION}}|$HA_VERSION|g" \
    -e "s|{{USE_LOCAL_PIP_MIRROR}}|$USE_LOCAL_PIP_MIRROR|g" \
    -e "s|{{HA_LOCAL_PIP_MIRROR_SUBDIR}}|$HA_LOCAL_PIP_MIRROR_SUBDIR|g" \
    "$TEMP_HA_SCRIPT"

# 赋予临时脚本执行权限
sudo chmod +x "$TEMP_HA_SCRIPT"

# 以 Home Assistant 用户身份执行临时脚本
# 明确指定使用 bash 来执行，以确保 'source' 命令可用
sudo -u "$HA_USER" bash "$TEMP_HA_SCRIPT" || log_error "以用户 '$HA_USER' 执行内部脚本失败。"

# 清理临时脚本文件
sudo rm -f "$TEMP_HA_SCRIPT"

# 4. 创建 systemd 服务 (以便开机自启和方便管理)
log_info "正在创建 systemd 服务以便 Home Assistant 开机自启..."
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
sudo systemctl enable homeassistant@"$HA_USER" || log_error "无法启用 Home Assistant systemd 服务。"
sudo systemctl start homeassistant@"$HA_USER" || log_error "无法启动 Home Assistant systemd 服务。"

log_info "Home Assistant systemd 服务已创建并启动。您可以使用 'sudo systemctl status homeassistant@$HA_USER' 查看状态。"
log_info "整个 Home Assistant 环境已设置完毕，并应用了您的自定义配置。"
log_info "首次启动可能需要一些时间来下载依赖和初始化。"
log_info "您可以通过访问您服务器的 IP 地址:8123 来访问您的控制系统。"
