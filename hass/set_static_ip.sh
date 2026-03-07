#!/bin/bash
# vim: filetype=sh

# ==============================================================================
# 脚本名称: set_static_ip.sh
# 描述: 为 Debian/Ubuntu 系统配置静态 IP 地址。
#       通过修改 /etc/network/interfaces 文件实现。
#       包含健全的错误处理、配置备份、接口预关闭、网络验证和智能IP生成功能。
#       新增Sudo权限管理、dos2unix工具自动安装与脚本格式转换。
# 作者: Gemini Assistant
# 日期: 2023-10-27 (或当前日期)
# 用法: ./set_static_ip.sh [网卡名称]
#       - 如果不指定网卡名称，脚本将尝试自动检测主要网卡。
# 示例: ./set_static_ip.sh          # 自动检测并配置
#       ./set_static_ip.sh ens33    # 为 ens33 网卡配置
# ==============================================================================

# --- 配置常量 ---
CONFIG_FILE="/etc/network/interfaces"
BACKUP_DIR="/etc/network/interfaces.bak"
HASS_USERNAME="hass" # 需要添加到sudo组的用户，如果存在

# --- 带有颜色的输出函数 ---
# 错误信息 (红色)
error_msg() {
    echo -e "\033[0;31mERROR: $1\033[0m" >&2
    exit 1 # 错误时退出脚本
}
# 成功信息 (绿色)
success_msg() {
    echo -e "\033[0;32mSUCCESS: $1\033[0m"
}
# 信息提示 (蓝色)
info_msg() {
    echo -e "\033[0;34mINFO: $1\033[0m"
}
# 警告信息 (黄色)
warning_msg() {
    echo -e "\033[0;33mWARNING: $1\033[0m"
}

# --- 检查当前用户是否为 root ---
check_is_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0 # 是 root
    else
        return 1 # 不是 root
    fi
}

# --- Sudo/Root 权限管理 ---
manage_privileges() {
    if check_is_root; then
        info_msg "脚本已在 root 权限下运行。"
        # 检查并安装 sudo (如果缺失)
        if ! command -v sudo &> /dev/null; then
            warning_msg "'sudo' 命令未找到。尝试安装 'sudo'..."
            if apt update && apt install -y sudo; then
                success_msg "'sudo' 已成功安装。"
            else
                error_msg "安装 'sudo' 失败。请手动检查 APT 仓库或网络连接。"
            fi
        else
            info_msg "'sudo' 命令已存在。"
        fi

        # 将 hass 用户添加到 sudo 组 (如果存在且未添加)
        if id "$HASS_USERNAME" &> /dev/null; then
            info_msg "用户 '$HASS_USERNAME' 存在。"
            if ! groups "$HASS_USERNAME" | grep -q '\bsudo\b'; then
                warning_msg "用户 '$HASS_USERNAME' 未在 'sudo' 组中。尝试添加..."
                if usermod -aG sudo "$HASS_USERNAME"; then
                    success_msg "用户 '$HASS_USERNAME' 已成功添加到 'sudo' 组。"
                    info_msg "请注意：'$HASS_USERNAME' 用户需要重新登录或使用 'newgrp sudo' 才能使新的组权限生效。"
                else
                    warning_msg "将用户 '$HASS_USERNAME' 添加到 'sudo' 组失败。请手动检查。"
                fi
            else
                info_msg "用户 '$HASS_USERNAME' 已在 'sudo' 组中。"
            fi
        else
            warning_msg "用户 '$HASS_USERNAME' 不存在。跳过将其添加到 'sudo' 组的操作。"
        fi
        echo ""
    else
        # 非 root 用户
        if command -v sudo &> /dev/null; then
            # Sudo 命令存在，尝试使用 sudo 重新运行脚本
            info_msg "当前用户不是 root，但 'sudo' 命令可用。"
            if sudo -n true &> /dev/null; then
                # 用户有免密 sudo 权限
                info_msg "正在使用免密 sudo 重新运行脚本..."
                exec sudo "$0" "$@" # 使用 exec 替换当前进程
            else
                # 用户需要输入密码或不在 sudoers 中
                error_msg "此脚本必须以 root 权限运行。\n请使用 'sudo $0' 并输入密码。\n如果您的用户没有 sudo 权限，请联系管理员将其添加到 sudoers 文件，或手动切换到 root 用户 (su -)。"
            fi
        else
            # Sudo 命令不存在且不是 root
            error_msg "此脚本必须以 root 权限运行。\n'sudo' 命令未找到，且当前用户不是 root。\n请手动切换到 root 用户 (su -) 安装 sudo 并将当前用户添加到 sudoers 文件，然后再次尝试运行此脚本。"
        fi
    fi
}

