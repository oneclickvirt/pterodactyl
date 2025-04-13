#!/bin/bash
# from
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.13

cd /root >/dev/null 2>&1
_red() { echo -e "\033[31m\033[01m$@\033[0m"; }
_green() { echo -e "\033[32m\033[01m$@\033[0m"; }
_yellow() { echo -e "\033[33m\033[01m$@\033[0m"; }
_blue() { echo -e "\033[36m\033[01m$@\033[0m"; }
reading() { read -rp "$(_green "$1")" "$2"; }
export DEBIAN_FRONTEND=noninteractive
utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
if [[ -z "$utf8_locale" ]]; then
    echo "No UTF-8 locale found"
else
    export LC_ALL="$utf8_locale"
    export LANG="$utf8_locale"
    export LANGUAGE="$utf8_locale"
    echo "Locale set to $utf8_locale"
fi
if [ "$(id -u)" != "0" ]; then
    _red "This script must be run as root" 1>&2
    exit 1
fi
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

check_update() {
    _yellow "Updating package management sources"
    if command -v apt-get >/dev/null 2>&1; then
        apt_update_output=$(apt-get update 2>&1)
        echo "$apt_update_output" >"$temp_file_apt_fix"
        if grep -q 'NO_PUBKEY' "$temp_file_apt_fix"; then
            public_keys=$(grep -oE 'NO_PUBKEY [0-9A-F]+' "$temp_file_apt_fix" | awk '{ print $2 }')
            joined_keys=$(echo "$public_keys" | paste -sd " ")
            _yellow "No Public Keys: ${joined_keys}"
            apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ${joined_keys}
            apt-get update
            if [ $? -eq 0 ]; then
                _green "Fixed"
            fi
        fi
        rm "$temp_file_apt_fix"
    else
        ${PACKAGE_UPDATE[int]}
    fi
}

