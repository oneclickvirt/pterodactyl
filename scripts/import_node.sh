#!/bin/bash
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.14

# 全局变量定义
PANEL_DIR="/var/www/pterodactyl"
USER_FILE="$PANEL_DIR/auto_users.txt"
COOKIES_FILE="/tmp/pterodactyl_cookies.txt"

# 检查是否有root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误：脚本必须以root权限运行！"
        exit 1
    fi
}

# URL 解码函数
url_decode() {
    local input="${1//+/ }"   # 将加号替换为空格
    echo -e "${input//%/\\x}" # 解析百分号编码
}

# 检查IP是否为私有IPv4
is_private_ipv4() {
    local ip_address=$1
    local ip_parts
    if [[ -z $ip_address ]]; then
        return 0 # 输入为空
    fi
    IFS='.' read -r -a ip_parts <<<"$ip_address"
    # 检查IP地址是否符合内网IP地址的范围
    # 去除回环，RFC 1918，多播，RFC 6598地址
    if [[ ${ip_parts[0]} -eq 10 ]] ||
        [[ ${ip_parts[0]} -eq 172 && ${ip_parts[1]} -ge 16 && ${ip_parts[1]} -le 31 ]] ||
        [[ ${ip_parts[0]} -eq 192 && ${ip_parts[1]} -eq 168 ]] ||
        [[ ${ip_parts[0]} -eq 127 ]] ||
        [[ ${ip_parts[0]} -eq 0 ]] ||
        [[ ${ip_parts[0]} -eq 100 && ${ip_parts[1]} -ge 64 && ${ip_parts[1]} -le 127 ]] ||
        [[ ${ip_parts[0]} -ge 224 ]]; then
        return 0 # 是内网IP地址
    else
        return 1 # 不是内网IP地址
    fi
}

# 获取IPv4地址
get_ipv4() {
    local IPV4=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)

    if [ -z "$IPV4" ]; then
        echo "无法获取本机IPv4地址，将尝试通过API获取"
    elif is_private_ipv4 "$IPV4"; then
        echo "检测到内网IPv4地址: $IPV4，将尝试通过API获取公网IP"
        IPV4=""
    else
        echo "检测到公网IPv4地址: $IPV4"
        echo "$IPV4"
        return
    fi

    local API_NET=("ipv4.ip.sb" "ipget.net" "ip.ping0.cc" "https://ip4.seeip.org" "https://api.my-ip.io/ip" "https://ipv4.icanhazip.com" "api.ipify.org")

    for p in "${API_NET[@]}"; do
        echo "尝试通过 $p 获取公网IP..."
        local response=$(curl -s4m8 "$p")
        sleep 1
        if [ $? -eq 0 ] && ! echo "$response" | grep -q "error"; then
            echo "成功获取到公网IP: $response (通过 $p)"
            echo "$response"
            return
        fi
    done

    echo "警告：无法获取公网IP地址，请手动设置"
    echo "127.0.0.1" # 返回一个默认值
}

# 读取面板配置信息
read_panel_config() {
    # 检查文件是否存在
    if [ ! -f "$USER_FILE" ]; then
        echo "错误：找不到文件 $USER_FILE，请确保面板已正确安装并生成用户信息文件。"
        exit 1
    fi

    local PANEL_URL=$(grep "登录页面" "$USER_FILE" | cut -d ':' -f2- | xargs)
    local ADMIN_EMAIL=$(grep "用户名" "$USER_FILE" | cut -d ':' -f2- | xargs)
    local ADMIN_PASSWORD=$(grep "密码" "$USER_FILE" | cut -d ':' -f2- | xargs)

    # 如果没有读取到信息，则退出
    if [ -z "$PANEL_URL" ] || [ -z "$ADMIN_EMAIL" ] || [ -z "$ADMIN_PASSWORD" ]; then
        echo "错误：无法从文件 $USER_FILE 中读取面板信息，请检查文件格式！"
        exit 1
    fi

    # 返回一个数组
    echo "$PANEL_URL|$ADMIN_EMAIL|$ADMIN_PASSWORD"
}

# 创建节点
create_node() {
    local node_name=$1
    local node_memory=$2
    local node_over_memory=$3
    local node_disk=$4
    local node_over_disk=$5
    local IPV4=$6

    echo "开始创建节点: $node_name"
    echo "节点IP地址: $IPV4"
    echo "节点配置: 内存=${node_memory}MB(超分配${node_over_memory}%) 磁盘=${node_disk}MB(超分配${node_over_disk}%)"

    cd "$PANEL_DIR"

    php artisan p:node:make \
        --name="${node_name}" \
        --description="Auto Generate" \
        --locationId=1 \
        --fqdn="${IPV4}" \
        --public=1 \
        --scheme=http \
        --proxy=0 \
        --maintenance=0 \
        --maxMemory=${node_memory} \
        --overallocateMemory=${node_over_memory} \
        --maxDisk=${node_disk} \
        --overallocateDisk=${node_over_disk} \
        --uploadSize=1024 \
        --daemonListeningPort=8080 \
        --daemonSFTPPort=2022 \
        --daemonBase="/var/lib/pterodactyl" \
        --no-interaction

    local EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
        echo "错误：节点创建失败，错误代码: $EXIT_CODE"
        return 1
    fi

    echo "节点创建成功！"
    return 0
}

