#!/bin/bash
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.15

PANEL_DIR="/var/www/pterodactyl"
USER_FILE="$PANEL_DIR/auto_users.txt"
COOKIES_FILE="/tmp/pterodactyl_cookies.txt"

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误：脚本必须以root权限运行！"
        exit 1
    fi
}

is_private_ipv4() {
    local ip=$1
    if [ -z "$ip" ]; then
        return 0
    fi
    if ! echo "$ip" | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' >/dev/null; then
        return 0
    fi
    IFS='.' read -r -a ip_parts <<< "$ip"
    # 10.0.0.0/8
    if [ "${ip_parts[0]}" -eq 10 ]; then
        return 0
    fi
    # 172.16.0.0/12
    if [ "${ip_parts[0]}" -eq 172 ] && [ "${ip_parts[1]}" -ge 16 ] && [ "${ip_parts[1]}" -le 31 ]; then
        return 0
    fi
    # 192.168.0.0/16
    if [ "${ip_parts[0]}" -eq 192 ] && [ "${ip_parts[1]}" -eq 168 ]; then
        return 0
    fi
    # 127.0.0.0/8
    if [ "${ip_parts[0]}" -eq 127 ]; then
        return 0
    fi
    # 169.254.0.0/16
    if [ "${ip_parts[0]}" -eq 169 ] && [ "${ip_parts[1]}" -eq 254 ]; then
        return 0
    fi
    # 224.0.0.0/4
    if [ "${ip_parts[0]}" -ge 224 ] && [ "${ip_parts[0]}" -le 239 ]; then
        return 0
    fi
    # 0.0.0.0
    if [ "${ip_parts[0]}" -eq 0 ] && [ "${ip_parts[1]}" -eq 0 ] && [ "${ip_parts[2]}" -eq 0 ] && [ "${ip_parts[3]}" -eq 0 ]; then
        return 0
    fi
    # RFC 6598 (100.64.0.0/10)
    if [ "${ip_parts[0]}" -eq 100 ] && [ "${ip_parts[1]}" -ge 64 ] && [ "${ip_parts[1]}" -le 127 ]; then
        return 0
    fi
    return 1
}

get_ipv4() {
    local output
    output=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)
    if [ -n "$output" ]; then
        if ! is_private_ipv4 "$output"; then
            echo "检测到公网IPv4地址: $output"
            echo "$output"
            return
        else
            echo "检测到内网IPv4地址: $output，将尝试通过API获取公网IP"
        fi
    else
        echo "无法获取本机IPv4地址，将尝试通过API获取"
    fi
    local api_list=(
        "https://ipv4.ip.sb" 
        "https://ipget.net"
        "https://ip.ping0.cc"
        "https://ip4.seeip.org"
        "https://api.my-ip.io/ip"
        "https://ipv4.icanhazip.com"
        "https://api.ipify.org"
    )
    for api_url in "${api_list[@]}"; do
        echo "尝试通过 $api_url 获取公网IP..."
        if ip=$(curl -s --connect-timeout 8 "$api_url"); then
            if [ -n "$ip" ] && ! echo "$ip" | grep -i "error" >/dev/null; then
                echo "成功获取到公网IP: $ip (通过 $api_url)"
                echo "$ip"
                return
            fi
        fi
        sleep 1
    done
    echo "警告：无法获取公网IP地址，请手动设置"
    echo "127.0.0.1"
}

read_panel_config() {
    if [ ! -f "$USER_FILE" ]; then
        exit 1
    fi
    local panel_url=""
    local admin_email=""
    local admin_password=""
    while IFS= read -r line; do
        if [[ "$line" == *登录页面* ]]; then
            panel_ip=$(echo "$line" | sed -n 's#.*http://\([^/:]*\).*#\1#p')
            panel_url="http://$panel_ip"
        elif [[ "$line" == *用户名* ]]; then
            admin_email=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//')
        elif [[ "$line" == *密码* ]]; then
            admin_password=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//')
        fi
    done < "$USER_FILE"
    panel_url=$(echo "$panel_url" | xargs)
    admin_email=$(echo "$admin_email" | xargs)
    admin_password=$(echo "$admin_password" | xargs)
    if [ -z "$panel_url" ] || [ -z "$admin_email" ] || [ -z "$admin_password" ]; then
        exit 1
    fi
    panel_url=${panel_url%/}
    echo "$panel_url|$admin_email|$admin_password"
}

