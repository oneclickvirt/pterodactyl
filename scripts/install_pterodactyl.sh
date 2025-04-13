#!/bin/bash
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.13

###########################################
# 初始化和环境变量设置
###########################################

export DEBIAN_FRONTEND=noninteractive
cd /root >/dev/null 2>&1

# 设置UTF-8语言环境
setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        echo "No UTF-8 locale found"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        echo "Locale set to $utf8_locale"
    fi
}

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        _red "This script must be run as root" 1>&2
        exit 1
    fi
}

# 系统变量初始化
init_system_vars() {
    temp_file_apt_fix="/tmp/apt_fix.txt"
    REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch")
    RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch")
    PACKAGE_UPDATE=("! apt-get update && apt-get --fix-broken install -y && apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "pacman -Sy")
    PACKAGE_INSTALL=("apt-get -y install" "apt-get -y install" "yum -y install" "yum -y install" "yum -y install" "pacman -Sy --noconfirm --needed")
    PACKAGE_REMOVE=("apt-get -y remove" "apt-get -y remove" "yum -y remove" "yum -y remove" "yum -y remove" "pacman -Rsc --noconfirm")
    PACKAGE_UNINSTALL=("apt-get -y autoremove" "apt-get -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "")
    CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')" "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)")

    SYS="${CMD[0]}"
    [[ -n $SYS ]] || exit 1

    for ((int = 0; int < ${#REGEX[@]}; int++)); do
        if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
            SYSTEM="${RELEASE[int]}"
            [[ -n $SYSTEM ]] && break
        fi
    done

    # 设置默认密码
    mysql_password="oneclick123"
}

###########################################
# 辅助函数模块
###########################################

# 彩色输出函数
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }

# 检查并更新包管理器
check_update() {
    _yellow "更新包管理源"
    if command -v apt-get >/dev/null 2>&1; then
        apt_update_output=$(apt-get update 2>&1)
        echo "$apt_update_output" >"$temp_file_apt_fix"
        if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
            public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
            joined_keys=$(echo "$public_keys" | paste -sd " ")
            _yellow "缺少公钥: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _green "已修复"
            fi
        fi
        rm "$temp_file_apt_fix"
    else
        ${PACKAGE_UPDATE[int]}
    fi
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
check_ipv4() {
    IPV4=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)
    if is_private_ipv4 "$IPV4"; then # 由于是内网IPv4地址，需要通过API获取外网地址
        IPV4=""
        local API_NET=("ipv4.ip.sb" "ipget.net" "ip.ping0.cc" "https://ip4.seeip.org" "https://api.my-ip.io/ip" "https://ipv4.icanhazip.com" "api.ipify.org")
        for p in "${API_NET[@]}"; do
            response=$(curl -s4m8 "$p")
            sleep 1
            if [ $? -eq 0 ] && ! echo "$response" | grep -q "error"; then
                IP_API="$p"
                IPV4="$response"
                break
            fi
        done
    fi
    export IPV4
}

###########################################
# 系统检测模块
###########################################

# 检查系统兼容性
check_system_compatibility() {
    if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
        _red "不支持当前系统: ${RELEASE[int]}"
        exit 1
    fi
}

###########################################
# 依赖安装模块
###########################################

# 安装基本依赖
install_basic_dependencies() {
    _yellow "安装基本依赖"

    # 安装基本工具
    check_update

    if ! command -v curl >/dev/null 2>&1; then
        _yellow "安装 curl"
        ${PACKAGE_INSTALL[int]} curl
    fi

    if ! command -v tar >/dev/null 2>&1; then
        _yellow "安装 tar"
        ${PACKAGE_INSTALL[int]} tar
    fi

    if ! command -v unzip >/dev/null 2>&1; then
        _yellow "安装 unzip"
        ${PACKAGE_INSTALL[int]} unzip
    fi

    if ! command -v git >/dev/null 2>&1; then
        _yellow "安装 git"
        ${PACKAGE_INSTALL[int]} git
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        _yellow "安装 sudo"
        ${PACKAGE_INSTALL[int]} sudo
    fi
}

# 根据系统安装软件包
install_system_packages() {
    _yellow "为 ${RELEASE[int]} 安装必要软件包"

    if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
        install_debian_ubuntu_packages
    elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
        install_centos_packages
    fi

    # 安装Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
}

# 为Debian/Ubuntu安装包
install_debian_ubuntu_packages() {
    apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    # 添加PHP仓库
    if [[ "${RELEASE[int]}" == "Ubuntu" ]]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    else
        if [ ! -d /etc/apt/sources.list.d/sury-php.list ]; then
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/sury-php.list
        fi
        wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
    fi
    # 添加Redis仓库
    if [ ! -d /usr/share/keyrings/redis-archive-keyring.gpg ]; then
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    fi
    if [ ! -d /etc/apt/sources.list.d/redis.list ]; then
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    fi
    # 安装MariaDB
    apt-get -y install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        apt-get -y install mariadb-server
    fi
    # 为Ubuntu 18.04添加universe仓库
    ubuntu_version=$(lsb_release -rs)
    if [ "$ubuntu_version" == "18.04" ]; then
        apt-add-repository universe
    fi
    # 更新和安装必要包
    check_update
    apt-get -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx redis-server
}

# 为CentOS安装包
install_centos_packages() {
    yum -y install epel-release curl
    yum -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    yum -y install yum-utils
    yum-config-manager --disable remi-php54
    yum-config-manager --enable remi-php82
    # 添加Redis仓库
    if [ ! -d /etc/pki/rpm-gpg/redis-archive-keyring.gpg ]; then
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /etc/pki/rpm-gpg/redis-archive-keyring.gpg
    fi
    if [ ! -d /etc/yum.repos.d/redis.repo ]; then
        echo "[redis]" | tee /etc/yum.repos.d/redis.repo
        echo "name=Redis" | tee -a /etc/yum.repos.d/redis.repo
        echo "baseurl=https://packages.redis.io/rpm" | tee -a /etc/yum.repos.d/redis.repo
        echo "gpgcheck=1" | tee -a /etc/yum.repos.d/redis.repo
        echo "gpgkey=file:///etc/pki/rpm-gpg/redis-archive-keyring.gpg" | tee -a /etc/yum.repos.d/redis.repo
    fi
    # 安装MariaDB
    yum -y install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        yum -y install mariadb-server
    fi
    # 更新和安装必要包
    check_update
    yum -y install php php-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx redis
    # 启动服务
    systemctl start mariadb
    systemctl enable mariadb
    systemctl start nginx
    systemctl enable nginx
    systemctl start redis
    systemctl enable redis
}

###########################################
# 数据库配置模块
###########################################

# 设置MySQL数据库
setup_mysql_database() {
    _yellow "配置MySQL数据库"
    mysql_user="root"
    database_name="panel"
    # 创建用户和数据库
    echo "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$mysql_password';" >create_user.sql
    echo "CREATE DATABASE $database_name;" >>create_user.sql
    echo "GRANT ALL PRIVILEGES ON $database_name.* TO 'pterodactyl'@'localhost' IDENTIFIED BY '$mysql_password' WITH GRANT OPTION;" >>create_user.sql
    mysql -u $mysql_user -p$mysql_password <create_user.sql
    rm create_user.sql
    # 验证连接
    mysql -u $mysql_user -p$mysql_password -e "exit"
}

###########################################
# Pterodactyl安装模块
###########################################

# 下载并解压Pterodactyl
download_pterodactyl() {
    _yellow "下载和准备Pterodactyl面板"
    if [ ! -d /var/www/pterodactyl ]; then
        mkdir -p /var/www/pterodactyl
    fi
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
}

# 配置Pterodactyl环境
configure_pterodactyl_env() {
    _yellow "配置Pterodactyl环境"
    check_ipv4
    # 更新APP_URL
    while IFS= read -r line; do
        if [[ "$line" == "APP_URL="* ]]; then
            sed -i 's/^APP_URL=.*/APP_URL="http:\/\/'"${IPV4}"':80\/"/' ".env.example"
            break
        fi
    done <".env.example"
    # 确认密码配置（避免覆盖）
    while IFS= read -r line; do
        if [[ "$line" == "DB_PASSWORD="* ]]; then
            sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD='"${mysql_password}"'/' ".env.example"
            break
        fi
    done <".env.example"
    # 配置邮件设置
    sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' .env.example
    sed -i 's/^MAIL_HOST=.*/MAIL_HOST=127.0.0.1/' .env.example
    sed -i 's/^MAIL_PORT=.*/MAIL_PORT=25/' .env.example
    sed -i 's/^MAIL_USERNAME=.*/MAIL_USERNAME=null/' .env.example
    sed -i 's/^MAIL_PASSWORD=.*/MAIL_PASSWORD=null/' .env.example
    sed -i 's/^MAIL_ENCRYPTION=.*/MAIL_ENCRYPTION=null/' .env.example
    sed -i 's/^MAIL_FROM_ADDRESS=.*/MAIL_FROM_ADDRESS=no-reply@localhost/' .env.example
    sed -i 's/^MAIL_FROM_NAME=.*/MAIL_FROM_NAME="Pterodactyl Panel"/' .env.example
    # 复制环境文件
    cp .env.example .env
}

# 安装Pterodactyl
install_pterodactyl() {
    _yellow "安装Pterodactyl面板"
    # 清理缓存
    php artisan config:clear
    php artisan cache:clear
    php artisan config:cache
    # 安装依赖
    COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader --no-interaction
    # 生成密钥和设置环境
    php artisan key:generate --force --no-interaction
    php artisan p:environment:setup \
        --author="unknown@unknown.com" \
        --url="http://${IPV4}:80/" \
        --timezone="UTC" \
        --cache="file" \
        --session="file" \
        --queue="redis" \
        --redis-host="127.0.0.1" \
        --redis-pass=null \
        --redis-port=6379 \
        --settings-ui=true \
        --telemetry=true \
        --new-salt \
        --no-interaction
    # 配置数据库连接
    php artisan p:environment:database \
        --host=127.0.0.1 \
        --port=3306 \
        --database="${database_name}" \
        --username="pterodactyl" \
        --password="${mysql_password}" \
        --no-interaction
    # 运行数据库迁移
    php artisan migrate --seed --force --no-interaction
    # 创建管理员用户
    PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)
    php artisan p:user:make \
        --email=admin@localhost \
        --username=oneclickvirt \
        --password="$PASSWORD" \
        --name-first=Admin \
        --name-last=User \
        --admin=1
    # 设置文件权限
    if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
        chown -R www-data:www-data /var/www/pterodactyl/*
    elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
        chown -R nginx:nginx /var/www/pterodactyl/*
    fi
    # 禁用reCAPTCHA
    if [ -d /var/www/pterodactyl/config/recaptcha.php ]; then
        sed -i "s/'enabled' => env('RECAPTCHA_ENABLED', true),/'disabled' => env('RECAPTCHA_ENABLED', false),/g" "/var/www/pterodactyl/config/recaptcha.php"
    fi
    # 设置环境模式
    while IFS= read -r line; do
        if [[ "$line" == "APP_ENVIRONMENT_ONLY="* ]]; then
            sed -i 's/^APP_ENVIRONMENT_ONLY=.*/APP_ENVIRONMENT_ONLY=false/' ".env"
            break
        fi
    done <".env"
}

###########################################
# 系统服务配置模块
###########################################

# 设置Cron作业
setup_cron_job() {
    _yellow "设置Cron作业"
    CRON_JOB="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
    echo "$CRON_JOB" | sudo crontab -u root -l | {
        cat
        echo "$CRON_JOB"
    } | sudo crontab -u root -
}

# 创建队列工作服务
create_queue_service() {
    _yellow "创建队列工作服务"
    if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
        cat <<EOL >/etc/systemd/system/pteroq.service
# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL
    elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
        cat <<EOL >/etc/systemd/system/pteroq.service
# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis.service

[Service]
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL
    fi
    # 启用服务
    systemctl enable --now redis.service
    systemctl enable --now pteroq.service
    systemctl enable nginx
    systemctl enable mariadb
    systemctl enable php8.1-fpm
    systemctl enable redis-server
}

###########################################
# 网络服务器配置模块
###########################################

# 配置Nginx
configure_nginx() {
    _yellow "配置Nginx服务器"
    rm /etc/nginx/sites-enabled/default
    if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
        nginx_config_path="/etc/nginx/sites-available/pterodactyl.conf"
    elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
        nginx_config_path="/etc/nginx/conf.d/pterodactyl.conf"
    fi
    # 创建Nginx配置
    config="
server {
    listen 80;
    server_name $IPV4;

    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;
    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE \"upload_max_filesize = 100M \n post_max_size=100M\";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY \"\";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
    }

    location ~ /\.ht {
        deny all;
    }
}
"
    echo "$config" >"$nginx_config_path"
    # 为非CentOS系统创建符号链接
    if [[ "${RELEASE[int]}" != "CentOS" ]]; then
        ln -s "$nginx_config_path" /etc/nginx/sites-enabled/pterodactyl.conf
    fi
    # 测试配置并重启Nginx
    nginx -t
    systemctl restart nginx
}

###########################################
# 主函数
###########################################

main() {
    # 初始化
    setup_locale
    check_root
    init_system_vars
    # 系统检查
    check_system_compatibility
    # 安装过程
    install_basic_dependencies
    install_system_packages
    # 数据库配置
    setup_mysql_database
    # Pterodactyl安装
    download_pterodactyl
    configure_pterodactyl_env
    install_pterodactyl
    # 系统服务配置
    setup_cron_job
    create_queue_service
    # Nginx配置
    configure_nginx
    # 显示安装信息
    _green "安装完成！"
    _green "登录页面(URL): http://${IPV4}:80/"
    _green "用户名(UserName): oneclickvirt"
    _green "密码(Password): $PASSWORD"
    echo ""
}

# 执行主函数
main