# --- dos2unix 工具管理与脚本格式转换 ---
manage_dos2unix() {
    local script_path="$0"
    info_msg "检查 'dos2unix' 工具..."
    if ! command -v dos2unix &> /dev/null; then
        warning_msg "'dos2unix' 命令未找到。尝试安装 'dos2unix'..."
        if apt update && apt install -y dos2unix; then
            success_msg "'dos2unix' 已成功安装。"
        else
            error_msg "安装 'dos2unix' 失败。请手动检查 APT 仓库或网络连接。"
        fi
    else
        info_msg "'dos2unix' 命令已存在。"
    fi

    # 检查脚本文件格式并转换
    if file -b "$script_path" | grep -q "CRLF"; then
        warning_msg "检测到脚本 '$script_path' 是 Windows (CRLF) 格式。正在尝试转换为 Unix (LF) 格式..."
        if dos2unix "$script_path"; then
            success_msg "脚本 '$script_path' 已成功转换为 Unix (LF) 格式。"
            info_msg "为确保脚本以正确的格式执行，正在重新启动脚本..."
            exec "$script_path" "$@" # 重新执行脚本
        else
            error_msg "脚本 '$script_path' 转换为 Unix 格式失败。请手动检查文件。"
        fi
    else
        info_msg "脚本 '$script_path' 已是 Unix (LF) 格式，无需转换。"
    fi # <--- 修正：这里应该是 fi
    echo ""
}

# --- 获取主要网络接口名称 ---
get_main_interface() {
    # 尝试通过默认路由获取
    local detected_interface=$(ip route | grep default | head -1 | awk '{print $5; exit}')
    if [ -z "$detected_interface" ]; then
        # 如果没有默认路由，尝试获取第一个 UP 的以太网接口
        detected_interface=$(ip -o link show | awk -F': ' '/UP/ {print $2}' | grep -E '^en|^eth' | head -1)
    fi

    if [ -z "$detected_interface" ]; then
        error_msg "无法自动检测主要网络接口。请手动指定网卡名称。例如: $0 ens33"
    fi
    echo "$detected_interface"
}