create_node() {
    local node_name=$1
    local node_memory=$2
    local node_over_memory=$3
    local node_disk=$4
    local node_over_disk=$5
    local ipv4=$6
    echo "开始创建节点: $node_name"
    echo "节点IP地址: $ipv4"
    echo "节点配置: 内存=${node_memory}MB(超分配${node_over_memory}%) 磁盘=${node_disk}MB(超分配${node_over_disk}%)"
    cd "$PANEL_DIR" || exit 1
    if ! php artisan p:node:make \
        "--name=$node_name" \
        "--description=Auto Generate" \
        "--locationId=1" \
        "--fqdn=$ipv4" \
        "--public=1" \
        "--scheme=http" \
        "--proxy=0" \
        "--maintenance=0" \
        "--maxMemory=$node_memory" \
        "--overallocateMemory=$node_over_memory" \
        "--maxDisk=$node_disk" \
        "--overallocateDisk=$node_over_disk" \
        "--uploadSize=1024" \
        "--daemonListeningPort=8080" \
        "--daemonSFTPPort=2022" \
        "--daemonBase=/var/lib/pterodactyl" \
        "--no-interaction"; then
        echo "错误：节点创建失败"
        return 1
    fi
    echo "节点创建成功！"
    return 0
}

login_panel() {
    local panel_url=$1
    local admin_email=$2
    local admin_password=$3
    echo "正在登录Pterodactyl面板: $panel_url"
    rm -f "$COOKIES_FILE" 2>/dev/null
    local csrf_response
    csrf_response=$(curl -s -c "$COOKIES_FILE" -b "$COOKIES_FILE" "$panel_url/sanctum/csrf-cookie")
    local xsrf_token
    xsrf_token=$(grep -oP 'XSRF-TOKEN\s+\K[^\s]+' "$COOKIES_FILE" | sed 's/%3D/=/g' | sed 's/%3d/=/g')
    if [ -z "$xsrf_token" ]; then
        echo "获取不到XSRF-TOKEN"
        return 1
    fi
    xsrf_token=$(echo "$xsrf_token" | sed -e 's/%\([0-9A-F][0-9A-F]\)/\\\\\\x\1/g' | xargs -0 printf "%b")
    echo "解码后的XSRF-TOKEN: $xsrf_token"
    local login_data="{\"user\":\"$admin_email\",\"password\":\"$admin_password\",\"g-recaptcha-response\":\"\"}"
    local login_response
    login_response=$(curl -s -c "$COOKIES_FILE" -b "$COOKIES_FILE" \
        -H "Content-Type: application/json" \
        -H "X-XSRF-TOKEN: $xsrf_token" \
        -H "Referer: $panel_url/auth/login" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "Accept: application/json" \
        -d "$login_data" \
        "$panel_url/auth/login")
    local admin_check_status
    admin_check_status=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIES_FILE" -b "$COOKIES_FILE" "$panel_url/admin")
    echo "$panel_url/admin 登录响应状态码：$admin_check_status"
    # echo "登录响应文本：${login_response:0:200}"
    if ! echo "$login_response" | grep -q '"complete":true'; then
        echo "错误：面板登录失败，请检查用户名和密码是否正确！"
        return 1
    fi
    local updated_token
    updated_token=$(grep -oP 'XSRF-TOKEN\s+\K[^\s]+' "$COOKIES_FILE" | sed 's/%3D/=/g' | sed 's/%3d/=/g')
    updated_token=$(echo "$updated_token" | sed -e 's/%\([0-9A-F][0-9A-F]\)/\\\\\\x\1/g' | xargs -0 printf "%b")
    echo "登录成功，获取到CSRF Token: $updated_token"
    echo "$updated_token"
    return 0
}

