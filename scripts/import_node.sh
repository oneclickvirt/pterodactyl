#!/bin/bash
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.15

myvar=$(pwd)
PANEL_DIR="/var/www/pterodactyl"
USER_FILE="$PANEL_DIR/auto_users.txt"
COOKIES_FILE="/tmp/pterodactyl_cookies.txt"

# 全局变量，用于存储函数返回值
G_IPV4=""
G_PANEL_URL=""
G_ADMIN_EMAIL=""
G_ADMIN_PASSWORD=""
G_CSRF_TOKEN=""
G_NODE_ID=""
G_INSTALL_TOKEN=""
G_ADMIN_KEY=""

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
    IFS='.' read -r -a ip_parts <<<"$ip"
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
            G_IPV4="$output"
            return 0
        fi
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
        if ip=$(curl -s --connect-timeout 8 "$api_url"); then
            if [ -n "$ip" ] && ! echo "$ip" | grep -i "error" >/dev/null; then
                G_IPV4="$ip"
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}

read_panel_config() {
    if [ ! -f "$USER_FILE" ]; then
        return 1
    fi
    local panel_ip=""
    G_PANEL_URL=""
    G_ADMIN_EMAIL=""
    G_ADMIN_PASSWORD=""
    while IFS= read -r line; do
        if [[ "$line" == *登录页面* ]]; then
            panel_ip=$(echo "$line" | sed -n 's#.*http://\([^/:]*\).*#\1#p')
            G_PANEL_URL="http://$panel_ip"
        elif [[ "$line" == *用户名* ]]; then
            G_ADMIN_EMAIL=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//')
        elif [[ "$line" == *密码* ]]; then
            G_ADMIN_PASSWORD=$(echo "$line" | cut -d':' -f2- | sed 's/^ *//')
        fi
    done <"$USER_FILE"
    G_PANEL_URL=$(echo "$G_PANEL_URL" | xargs)
    G_ADMIN_EMAIL=$(echo "$G_ADMIN_EMAIL" | xargs)
    G_ADMIN_PASSWORD=$(echo "$G_ADMIN_PASSWORD" | xargs)
    if [ -z "$G_PANEL_URL" ] || [ -z "$G_ADMIN_EMAIL" ] || [ -z "$G_ADMIN_PASSWORD" ]; then
        return 1
    fi
    G_PANEL_URL=${G_PANEL_URL%/}
    return 0
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
    sleep 1
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
    sleep 1
    admin_check_status=$(curl -s -o /dev/null -w "%{http_code}" -c "$COOKIES_FILE" -b "$COOKIES_FILE" "$panel_url/admin")
    sleep 1
    echo "$panel_url/admin 登录响应状态码：$admin_check_status"
    echo "登录响应文本：${login_response:0:200}"
    if ! echo "$login_response" | grep -q '"complete":true'; then
        echo "错误：面板登录失败，请检查用户名和密码是否正确！"
        return 1
    fi
    local updated_token
    updated_token=$(grep -oP 'XSRF-TOKEN\s+\K[^\s]+' "$COOKIES_FILE" | sed 's/%3D/=/g' | sed 's/%3d/=/g')
    updated_token=$(echo "$updated_token" | sed -e 's/%\([0-9A-F][0-9A-F]\)/\\\\\\x\1/g' | xargs -0 printf "%b")
    echo "登录成功，获取到CSRF Token: $updated_token"
    G_CSRF_TOKEN="$updated_token"
    return 0
}

