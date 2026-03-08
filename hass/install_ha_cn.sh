#!/bin/bash

# --- 配置参数 ---
# Home Assistant 运行的用户
HA_USER="zych_ha"
# Home Assistant 的安装目录 (虚拟环境将在此处创建)
HA_INSTALL_DIR="/srv/$HA_USER"
# Home Assistant 的配置目录 (通常是 ~/.homeassistant，我们会使用这个)
HA_CONFIG_DIR="/home/$HA_USER/.homeassistant"
# 您的 ha-mirror 仓库的 Git URL
HA_MIRROR_REPO="https://pxy.140407.xyz/https://github.com/yuanzhou029/ha-mirror.git" # <--- **请务必将此替换为您的实际 GitHub 仓库 URL**
# ha-mirror 仓库中包含 Home Assistant 配置文件的子目录名称
HA_MIRROR_CONFIG_SUBDIR="config"

# --- 国内镜像源配置 ---
# PyPI 镜像源 (选择一个稳定且速度快的)
# 推荐使用清华大学或阿里云
PIP_MIRROR_URL="https://repo.huaweicloud.com/repository/pypi/simple" # <--- **您可以选择其他镜像源**

# 这些镜像源可以显著加速 Python 包的下载和安装速度，特别是对于国内用户。

# 清华大学 (Tsinghua University)
# 地址：https://pypi.tuna.tsinghua.edu.cn/simple
# 特点：目前最常用、最稳定、更新速度快的镜像之一。

# 阿里云 (Aliyun)
# 地址：https://mirrors.aliyun.com/pypi/simple/
# 特点：大型云服务商提供，稳定可靠。

# 华为云 (Huawei Cloud)
# 地址：https://repo.huaweicloud.com/repository/pypi/simple/
# 特点：华为云提供的镜像，速度和稳定性良好。

# 中国科学技术大学 (USTC)
# 地址：https://pypi.mirrors.ustc.edu.cn/simple/
# 特点：更新速度快，服务稳定

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

log_info "正在开始 Hass 原生安装和自定义配置部署 (利用国内镜像)..."

