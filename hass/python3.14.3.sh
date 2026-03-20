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

# 设置颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'
echo -e "${BLUE}${BOLD}开始自动编译安装 Python 3.14.3${NC}"
# 检测系统类型
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v apk &> /dev/null; then
    PKG_MANAGER="apk"
else
    echo -e "${RED}未找到支持的包管理器${NC}"
    exit 1
fi
echo -e "${YELLOW}检测到包管理器: $PKG_MANAGER${NC}"
# 步骤1: 更新系统
echo -e "${YELLOW}步骤1: 更新系统...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get update
    sudo apt-get upgrade -y
elif [ "$PKG_MANAGER" = "apk" ]; then
    sudo apk update
    sudo apk upgrade
fi
# 步骤2: 安装构建工具
echo -e "${YELLOW}步骤2: 安装构建工具...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get install -y build-essential
elif [ "$PKG_MANAGER" = "apk" ]; then
    sudo apk add build-base
fi
# 步骤3: 安装依赖
echo -e "${YELLOW}步骤3: 安装编译依赖...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get install -y libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev wget curl llvm \
    libncursesw5-dev libffi-dev liblzma-dev tk-dev \
    libgdbm-dev libc6-dev libdb-dev libexpat1-dev \
    libncurses5-dev
elif [ "$PKG_MANAGER" = "apk" ]; then
    sudo apk add openssl-dev zlib-dev bzip2-dev \
    readline-dev sqlite-dev curl llvm \
    ncurses-dev ncurses5-compat-libs ncursesw5-dev libffi-dev \
    xz-dev tk-dev gdbm-dev musl-dev expat-dev
fi
# 步骤4: 下载 Python 3.14.3 源码
echo -e "${YELLOW}步骤4: 下载 Python 3.14.3 源码...${NC}"
rm -f Python-3.14.3.tgz*
sudo wget https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/APK/releases/download/3.14.3/Python-3.14.3.tgz -O Python-3.14.3.tgz
# 步骤5: 解压源码包
echo -e "${YELLOW}步骤5: 解压源码包...${NC}"
rm -rf Python-3.14.3/
tar xzf Python-3.14.3.tgz
# 步骤6: 配置编译选项
echo -e "${YELLOW}步骤6: 配置编译选项...${NC}"
cd Python-3.14.3
./configure --enable-optimizations --with-ensurepip=install
# 步骤7: 开始编译
echo -e "${YELLOW}步骤7: 开始编译 Python (这可能需要较长时间)...${NC}"
make -j $(nproc)
# 步骤8: 安装 Python
echo -e "${YELLOW}步骤8: 安装 Python...${NC}"
sudo make altinstall
# 步骤9: 验证安装
echo -e "${YELLOW}步骤9: 验证 Python 版本...${NC}"
if command -v python3.14 &> /dev/null; then
    echo -e "${GREEN}${BOLD}Python 版本验证成功:${NC}"
    python3.14 --version
elif command -v python3.14.3 &> /dev/null; then
    echo -e "${GREEN}${BOLD}Python 版本验证成功:${NC}"
    python3.14.3 --version
else
    echo -e "${RED}Python 3.14.3 安装可能未成功${NC}"
    # 查找可能的安装位置
    find /usr -name "python3.14*" 2>/dev/null | head -5
    exit 1
fi
# 步骤10: 更新 pip
echo -e "${YELLOW}步骤10: 更新 pip...${NC}"
if command -v python3.14 &> /dev/null; then
    python3.14 -m pip install --upgrade pip
elif command -v python3.14.3 &> /dev/null; then
    python3.14.3 -m pip install --upgrade pip
fi
echo -e "${GREEN}${BOLD}Python 3.14.3 编译安装完成!${NC}"
echo -e "${GREEN}现在可以使用 python3.14 或 python3.14.3 命令了${NC}"
# 显示安装信息
echo -e "${BLUE}Python 安装路径:${NC}"
which python3.14 || which python3.14.3
echo -e "${BLUE}Pip 版本:${NC}"
if command -v python3.14 &> /dev/null; then
    python3.14 -m pip --version
elif command -v python3.14.3 &> /dev/null; then
    python3.14.3 -m pip --version
fi