get_latest_node_id() {
    echo "获取最新创建的节点ID..."
    local result
    result=$(php /var/www/pterodactyl/artisan p:node:list --format=json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        echo "执行 PHP 命令时出错或结果为空"
        echo "1"
        return
    fi
    local latest_node_id
    latest_node_id=$(echo "$result" | jq '.[-1].id')
    if [ -n "$latest_node_id" ]; then
        echo "获取到最新节点ID: $latest_node_id"
        echo "$latest_node_id"
    else
        echo "警告：无法获取最新节点ID，将使用默认值1"
        echo "1"
    fi
}

generate_install_token() {
    local panel_url=$1
    local panel_email=$2
    local panel_password=$3
    local node_id=$4
    echo "正在为节点ID $node_id 生成安装令牌..."
    local config_url="$panel_url/admin/nodes/view/$node_id/configuration"
    echo "获取配置页面: $config_url"
    local html_content
    html_content=$(curl -s -b "$COOKIES_FILE" "$config_url")
    if [ $? -ne 0 ] || [ -z "$html_content" ]; then
        echo "获取配置页面失败"
        return 1
    fi
    local csrf_token
    csrf_token=$(echo "$html_content" | grep -oP '<meta name="_token" content="\K[^"]+')
    if [ -z "$csrf_token" ]; then
        echo "无法从页面中解析CSRF Token"
        return 1
    fi
    echo "从HTML中解析到的CSRF Token: $csrf_token"
    local token_url="$panel_url/admin/nodes/view/$node_id/settings/token"
    echo "请求生成令牌URL: $token_url"
    local token_response
    token_response=$(curl -s -b "$COOKIES_FILE" \
        -H "X-CSRF-TOKEN: $csrf_token" \
        -H "Accept: */*" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36" \
        -H "Origin: $panel_url" \
        -H "Referer: $panel_url/admin/nodes/view/$node_id/configuration" \
        -X POST \
        "$token_url")
    if [ $? -ne 0 ] || [ -z "$token_response" ]; then
        echo "错误：请求失败"
        echo "响应内容: $token_response"
        return 1
    fi
    local install_token
    install_token=$(echo "$token_response" | grep -oP '"token":"\K[^"]+')
    if [ -z "$install_token" ]; then
        echo "错误：生成安装令牌失败！响应内容: $token_response"
        return 1
    fi
    echo "安装令牌生成成功"
    echo "$install_token"
}

show_wings_install_command() {
    local panel_url=$1
    local install_token=$2
    local node_id=$3
    echo -e "\n一键导入命令：\n"
    echo "cd /etc/pterodactyl && sudo wings configure --panel-url $panel_url --token $install_token --node $node_id"
}

main() {
    check_root
    echo -n "请输入节点名称 [默认: auto-node]: "
    read -r node_name
    node_name=${node_name:-auto-node}
    echo -n "请输入节点内存 (MB) [默认: 1024]: "
    read -r node_memory
    node_memory=${node_memory:-1024}
    if ! [[ "$node_memory" =~ ^[0-9]+$ ]]; then
        echo "输入必须是数字，将使用默认值"
        node_memory=1024
    fi
    echo -n "请输入内存超分配百分比 [默认: 0]: "
    read -r node_over_memory
    node_over_memory=${node_over_memory:-0}
    if ! [[ "$node_over_memory" =~ ^[0-9]+$ ]]; then
        echo "输入必须是数字，将使用默认值"
        node_over_memory=0
    fi
    echo -n "请输入节点磁盘 (MB) [默认: 10240]: "
    read -r node_disk
    node_disk=${node_disk:-10240}
    if ! [[ "$node_disk" =~ ^[0-9]+$ ]]; then
        echo "输入必须是数字，将使用默认值"
        node_disk=10240
    fi
    echo -n "请输入磁盘超分配百分比 [默认: 0]: "
    read -r node_over_disk
    node_over_disk=${node_over_disk:-0}
    if ! [[ "$node_over_disk" =~ ^[0-9]+$ ]]; then
        echo "输入必须是数字，将使用默认值"
        node_over_disk=0
    fi
    ipv4=$(get_ipv4)
    if ! create_node "$node_name" "$node_memory" "$node_over_memory" "$node_disk" "$node_over_disk" "$ipv4"; then
        echo "节点创建失败，脚本中断"
        exit 1
    fi
    echo "读取面板配置..."
    panel_config=$(read_panel_config)
    if [ -z "$panel_config" ]; then
        echo "无法获取面板配置，脚本中断"
        exit 1
    fi
    panel_url=$(echo "$panel_config" | cut -d'|' -f1)
    admin_email=$(echo "$panel_config" | cut -d'|' -f2)
    admin_password=$(echo "$panel_config" | cut -d'|' -f3)
    echo "面板地址: $panel_url"
    echo "管理员邮箱: $admin_email"
    echo "管理员密码: ${admin_password:0:3}****"
    csrf_token=$(login_panel "$panel_url" "$admin_email" "$admin_password")
    if [ $? -ne 0 ] || [ -z "$csrf_token" ]; then
        echo "面板登录失败，脚本中断"
        exit 1
    fi
    node_id=$(get_latest_node_id)
    echo "将使用节点ID: $node_id"
    echo -n "请确认节点ID [默认: $node_id]: "
    read -r input_node_id
    if [ -n "$input_node_id" ]; then
        if [[ "$input_node_id" =~ ^[0-9]+$ ]]; then
            node_id=$input_node_id
        else
            echo "输入无效，将使用默认节点ID: $node_id"
        fi
    fi
    install_token=$(generate_install_token "$panel_url" "$admin_email" "$admin_password" "$node_id")
    if [ $? -ne 0 ] || [ -z "$install_token" ]; then
        echo "安装令牌生成失败，脚本中断"
        exit 1
    fi
    show_wings_install_command "$panel_url" "$install_token" "$node_id"
}

main