get_latest_node_id() {
    local result
    result=$(php /var/www/pterodactyl/artisan p:node:list --format=json 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$result" ]; then
        G_NODE_ID="1"
        return 0
    fi
    local latest_node_id
    latest_node_id=$(echo "$result" | jq '.[-1].id')
    if [ -n "$latest_node_id" ]; then
        G_NODE_ID="$latest_node_id"
    else
        G_NODE_ID="1"
    fi
    return 0
}

generate_admin_api_key() {
    local panel_url=$1
    local api_page_url="$panel_url/admin/api"
    local key_file="AdminKey.txt"
    if [ -s "$key_file" ]; then
        echo "API 密钥已存在于 $key_file，跳过生成。"
        G_ADMIN_KEY=$(cat "$key_file")
        return 0
    fi
    echo "正在获取API页面的CSRF令牌..."
    local api_page_content
    sleep 1
    api_page_content=$(curl -s -b "$COOKIES_FILE" "$api_page_url")
    if [ $? -ne 0 ] || [ -z "$api_page_content" ]; then
        echo "获取API页面失败"
        return 1
    fi
    local api_csrf_token
    api_csrf_token=$(echo "$api_page_content" | grep -oP '<meta name="_token" content="\K[^"]+')
    if [ -z "$api_csrf_token" ]; then
        echo "无法获取API页面的CSRF令牌"
        return 1
    fi
    echo "获取到API页面CSRF令牌: $api_csrf_token"
    echo "正在创建新的API密钥..."
    local create_api_response
    sleep 1
    create_api_response=$(curl -s -b "$COOKIES_FILE" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Origin: $panel_url" \
        -H "Referer: $panel_url/admin/api/new" \
        -X POST \
        --data-raw "r_allocations=3&r_database_hosts=3&r_eggs=3&r_locations=3&r_nests=3&r_nodes=3&r_server_databases=3&r_servers=3&r_users=3&memo=AdminKey&_token=$api_csrf_token" \
        "$panel_url/admin/api/new")
    if [ $? -ne 0 ] || [ -z "$create_api_response" ]; then
        echo "创建API密钥请求失败"
        return 1
    fi
    sleep 3
    local admin_key
    api_page_content=$(curl -s -b "$COOKIES_FILE" "$api_page_url")
    if [ $? -ne 0 ] || [ -z "$api_page_content" ]; then
        echo "重新获取API页面失败"
        return 1
    fi
    admin_key=$(echo "$api_page_content" | tr -d '\n' | grep -oP '<td><code>(ptla_[^<]+)</code></td>\s*<td>AdminKey</td>' | grep -oP 'ptla_[^<]+')
    if [ -z "$admin_key" ]; then
        echo "无法从响应中提取API密钥"
        return 1
    fi
    G_ADMIN_KEY="ptla_$admin_key"
    echo "成功创建API密钥: $G_ADMIN_KEY"
    echo "$G_ADMIN_KEY" > "$key_file"
    return 0
}

generate_install_token() {
    local panel_url=$1
    local node_id=$2
    local config_url="$panel_url/admin/nodes/view/$node_id/configuration"
    local html_content
    sleep 1
    html_content=$(curl -s -b "$COOKIES_FILE" "$config_url")
    if [ $? -ne 0 ] || [ -z "$html_content" ]; then
        return 1
    fi
    local csrf_token
    csrf_token=$(echo "$html_content" | grep -oP '<meta name="_token" content="\K[^"]+')
    if [ -z "$csrf_token" ]; then
        return 1
    fi
    local token_url="$panel_url/admin/nodes/view/$node_id/settings/token"
    local token_response
    sleep 1
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
        return 1
    fi
    local install_token
    install_token=$(echo "$token_response" | grep -oP '"token":"\K[^"]+')
    if [ -z "$install_token" ]; then
        return 1
    fi
    G_INSTALL_TOKEN="$install_token"
    return 0
}

show_wings_install_command() {
    cd $myvar >/dev/null 2>&1
    local panel_url=$1
    local install_token=$2
    local node_id=$3
    local cmd="(cd /etc/pterodactyl && sudo wings configure --panel-url \"$panel_url\" --token \"$install_token\" --node \"$node_id\")"
    echo -e "在wings端一键导入配置的命令[带英文括号]，同时该命令保存在当前路径下的 wings_cmd.txt 文件中避免遗忘："
    echo "$cmd"
    echo "$cmd" >> ./wings_cmd.txt
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
    if ! get_ipv4; then
        echo "无法获取IPv4地址，脚本中断"
        exit 1
    fi
    if ! create_node "$node_name" "$node_memory" "$node_over_memory" "$node_disk" "$node_over_disk" "$G_IPV4"; then
        echo "节点创建失败，脚本中断"
        exit 1
    fi
    echo "读取面板配置..."
    if ! read_panel_config; then
        echo "无法获取面板配置，脚本中断"
        exit 1
    fi
    echo "面板地址: $G_PANEL_URL"
    echo "管理员邮箱: $G_ADMIN_EMAIL"
    echo "管理员密码: ${G_ADMIN_PASSWORD:0:3}****"
    if ! login_panel "$G_PANEL_URL" "$G_ADMIN_EMAIL" "$G_ADMIN_PASSWORD"; then
        echo "面板登录失败，脚本中断"
        exit 1
    fi
    generate_admin_api_key "$G_PANEL_URL"
    get_latest_node_id
    echo "将使用节点ID: $G_NODE_ID"
    echo -n "请确认节点ID [默认: $G_NODE_ID]: "
    read -r input_node_id
    if [ -n "$input_node_id" ]; then
        if [[ "$input_node_id" =~ ^[0-9]+$ ]]; then
            G_NODE_ID=$input_node_id
        else
            echo "输入无效，将使用默认节点ID: $G_NODE_ID"
        fi
    fi
    if ! generate_install_token "$G_PANEL_URL" "$G_NODE_ID"; then
        echo "安装令牌生成失败，脚本中断"
        exit 1
    fi
    show_wings_install_command "$G_PANEL_URL" "$G_INSTALL_TOKEN" "$G_NODE_ID"
}

main