# 模拟登录面板 - 改进版
login_panel() {
    local panel_url=$1
    local admin_email=$2
    local admin_password=$3

    echo "正在登录Pterodactyl面板: $panel_url"

    # 删除旧的cookie文件(如果存在)
    rm -f "$COOKIES_FILE"

    # 首先获取CSRF令牌
    local csrf_response=$(curl -s -c "$COOKIES_FILE" "${panel_url}/auth/login")
    local initial_csrf=$(grep "XSRF-TOKEN" "$COOKIES_FILE" | awk '{print $7}' | url_decode)

    if [ -z "$initial_csrf" ]; then
        echo "错误：无法获取初始CSRF令牌"
        return 1
    fi

    echo "获取到初始CSRF令牌: $initial_csrf"

    # 使用CSRF令牌进行登录
    local LOGIN_RESPONSE=$(curl -s -c "$COOKIES_FILE" -b "$COOKIES_FILE" -X POST "$panel_url/auth/login" \
        -H "X-CSRF-TOKEN: $initial_csrf" \
        -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:137.0) Gecko/20100101 Firefox/137.0' \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -H 'X-Requested-With: XMLHttpRequest' \
        --data-raw "{\"user\":\"$admin_email\",\"password\":\"$admin_password\"}")

    # 验证登录是否成功
    if echo "$LOGIN_RESPONSE" | grep -q "错误" || echo "$LOGIN_RESPONSE" | grep -q "token_mismatch" || echo "$LOGIN_RESPONSE" | grep -q "These credentials do not match our records"; then
        echo "错误：面板登录失败，请检查用户名和密码是否正确！"
        return 1
    fi

    # 获取更新后的CSRF令牌
    local CSRF_TOKEN=$(grep "XSRF-TOKEN" "$COOKIES_FILE" | awk '{print $7}' | url_decode)

    echo "登录成功，获取到CSRF Token: $CSRF_TOKEN"
    echo "$CSRF_TOKEN"
    return 0
}

# 生成API密钥 - 改进版
generate_api_key() {
    local panel_url=$1
    local csrf_token=$2

    echo "正在生成API密钥..."

    # 首先检查是否已经存在API密钥
    local keys_response=$(curl -s -b "$COOKIES_FILE" -X GET "$panel_url/account/api" \
        -H "X-CSRF-TOKEN: $csrf_token" \
        -H "Accept: text/html,application/xhtml+xml")

    # 如果已有密钥太多，先删除一个
    if echo "$keys_response" | grep -q "Delete API Key"; then
        echo "检测到已有API密钥，将创建新的密钥"

        # 获取第一个API密钥的ID
        local api_id=$(echo "$keys_response" | grep -o 'data-action="delete-api-key" data-id="[0-9]*"' | head -1 | grep -o 'data-id="[0-9]*"' | grep -o '[0-9]*')

        if [ ! -z "$api_id" ]; then
            echo "删除已有API密钥ID: $api_id"
            curl -s -b "$COOKIES_FILE" -X DELETE "$panel_url/account/api/revoke/$api_id" \
                -H "X-CSRF-TOKEN: $csrf_token" \
                -H "Accept: application/json" \
                -H "X-Requested-With: XMLHttpRequest"
        fi
    fi

    # 创建新的API密钥
    local API_KEY_RESPONSE=$(curl -s -b "$COOKIES_FILE" -X POST "$panel_url/account/api" \
        -H "X-CSRF-TOKEN: $csrf_token" \
        -H "Accept: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data "description=auto-deploy-$(date +%Y%m%d)&allowed_ips=")

    # 提取API密钥
    local API_KEY=""
    if [[ "$API_KEY_RESPONSE" == *"token"* ]]; then
        API_KEY=$(echo "$API_KEY_RESPONSE" | grep -o '"token":"[^"]*"' | sed 's/"token":"//;s/"//')
    fi

    if [ -z "$API_KEY" ]; then
        echo "错误：生成API密钥失败！"
        return 1
    fi

    echo "API密钥生成成功"
    echo "$API_KEY"
    return 0
}

# 获取最新创建的节点ID
get_latest_node_id() {
    local panel_url=$1
    local api_key=$2

    echo "获取最新创建的节点ID..."

    local nodes_response=$(curl -s -X GET "$panel_url/api/application/nodes" \
        -H "Authorization: Bearer $api_key" \
        -H "Accept: application/json")

    # 解析节点列表获取最新节点ID
    local latest_node_id=""
    if echo "$nodes_response" | grep -q "data"; then
        # 使用grep和sed提取最后一个节点ID
        latest_node_id=$(echo "$nodes_response" | grep -o '"id":[0-9]*' | tail -1 | cut -d':' -f2)
    fi

    if [ -z "$latest_node_id" ]; then
        echo "警告：无法获取最新节点ID，将使用默认值1"
        latest_node_id=1
    fi

    echo "获取到最新节点ID: $latest_node_id"
    echo "$latest_node_id"
    return 0
}

# 生成节点安装令牌 - 改进版
generate_install_token() {
    local panel_url=$1
    local api_key=$2
    local node_id=$3

    echo "正在为节点ID $node_id 生成安装令牌..."

    local TOKEN_RESPONSE=$(curl -s -X POST "$panel_url/api/application/nodes/$node_id/install" \
        -H "Authorization: Bearer $api_key" \
        -H "Accept: application/json")

    # 尝试解析安装令牌
    local INSTALL_TOKEN=""
    if [[ "$TOKEN_RESPONSE" == *"token"* ]]; then
        INSTALL_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | sed 's/"token":"//;s/"//')
    fi

    if [ -z "$INSTALL_TOKEN" ]; then
        echo "错误：生成安装令牌失败！"
        return 1
    fi

    echo "安装令牌生成成功"
    echo "$INSTALL_TOKEN"
    return 0
}