# --- 获取当前网络配置 ---
get_current_network_config() {
    local interface="$1"
    # 获取IP地址和CIDR
    local ip_info=$(ip -4 addr show dev "$interface" | grep -w inet | awk '{print $2}' | head -1)

    CURRENT_IP=$(echo "$ip_info" | cut -d'/' -f1)
    local cidr=$(echo "$ip_info" | cut -d'/' -f2)
    
    CURRENT_NETMASK="" # 初始化为空

    if [ -n "$cidr" ]; then
        info_msg "尝试从 CIDR /$cidr 计算子网掩码..."
        local python_cmd=""
        if command -v python3 &> /dev/null; then
            python_cmd="python3"
        elif command -v python &> /dev/null; then
            # 检查 'python' 命令是否指向 Python 3
            if [ "$("$python" -V 2>&1 | cut -d' ' -f2 | cut -d'.' -f1)" -ge 3 ]; then
                python_cmd="python"
            else
                warning_msg "检测到 'python' 命令是 Python 2。Python 2 不支持 'ipaddress' 模块或需要单独安装。将跳过 Python 尝试。"
            fi
        fi

        if [ -n "$python_cmd" ]; then
            CURRENT_NETMASK=$("$python_cmd" -c "import ipaddress; print(str(ipaddress.IPv4Network(('0.0.0.0/%s' % '$cidr'), False).netmask))" 2>/dev/null)
            if [ -z "$CURRENT_NETMASK" ]; then 
                warning_msg "使用 '$python_cmd' 尝试计算子网掩码失败（可能缺少 'ipaddress' 模块或环境问题）。尝试 'ipcalc'..."
            else
                success_msg "已使用 '$python_cmd' 成功计算子网掩码。"
            fi
        else
            warning_msg "未找到 'python3' 或兼容的 'python' 命令。无法使用 Python 计算子网掩码。尝试 'ipcalc'..."
        fi

        if [ -z "$CURRENT_NETMASK" ]; then # 如果 Python 尝试失败，尝试 ipcalc
            if command -v ipcalc &> /dev/null; then
                info_msg "使用 'ipcalc' 来确定子网掩码。"
                CURRENT_NETMASK=$(ipcalc -m "$CURRENT_IP/$cidr" | grep -oP '(?<=Netmask:\s)\d+(\.\d+){3}' | head -1)
                if [ -z "$CURRENT_NETMASK" ]; then
                    warning_msg "'ipcalc' 失败或未能确定子网掩码。这可能由于输入不正确或版本问题。"
                else
                    success_msg "已使用 'ipcalc' 成功计算子网掩码。"
                fi
            else
                warning_msg "未能找到 'ipcalc' 命令。无法自动确定子网掩码。请安装 'python3' (及其 'ipaddress' 模块) 或 'ipcalc'。"
            fi
        fi
    fi

    CURRENT_GATEWAY=$(ip route | grep "default via" | awk '{print $3}' | head -1)
    
    local dns_found=""
    if [ -f /etc/resolv.conf ]; then
        # IPv4地址的正则表达式
        local ipv4_regex='(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)'
        # 过滤掉注释和空行，然后提取IPv4 nameserver
        dns_found=$(grep -E "^nameserver\s+$ipv4_regex" /etc/resolv.conf | awk '{print $2}' | head -1)
    fi

    if [ -z "$CURRENT_IP" ]; then
        warning_msg "未能获取 '$interface' 的 IP 地址。"
    fi
    if [ -z "$CURRENT_NETMASK" ]; then
        warning_msg "未能获取 '$interface' 的子网掩码。"
    fi
    if [ -z "$CURRENT_GATEWAY" ]; then
        warning_msg "未能获取 '$interface' 的网关地址。"
    fi
    
    if [ -z "$dns_found" ]; then
        warning_msg "未能获取当前 IPv4 DNS 服务器信息。'/etc/resolv.conf' 可能由 'systemd-resolved' 或 'NetworkManager' 管理，或仅包含 IPv6 DNS。将使用通用默认值: 8.8.8.8 1.1.1.1"
        CURRENT_DNS="8.8.8.8 1.1.1.1"
    else
        CURRENT_DNS="$dns_found"
    fi
}

