#!/bin/bash
# 脚本需要 bash，而不是纯 sh，因为使用了 [[ ]] 和一些 bash 特性

# --- 配置 ---
ROOT_PASSWORD="yz,821009"
HASS_USERNAME="hass"
EXPECT_SCRIPT_COMMON_PATH="/tmp/mcp_exec_expect_script.exp" # 临时 expect 脚本路径

# --- 辅助函数：颜色输出 ---
info_msg() { echo -e "\e[34m[信息]\e[0m $1"; }
success_msg() { echo -e "\e[32m[成功]\e[0m $1"; }
warn_msg() { echo -e "\e[33m[警告]\e[0m $1"; }
error_msg() { echo -e "\e[31m[错误]\e[0m $1"; exit 1; }

# --- 核心函数：以 root 身份执行命令 (使用 expect 自动化) ---
execute_as_root() {
    local cmd="$1"
    local desc="$2"
    info_msg "正在以 root 身份执行: $desc"

    # 生成临时的 expect 脚本
    cat <<EOF > "$EXPECT_SCRIPT_COMMON_PATH"
#!/usr/bin/expect -f
set timeout 10
set root_pass [lindex \$argv 0]

spawn su -
expect {
    "Password:" { send "\$root_pass\\r" }
    timeout { puts "ERROR: su - 命令在密码提示处超时。"; exit 1 }
    eof { puts "ERROR: su - 命令在密码提示处过早退出。"; exit 1 }
}
expect {
    "#" { }
    timeout { puts "ERROR: su - 命令在输入密码后超时。可能是密码错误或遇到意外提示符。"; exit 1 }
    eof { puts "ERROR: su - 命令在输入密码后过早退出。可能是密码错误或遇到意外提示符。"; exit 1 }
}

send "$cmd\\r"
expect {
    "#" { }
    timeout { puts "ERROR: 命令 '$cmd' 执行超时。"; exit 1 }
    eof { puts "ERROR: 命令 '$cmd' 过早退出。"; exit 1 }
}

send "exit\\r"
expect eof
exit 0
EOF
    chmod +x "$EXPECT_SCRIPT_COMMON_PATH"

    # 执行 expect 脚本
    if "$EXPECT_SCRIPT_COMMON_PATH" "$ROOT_PASSWORD"; then
        success_msg "$desc 已完成。"
        rm -f "$EXPECT_SCRIPT_COMMON_PATH" # 删除临时脚本
        return 0
    else
        error_msg "$desc 失败。请检查 root 密码是否正确，或手动执行该命令。"
    fi
}

# --- 检查并安装 expect 工具的函数 ---
check_and_install_expect() {
    if command -v expect >/dev/null 2>&1; then
        info_msg "Expect 已经安装。"
        return 0
    else
        warn_msg "Expect 未安装。为了自动化 root 权限操作，我们需要先安装它。"
        warn_msg "接下来，脚本会尝试使用 'su -c \"apt update && apt install -y expect\"' 来安装 expect。"
        warn_msg "请注意：如果您当前用户没有 sudo 权限，并且 'su' 首次需要密码，您可能需要在此处手动输入一次 root 密码。"

        # 尝试安装 expect。这里的 'su -c' 将会交互式地提示 root 密码
        # 这是唯一的可能需要手动输入的点，用于解决“鸡生蛋”问题
        if su -c "apt update && apt install -y expect"; then
            success_msg "Expect 已成功安装。"
            # 再次验证安装
            if command -v expect >/dev/null 2>&1; then
                return 0
            else
                error_msg "Expect 安装成功，但无法找到 'expect' 命令。请检查您的 PATH 或手动安装。"
            fi
        else
            error_msg "无法自动安装 expect。请手动运行 'su -c \"apt install -y expect\"' 或检查 root 密码。"
        fi
        exit 1 # 如果 expect 安装失败，则退出
    fi
}

