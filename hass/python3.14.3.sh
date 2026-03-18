#!/bin/bash

# 设置颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}开始自动编译安装 Python 3.14.3${NC}"

# 步骤1: 更新系统
echo -e "${YELLOW}步骤1: 更新系统...${NC}"
sudo apt update
sudo apt upgrade -y

# 步骤2: 安装构建工具
echo -e "${YELLOW}步骤2: 安装构建工具...${NC}"
sudo apt install -y build-essential checkinstall

# 步骤3: 安装依赖
echo -e "${YELLOW}步骤3: 安装编译依赖...${NC}"
sudo apt install -y libssl-dev zlib1g-dev libbz2-dev \
libreadline-dev libsqlite3-dev wget curl llvm \
libncurses5-dev libncursesw5-dev libffi-dev \
liblzma-dev tk-dev libgdbm-dev libc6-dev \
libdb-dev libexpat1-dev liblzma-dev zlib1g-dev \
libssl-dev

# 步骤4: 下载 Python 3.14.3 源码
echo -e "${YELLOW}步骤4: 下载 Python 3.14.3 源码...${NC}"
sudo wget https://url.yh-iot.cloudns.org/https://github.com/yuanzhou029/APK/releases/download/3.14.3/Python-3.14.3.tgz

# 步骤5: 解压源码包
echo -e "${YELLOW}步骤5: 解压源码包...${NC}"
sudo tar xzf Python-3.14.3.tgz

# 步骤6: 配置编译选项
echo -e "${YELLOW}步骤6: 配置编译选项...${NC}"
cd Python-3.14.3
sudo ./configure --enable-optimizations

# 步骤7: 开始编译
echo -e "${YELLOW}步骤7: 开始编译 Python (这可能需要较长时间)...${NC}"
sudo make -j $(nproc)

# 步骤8: 安装 Python
echo -e "${YELLOW}步骤8: 安装 Python...${NC}"
sudo make install

# 步骤9: 验证安装
echo -e "${YELLOW}步骤9: 验证 Python 版本...${NC}"
if command -v python3.14 &> /dev/null; then
    echo -e "${GREEN}${BOLD}Python 版本验证成功:${NC}"
    python3.14 --version
else
    echo -e "${RED}Python 3.14.3 安装可能未成功${NC}"
    exit 1
fi

# 步骤10: 更新 pip
echo -e "${YELLOW}步骤10: 更新 pip...${NC}"
python3.14 -m pip install --upgrade pip

echo -e "${GREEN}${BOLD}Python 3.14.3 编译安装完成!${NC}"
echo -e "${GREEN}现在可以使用 python3.14 命令了${NC}"

# 显示安装信息
echo -e "${BLUE}Python 安装路径:${NC}"
which python3.14

echo -e "${BLUE}Pip 版本:${NC}"
python3.14 -m pip --version