is_private_ipv4() {
    local ip_address=$1
    local ip_parts
    if [[ -z $ip_address ]]; then
        return 0 # 输入为空
    fi
    IFS='.' read -r -a ip_parts <<<"$ip_address"
    # 检查IP地址是否符合内网IP地址的范围
    # 去除 回环，RFC 1918，多播，RFC 6598 地址
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

check_ipv4() {
    IPV4=$(ip -4 addr show | grep global | awk '{print $2}' | cut -d '/' -f1 | head -n 1)
    if is_private_ipv4 "$IPV4"; then # 由于是内网IPV4地址，需要通过API获取外网地址
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

if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
    exit 1
else
    mysql_password="oneclick123"
fi
check_update
if ! command -v curl >/dev/null 2>&1; then
    _yellow "Installing curl"
    ${PACKAGE_INSTALL[int]} curl
fi
if ! command -v tar >/dev/null 2>&1; then
    _yellow "Installing tar"
    ${PACKAGE_INSTALL[int]} tar
fi
if ! command -v unzip >/dev/null 2>&1; then
    _yellow "Installing unzip"
    ${PACKAGE_INSTALL[int]} unzip
fi
if ! command -v git >/dev/null 2>&1; then
    _yellow "Installing git"
    ${PACKAGE_INSTALL[int]} git
fi
if ! command -v sudo >/dev/null 2>&1; then
    _yellow "Installing sudo"
    ${PACKAGE_INSTALL[int]} sudo
fi
if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
    apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    if [[ "${RELEASE[int]}" == "Ubuntu" ]]; then
        LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    else
        if [ ! -d /etc/apt/sources.list.d/sury-php.list ]; then
            echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/sury-php.list
        fi
        wget -qO - https://packages.sury.org/php/apt.gpg | apt-key add -
    fi
    if [ ! -d /usr/share/keyrings/redis-archive-keyring.gpg ]; then
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    fi
    if [ ! -d /etc/apt/sources.list.d/redis.list ]; then
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    fi
    apt-get -y install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        apt-get -y install mariadb-server
    fi
    ubuntu_version=$(lsb_release -rs)
    if [ "$ubuntu_version" == "18.04" ]; then
        apt-add-repository universe
    fi
    check_update
    apt-get -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx redis-server
elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
    yum -y install epel-release curl
    yum -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    yum -y install yum-utils
    yum-config-manager --disable remi-php54
    yum-config-manager --enable remi-php82
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
    yum -y install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        yum -y install mariadb-server
    fi
    check_update
    yum -y install php php-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx redis
    systemctl start mariadb
    systemctl enable mariadb
    systemctl start nginx
    systemctl enable nginx
    systemctl start redis
    systemctl enable redis
fi
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
if [ ! -d /var/www/pterodactyl ]; then
    mkdir -p /var/www/pterodactyl
fi
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/
mysql_user="root"
database_name="panel"
echo "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$mysql_password';" > create_user.sql
echo "CREATE DATABASE $database_name;" >> create_user.sql
echo "GRANT ALL PRIVILEGES ON $database_name.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;" >> create_user.sql
mysql -u $mysql_user -p$mysql_password < create_user.sql
rm create_user.sql
mysql -u $mysql_user -p$mysql_password -e "exit"
check_ipv4
while IFS= read -r line; do
  if [[ "$line" == "APP_URL="* ]]; then
    sed -i 's/^APP_URL=.*/APP_URL="http:\/\/'"${IPV4}"':80\/"/' ".env.example"
    break
  fi
done < ".env.example"
while IFS= read -r line; do
  if [[ "$line" == "DB_PASSWORD="* ]]; then
    sed -i 's/^DB_PASSWORD=.*/DB_PASSWORD='"${mysql_password}"'/' ".env.example"
    break
  fi
done < ".env.example"
sed -i 's/^MAIL_MAILER=.*/MAIL_MAILER=log/' .env.example
sed -i 's/^MAIL_HOST=.*/MAIL_HOST=127.0.0.1/' .env.example
sed -i 's/^MAIL_PORT=.*/MAIL_PORT=25/' .env.example
sed -i 's/^MAIL_USERNAME=.*/MAIL_USERNAME=null/' .env.example
sed -i 's/^MAIL_PASSWORD=.*/MAIL_PASSWORD=null/' .env.example
sed -i 's/^MAIL_ENCRYPTION=.*/MAIL_ENCRYPTION=null/' .env.example
sed -i 's/^MAIL_FROM_ADDRESS=.*/MAIL_FROM_ADDRESS=no-reply@localhost/' .env.example
sed -i 's/^MAIL_FROM_NAME=.*/MAIL_FROM_NAME="Pterodactyl Panel"/' .env.example
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan p:environment:setup
php artisan p:environment:database
# php artisan p:environment:mail
php artisan migrate --seed --force
_blue "设置管理员用户(请选择Yes) - Setting up the administrator user(Please select Yes)"
_green "At this time passwords must meet the following requirements: 8 characters, mixed case, at least one number."
_green "密码必须满足以下要求：8个字符，大小写混合，至少1个数字"
php artisan p:user:make
if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
    chown -R www-data:www-data /var/www/pterodactyl/*
elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
    chown -R nginx:nginx /var/www/pterodactyl/*
fi
CRON_JOB="* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
echo "$CRON_JOB" | sudo crontab -u root -l | { cat; echo "$CRON_JOB"; } | sudo crontab -u root -
if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
    cat <<EOL > /etc/systemd/system/pteroq.service
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
    cat <<EOL > /etc/systemd/system/pteroq.service
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
systemctl enable --now pteroq.service
systemctl enable --now redis.service
systemctl enable nginx
systemctl enable mariadb
systemctl enable php8.1-fpm
systemctl enable redis-server
rm /etc/nginx/sites-enabled/default
if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
    nginx_config_path="/etc/nginx/sites-available/pterodactyl.conf"
elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
    nginx_config_path="/etc/nginx/conf.d/pterodactyl.conf"
fi
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
echo "$config" > "$nginx_config_path"
if [[ "${RELEASE[int]}" != "CentOS" ]]; then
    ln -s "$nginx_config_path" /etc/nginx/sites-enabled/pterodactyl.conf
fi
nginx -t
systemctl restart nginx
if [ -d /var/www/pterodactyl/config/recaptcha.php ]; then
    sed -i "s/'enabled' => env('RECAPTCHA_ENABLED', true),/'disabled' => env('RECAPTCHA_ENABLED', false),/g" "/var/www/pterodactyl/config/recaptcha.php"
fi
while IFS= read -r line; do
  if [[ "$line" == "APP_ENVIRONMENT_ONLY="* ]]; then
    sed -i 's/^APP_ENVIRONMENT_ONLY=.*/APP_ENVIRONMENT_ONLY=false/' ".env"
    break
  fi
done < ".env"
_green "Login Page URL: http://${IPV4}:80/"
_green "登录页面URL: http://${IPV4}:80/"
echo ""