# 显示Wings安装命令
show_wings_install_command() {
    local panel_url=$1
    local install_token=$2
    local node_id=$3

    echo -e "\n🎉 完整的Wings一键安装命令：\n"
    echo "cd /etc/pterodactyl && sudo wings configure --panel-url $panel_url --token $install_token --node $node_id"
    echo -e "\n执行以上命令后，启动Wings服务：\n"
    echo "sudo systemctl enable --now wings"
}

# 主函数
main() {
    check_root

    echo "开始执行部署脚本"

    # 读取节点参数
    read -p "请输入节点名称 [默认: auto-node]: " node_name
    node_name=${node_name:-auto-node}

    read -p "请输入节点内存 (MB) [默认: 1024]: " node_memory
    node_memory=${node_memory:-1024}

    read -p "请输入内存超分配百分比 [默认: 0]: " node_over_memory
    node_over_memory=${node_over_memory:-0}

    read -p "请输入节点磁盘 (MB) [默认: 10240]: " node_disk
    node_disk=${node_disk:-10240}

    read -p "请输入磁盘超分配百分比 [默认: 0]: " node_over_disk
    node_over_disk=${node_over_disk:-0}

    # 获取IP地址
    IPV4=$(get_ipv4)

    # 创建节点
    create_node "$node_name" "$node_memory" "$node_over_memory" "$node_disk" "$node_over_disk" "$IPV4"
    if [ $? -ne 0 ]; then
        echo "节点创建失败，脚本中断"
        exit 1
    fi

    # 读取面板配置
    IFS='|' read -r PANEL_URL ADMIN_EMAIL ADMIN_PASSWORD <<<"$(read_panel_config)"

    echo "面板地址: $PANEL_URL"
    echo "管理员邮箱: $ADMIN_EMAIL"

    # 模拟登录面板
    CSRF_TOKEN=$(login_panel "$PANEL_URL" "$ADMIN_EMAIL" "$ADMIN_PASSWORD")
    if [ $? -ne 0 ]; then
        echo "面板登录失败，脚本中断"
        exit 1
    fi

    # 生成API密钥
    API_KEY=$(generate_api_key "$PANEL_URL" "$CSRF_TOKEN")
    if [ $? -ne 0 ]; then
        echo "API密钥生成失败，脚本中断"
        exit 1
    fi

    # 获取最新创建的节点ID
    NODE_ID=$(get_latest_node_id "$PANEL_URL" "$API_KEY")
    if [ $? -ne 0 ]; then
        echo "获取最新节点ID失败，将使用默认值1"
        NODE_ID=1
    else
        echo "将使用节点ID: $NODE_ID"
    fi

    read -p "请确认节点ID [默认: $NODE_ID]: " input_node_id
    NODE_ID=${input_node_id:-$NODE_ID}

    # 生成安装令牌
    INSTALL_TOKEN=$(generate_install_token "$PANEL_URL" "$API_KEY" "$NODE_ID")
    if [ $? -ne 0 ]; then
        echo "安装令牌生成失败，脚本中断"
        exit 1
    fi

    # 显示Wings安装命令
    show_wings_install_command "$PANEL_URL" "$INSTALL_TOKEN" "$NODE_ID"

    # 清理临时文件
    rm -f "$COOKIES_FILE"

    echo "脚本执行完成!"
}

# 执行主函数
main "$@"