# --- 主逻辑 ---
main() {
    info_msg "脚本开始执行。"

    # 1. 检查当前用户是否为 root，如果是，则直接退出，因为本脚本是为了非 root 用户自动化设置 sudo
    if [[ $(id -u) -eq 0 ]]; then
        error_msg "本脚本不应以 root 用户直接运行，它旨在为非 root 用户自动化设置 sudo。请以普通用户 ($HASS_USERNAME) 运行。"
    fi

    # 2. 检查并安装 expect (如果未安装，这里会提示用户手动输入 root 密码)
    check_and_install_expect

    # --- 以下步骤将完全自动化，因为 expect 已经可用 ---

    # 3. 以 root 身份执行：更新包，安装 sudo
    execute_as_root "apt update && apt install -y sudo" "更新包列表并安装 sudo"

    # 4. 以 root 身份执行：将 hass 用户添加到 sudo 组
    execute_as_root "usermod -aG sudo $HASS_USERNAME" "将用户 '$HASS_USERNAME' 添加到 'sudo' 组"

    # 5. 为了使新的组权限生效，我们需要创建一个新的会话。这里我们使用 expect 模拟切换到 hass 用户并执行 newgrp
    # 注意：newgrp 命令在非交互式或 expect 中可能行为不完全符合预期。
    # 更可靠的做法是让用户在脚本完成后重新登录，或使用 su - $HASS_USERNAME 创建一个新会话。
    # 这里为了演示自动化，尝试用 expect 模拟新会话。
    info_msg "尝试激活 '$HASS_USERNAME' 用户的 sudo 权限（可能需要重新登录以完全生效）"
    # 这里不再用 expect 模拟 newgrp，因为它在自动化环境中不总是可靠且可能需要密码。
    # 最直接且可靠的验证是切换到新会话并执行 sudo 命令。
    execute_as_root "echo 'hass 用户已添加到 sudo 组。请切换到 hass 用户并验证。'"

    # 6. 按照要求的顺序执行验证命令
    info_msg "执行验证步骤..."

    # 1. 将root用户切回hass用户执行一个sl命令 (如果sl已安装)
    info_msg "尝试以 '$HASS_USERNAME' 身份执行 'sl' 命令..."
    # 使用 expect 切换到 hass 用户并执行命令
    cat <<EOF > "$EXPECT_SCRIPT_COMMON_PATH"
#!/usr/bin/expect -f
set timeout 10
spawn su - $HASS_USERNAME
expect {
    "Password:" { send "\$root_pass\\r" }
    "$" { } ; # 如果 hass 用户没有密码，直接到 shell 提示符
    timeout { puts "ERROR: su - $HASS_USERNAME 命令超时。"; exit 1 }
    eof { puts "ERROR: su - $HASS_USERNAME 命令过早退出。"; exit 1 }
}
send "sl 2>/dev/null || echo 'sl command not found or failed, continuing...'\r"
expect "$"
send "exit\\r"
expect eof
EOF
    chmod +x "$EXPECT_SCRIPT_COMMON_PATH"
    "$EXPECT_SCRIPT_COMMON_PATH" "$ROOT_PASSWORD" || warn_msg "执行hass用户的sl命令失败或sl未安装。"
    rm -f "$EXPECT_SCRIPT_COMMON_PATH"

    # 2. 将用户切换至root用户执行sudo -l命令
    execute_as_root "sudo -l" "以 root 身份执行 sudo -l"

    # 3. 将用户切回hass并执行sudo -l
    info_msg "尝试以 '$HASS_USERNAME' 身份执行 'sudo -l'..."
    cat <<EOF > "$EXPECT_SCRIPT_COMMON_PATH"
#!/usr/bin/expect -f
set timeout 10
spawn su - $HASS_USERNAME
expect {
    "Password:" { send "\$root_pass\\r" }
    "$" { } ; # 如果 hass 用户没有密码，直接到 shell 提示符
    timeout { puts "ERROR: su - $HASS_USERNAME 命令超时。"; exit 1 }
    eof { puts "ERROR: su - $HASS_USERNAME 命令过早退出。"; exit 1 }
}
send "sudo -l\r"
expect {
    "Password:" { send "$ROOT_PASSWORD\\r" } ; # 如果 sudo -l 提示密码，也尝试输入 root 密码 (假设 hass 密码与 root 相同)
    "$" { }
    timeout { puts "ERROR: sudo -l for hass user timed out."; exit 1 }
    eof { puts "ERROR: sudo -l for hass user exited prematurely."; exit 1 }
}
expect "$"
send "exit\\r"
expect eof
EOF
    chmod +x "$EXPECT_SCRIPT_COMMON_PATH"
    "$EXPECT_SCRIPT_COMMON_PATH" "$ROOT_PASSWORD" || warn_msg "执行hass用户的sudo -l命令失败。"
    rm -f "$EXPECT_SCRIPT_COMMON_PATH"

    # 7. 现在切换回hass用户，进入其根目录并执行其他功能
    info_msg "尝试以 '$HASS_USERNAME' 身份执行 'set_static_ip.sh' (如果存在)..."
    # 这里我们不能直接检查 /home/$HASS_USERNAME/set_static_ip.sh 的存在性，因为当前可能不是 hass 用户
    # 我们可以通过 expect 切换到 hass 用户来检查并执行
    cat <<EOF > "$EXPECT_SCRIPT_COMMON_PATH"
#!/usr/bin/expect -f
set timeout 10
spawn su - $HASS_USERNAME
expect {
    "Password:" { send "\$root_pass\\r" }
    "$" { } ; # 如果 hass 用户没有密码，直接到 shell 提示符
    timeout { puts "ERROR: su - $HASS_USERNAME 命令超时。"; exit 1 }
    eof { puts "ERROR: su - $HASS_USERNAME 命令过早退出。"; exit 1 }
}
send "if [ -f \"/home/$HASS_USERNAME/set_static_ip.sh\" ]; then cd && sudo ./set_static_ip.sh; else echo 'set_static_ip.sh 不存在于hass用户根目录'; fi\r"
expect {
    "Password:" { send "$ROOT_PASSWORD\\r" } ; # 如果 sudo 提示密码，也尝试输入 root 密码
    "$" { }
    timeout { puts "ERROR: set_static_ip.sh execution timed out."; exit 1 }
    eof { puts "ERROR: set_static_ip.sh execution exited prematurely."; exit 1 }
}
expect "$"
send "exit\\r"
expect eof
EOF
    chmod +x "$EXPECT_SCRIPT_COMMON_PATH"
    "$EXPECT_SCRIPT_COMMON_PATH" "$ROOT_PASSWORD" || warn_msg "执行 set_static_ip.sh 失败或不存在。"
    rm -f "$EXPECT_SCRIPT_COMMON_PATH"


    # 8. 删除此脚本
    rm -f "$0"
    success_msg "脚本已自动删除。"
    info_msg "所有步骤完成。建议您重新登录或启动一个新的 shell 会话，以确保所有权限更改完全生效。"
}

# 运行主函数
main