# 0. 检查并安装必要工具 (python3-venv, git, build-essential, python3-dev)
log_info "正在检查并安装必要的系统工具 (python3-venv, git, build-essential, python3-dev)..."
REQUIRED_TOOLS=("python3-venv" "git" "build-essential" "python3-dev") # <-- 增加 python3-dev
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

    log_info "当前用户: $(whoami)"
    log_info "当前工作目录: $(pwd)"
    log_info "PATH 环境变量: $PATH"

    # 定义从外部脚本继承的变量 (需要替换)
    HA_INSTALL_DIR_INNER="{{HA_INSTALL_DIR}}"
    HA_CONFIG_DIR_INNER="{{HA_CONFIG_DIR}}"
    HA_MIRROR_REPO_INNER="{{HA_MIRROR_REPO}}"
    HA_MIRROR_CONFIG_SUBDIR_INNER="{{HA_MIRROR_CONFIG_SUBDIR}}"
    PIP_MIRROR_URL_INNER="{{PIP_MIRROR_URL}}"
    GIT_PROXY_INNER="{{GIT_PROXY}}"
    HA_USER_INNER="{{HA_USER}}" # 也需要传递用于 chown

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

    # 3.3 配置 pip 使用国内镜像源
    log_info "正在配置 pip 使用国内镜像源: $PIP_MIRROR_URL_INNER"
    # *** 关键修正：修正 TRUSTED_HOST_INNER 提取方式，只获取域名 ***
    # 使用sed确保只提取域名，例如从 https://repo.huaweicloud.com/repository/pypi/simple 中提取 repo.huaweicloud.com
    TRUSTED_HOST_INNER=$(echo "$PIP_MIRROR_URL_INNER" | sed -E 's/^https?:\/\/([^\/]+).*$/\1/')
    pip config set global.index-url "$PIP_MIRROR_URL_INNER" || log_error "无法设置 pip 镜像源。"
    pip config set global.trusted-host "$TRUSTED_HOST_INNER" || log_error "无法设置 pip trusted-host。"
    log_info "pip 配置完成。修正后的 Trusted Host: $TRUSTED_HOST_INNER"


    # 3.4 安装 Home Assistant
    log_info "正在安装官方 Hass 核心..."
    # 优先安装 setuptools 和 wheel 以确保构建依赖正
    pip install --upgrade setuptools wheel || log_error "无法升级 setuptools/wheel。"
    pip install homeassistant || log_error "无法安装 Home Assistant。请检查网络连接、PyPI 镜像源、Python 开发头文件 (python3-dev) 或编译工具 (build-essential)。"
    log_info "官方 Home Assistant 核心安装成功。"

    # 3.5 验证 hass 脚本是否存在和可执行
    HASS_VENV_PATH_INNER="$HA_INSTALL_DIR_INNER/bin/hass"
    if [ ! -f "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：Home Assistant 的 'hass' 可执行文件未找到于 '$HASS_VENV_PATH_INNER'。Home Assistant 可能安装失败。"
    fi
    if [ ! -x "$HASS_VENV_PATH_INNER" ]; then
        log_error "错误：Home Assistant 的 'hass' 可执行文件在 '$HASS_VENV_PATH_INNER' 没有执行权限。"
    fi
    log_info "'hass' 可执行文件存在并有执行权限: $HASS_VENV_PATH_PATH_INNER" # 小改动，确保HA_INSTALL_DIR_INNER在PATH中

    # 3.6 克隆 ha-mirror 仓库 (用于获取自定义配置)
    log_info "正在克隆或更新 ha-mirror 仓库到 '$HA_INSTALL_DIR_INNER/ha-mirror-repo'..."
    CLONE_URL_INNER="$HA_MIRROR_REPO_INNER"

    if [ -n "$GIT_PROXY_INNER" ]; then
        log_info "正在设置 Git 环境变量代理: $GIT_PROXY_INNER"
        export ALL_PROXY="$GIT_PROXY_INNER"
        export HTTPS_PROXY="$GIT_PROXY_INNER"
        export HTTP_PROXY="$GIT_PROXY_INNER"
    fi

    if [ ! -d "$HA_INSTALL_DIR_INNER/ha-mirror-repo" ]; then
        git clone "$CLONE_URL_INNER" "$HA_INSTALL_DIR_INNER/ha-mirror-repo" || log_error "无法克隆 ha-mirror 仓库。请检查 Git 代理或仓库地址。"
        log_info "ha-mirror 仓库克隆成功。"
    else
        log_info "ha-mirror 仓库已存在，正在执行 'git pull' 更新。"
        cd "$HA_INSTALL_DIR_INNER/ha-mirror-repo"
        git pull || log_error "无法更新 ha-mirror 仓库。请检查 Git 代理或仓库地址。"
        cd "$HA_INSTALL_DIR_INNER" # 返回到虚拟环境的根目录
        log_info "ha-mirror 仓库更新成功。"
    fi

    # 清除 Git 代理环境变量，以免影响后续操作
    unset ALL_PROXY HTTPS_PROXY HTTP_PROXY

    # 3.7 部署自定义配置和组件 (来自 ha-mirror 的 config 目录)
    log_info "正在部署自定义配置和组件到 Home Assistant 配置目录 '$HA_CONFIG_DIR_INNER'..."
    mkdir -p "$HA_CONFIG_DIR_INNER" || log_error "无法创建 Home Assistant 配置目录。"
    
    # 复制 ha-mirror/config 中的内容到 HA_CONFIG_DIR_INNER
    cp -r "$HA_INSTALL_DIR_INNER/ha-mirror-repo/$HA_MIRROR_CONFIG_SUBDIR_INNER"/* "$HA_CONFIG_DIR_INNER/" || log_error "无法复制自定义配置。"
    
    # 确保配置目录的权限正确
    chown -R "$HA_USER_INNER":"$HA_USER_INNER" "$HA_CONFIG_DIR_INNER" || log_error "无法设置配置目录权限。"
    log_info "自定义配置和组件部署成功。"
    
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