# --- 主脚本逻辑 ---
main() {
    # 1. Sudo/Root 权限管理 (此函数可能会重新执行脚本)
    manage_privileges

    # 2. dos2unix 工具管理与脚本格式转换 (此函数可能会重新执行脚本)
    #    注意：dos2unix 必须在权限管理之后，因为可能需要 sudo 安装。
    manage_dos2unix

    # 确保现在我们是 root 且脚本格式正确
    if ! check_is_root; then
        error_msg "脚本权限检查失败，无法以 root 身份继续执行。"
    fi

    # 3. 解析命令行参数或自动检测接口
    local INTERFACE
    if [ -n "$1" ]; then
        INTERFACE="$1"
        info_msg "使用用户指定的网卡: '$INTERFACE'"
    else
        info_msg "未指定网卡名称，尝试自动检测主要网卡..."
        INTERFACE=$(get_main_interface)
        success_msg "已自动检测到主要网卡: '$INTERFACE'"
    fi
    echo ""

    # 4. 验证网卡是否存在
    info_msg "验证网卡 '$INTERFACE'..."
    if ! ip link show "$INTERFACE" &> /dev/null; then
        error_msg "网卡 '$INTERFACE' 未找到。请检查网卡名称是否正确。\n当前系统网卡列表:\n$(ip link show)"
    fi
    success_msg "网卡 '$INTERFACE' 存在。"
    echo ""

    # 5. 获取当前网络配置
    info_msg "正在获取网卡 '$INTERFACE' 的当前网络配置..."
    get_current_network_config "$INTERFACE"
    echo "--- 当前网络配置 ($INTERFACE) ---"
    echo "IP 地址:     ${CURRENT_IP:-未知}"
    echo "子网掩码:    ${CURRENT_NETMASK:-未知}"
    echo "网关:        ${CURRENT_GATEWAY:-未知}"
    echo "DNS 服务器:  ${CURRENT_DNS:-未知}"
    echo "-----------------------------------"
    echo ""

    if [ -z "$CURRENT_IP" ] || [ -z "$CURRENT_NETMASK" ] || [ -z "$CURRENT_GATEWAY" ]; then
        local error_detail=""
        if [ -z "$CURRENT_IP" ]; then error_detail+="IP 地址 "; fi
        if [ -z "$CURRENT_NETMASK" ]; then error_detail+="子网掩码 "; fi
        if [ -z "$CURRENT_GATEWAY" ]; then error_detail+="网关 "; fi
        error_msg "无法自动获取当前完整的网络配置。缺少以下信息：$error_detail。\n请确保网卡 '$INTERFACE' 已连接且具有 IP 地址，且系统已安装 'python3' (及其 'ipaddress' 模块) 或 'ipcalc' 来计算子网掩码。如果问题依旧，请手动检查网络配置。"
    fi

    # 6. 生成新的静态 IP 配置
    info_msg "正在根据当前配置智能生成新的静态 IP 地址 (将IP末位设置为.254)..."
    local NEW_STATIC_IP=$(echo "$CURRENT_IP" | awk -F'.' '{print $1"."$2"."$3".254"}')
    local NEW_NETMASK="$CURRENT_NETMASK"
    local NEW_GATEWAY="$CURRENT_GATEWAY"
    #local NEW_DNS="$CURRENT_DNS"
    local NEW_DNS="218.30.19.40 61.134.1.4"


    echo "--- 将要配置的静态 IP 信息 ($INTERFACE) ---"
    echo "新 IP 地址:    $NEW_STATIC_IP"
    echo "子网掩码:     $NEW_NETMASK"
    echo "网关:         $NEW_GATEWAY"
    echo "DNS 服务器:   $NEW_DNS"
    echo "------------------------------------------"
    echo ""

    # 7. 备份现有网络配置
    info_msg "尝试备份现有配置..."
    mkdir -p "$BACKUP_DIR" || warning_msg "无法创建备份目录 '$BACKUP_DIR'。将跳过备份。"
    local BACKUP_FILE="${BACKUP_DIR}/interfaces_$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        success_msg "现有配置已备份到 $BACKUP_FILE"
    else
        warning_msg "备份 '$CONFIG_FILE' 失败。将继续操作，但建议您手动保存配置以防万一。"
    fi
    echo ""

    # 8. 预先关闭网卡以避免 "Address already assigned" 错误
    info_msg "正在关闭网卡 '$INTERFACE' 以避免 '地址已被分配' 错误..."
    if command -v ifdown &> /dev/null; then
        if ! ifdown "$INTERFACE" 2>/dev/null; then
            warning_msg "'ifdown $INTERFACE' 失败 (可能网卡未通过 /etc/network/interfaces 配置或已关闭)。尝试使用 'ip link set down'..."
            if ! ip link set "$INTERFACE" down 2>/dev/null; then
                warning_msg "无法使用 'ip link set down' 关闭网卡 '$INTERFACE'。如果它已经关闭或由其他服务管理，则可能没有问题。"
            else
                success_msg "已使用 'ip link set down' 成功关闭网卡 '$INTERFACE'。"
            fi
        else
            success_msg "已使用 'ifdown' 成功关闭网卡 '$INTERFACE'。"
        fi
    else
        warning_msg "未找到 'ifdown' 命令。尝试使用 'ip link set down'。"
        if ! ip link set "$INTERFACE" down 2>/dev/null; then
            warning_msg "无法使用 'ip link set down' 关闭网卡 '$INTERFACE'。如果它已经关闭或由其他服务管理，则可能没有问题。"
        else
            success_msg "已使用 'ip link set down' 成功关闭网卡 '$INTERFACE'。"
        fi
    fi
    echo ""

    # 9. 生成并应用新的配置
    info_msg "正在生成并应用新的静态 IP 配置到 '$CONFIG_FILE'..."
    local TEMP_CONFIG_FILE=$(mktemp) || error_msg "无法创建临时文件。"

    cat << EOF > "$TEMP_CONFIG_FILE"
# 此文件描述了系统上可用的网络接口
# 以及如何激活它们。更多信息，请参阅 interfaces(5)。

# 回环网络接口
auto lo
iface lo inet loopback

# 主网络接口 - 由 $(basename "$0") 在 $(date) 配置
auto $INTERFACE
iface $INTERFACE inet static
    address $NEW_STATIC_IP
    netmask $NEW_NETMASK
    gateway $NEW_GATEWAY
    dns-nameservers $NEW_DNS
EOF

    # 原子性更新配置文件
    mv "$TEMP_CONFIG_FILE" "$CONFIG_FILE" || error_msg "无法将新配置写入 '$CONFIG_FILE'。"
    success_msg "新配置已写入 '$CONFIG_FILE'。"
    echo "新配置文件内容:"
    cat "$CONFIG_FILE"
    echo ""

    # 10. 启用并重启网络服务
    info_msg "确保 'networking.service' 服务已启用以随系统启动..."
    systemctl enable networking || warning_msg "无法启用 networking 服务随系统启动。它可能被屏蔽或有其他首选服务。"

    info_msg "正在重启网络服务 'networking.service'..."
    if ! systemctl restart networking; then
        error_msg "重启网络服务失败。\n请检查详细日志: 'sudo systemctl status networking.service' 和 'journalctl -xeu networking.service'"
    fi
    success_msg "网络服务已成功重启。"
    echo ""

    # 11. 网络配置验证
    info_msg "正在验证网络配置..."
    sleep 3 # 给网络一些时间来完全启动

    local IP_ADDR_CHECK=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    local ROUTE_GATEWAY_CHECK=$(ip r | grep "default via" | awk '{print $3}' | head -1)
    local DNS_RESOLV_CHECK=$(grep -E '^nameserver' /etc/resolv.conf | awk '{print $2}' | xargs)

    echo "--- 网卡 '$INTERFACE' 当前网络状态 ---"
    echo "预期 IP 地址: $NEW_STATIC_IP"
    echo "实际 IP 地址:   $IP_ADDR_CHECK"
    echo "预期 网关:    $NEW_GATEWAY"
    echo "实际 网关:      $ROUTE_GATEWAY_CHECK"
    echo "预期 DNS:     $NEW_DNS"
    echo "实际 DNS (/etc/resolv.conf): $DNS_RESOLV_CHECK"
    echo "------------------------------------"

    local validation_successful=true
    if [[ "$IP_ADDR_CHECK" != "$NEW_STATIC_IP" ]]; then
        warning_msg "IP 地址验证失败！实际 IP ($IP_ADDR_CHECK) 与预期 IP ($NEW_STATIC_IP) 不匹配。"
        validation_successful=false
    else
        success_msg "IP 地址验证成功。"
    fi

    if [[ "$ROUTE_GATEWAY_CHECK" != "$NEW_GATEWAY" ]]; then
        warning_msg "网关验证失败！实际网关 ($ROUTE_GATEWAY_CHECK) 与预期网关 ($NEW_GATEWAY) 不匹配。"
        validation_successful=false
    else
        success_msg "网关验证成功。"
    fi

    # 检查 DNS (只需验证第一个预期的DNS服务器是否存在于实际列表中)
    local first_dns_expected=$(echo "$NEW_DNS" | awk '{print $1}')
    if [ -n "$first_dns_expected" ] && ! echo "$DNS_RESOLV_CHECK" | grep -q "$first_dns_expected"; then
        warning_msg "预期 DNS 服务器 '$first_dns_expected' 未在 /etc/resolv.conf 中找到。这可能由 'systemd-resolved' 或 'NetworkManager' 等其他服务管理，并非直接由 interfaces 文件控制，但请确保网络工作正常。"
    else
        success_msg "DNS 服务器验证成功 (或由其他服务管理，但已检测到)。"
    fi

    if "$validation_successful"; then
        success_msg "静态 IP 配置已成功应用和验证！"
        echo ""
        info_msg "尝试 ping baidu.com 测试互联网连通性..."
        if ping -c 4 baidu.com &> /dev/null; then
            success_msg "Ping baidu.com 成功。互联网连通性确认。"
            exit 0
        else
            warning_msg "Ping baidu.com 失败。互联网连通性可能仍有问题。请检查防火墙规则或路由器设置。"
            exit 1 # 连通性失败，但也算部分成功，不应该直接 error_msg
        fi
    else
        error_msg "最终网络配置验证失败。请检查上述输出和相关日志。"
    fi
}

# 运行主函数
main "$@"
