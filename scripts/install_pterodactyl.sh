#!/bin/bash
# from
# https://github.com/spiritLHLS/pterodactyl
# 2023.09.27

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

if [[ "${RELEASE[int]}" != "Debian" && "${RELEASE[int]}" != "Ubuntu" && "${RELEASE[int]}" != "CentOS" ]]; then
    exit 1
else
    mysql_password="oneclickvirt123"
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
if [[ "${RELEASE[int]}" == "Debian" || "${RELEASE[int]}" == "Ubuntu" ]]; then
    apt-get -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    if [ ! -d /usr/share/keyrings/redis-archive-keyring.gpg ]; then
        curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    fi
    if [ ! -d /etc/apt/sources.list.d/redis.list ]; then
        echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    fi
    apt-get install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        apt-get install mariadb-server
    fi
    ubuntu_version=$(lsb_release -rs)
    if [ "$ubuntu_version" == "18.04" ]; then
        apt-add-repository universe
    fi
    check_update
    apt-get -y install php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} nginx redis-server
elif [[ "${RELEASE[int]}" == "CentOS" ]]; then
    yum -y install epel-release curl
    yum -y install https://rpms.remirepo.net/enterprise/remi-release-8.rpm
    yum -y install yum-utils
    yum-config-manager --disable remi-php54
    yum-config-manager --enable remi-php81
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
    yum install mariadb-server
    if [ $? -ne 0 ]; then
        curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash
        yum install mariadb-server
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
mysql -u root -p
CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY "$mysql_password";
CREATE DATABASE panel;
GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;
exit
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan p:environment:setup
php artisan p:environment:database
# php artisan p:environment:mail
php artisan migrate --seed --force
echo "oneclick123" | php artisan p:user:make
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
    systemctl enable --now pteroq.service
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
    systemctl enable --now pteroq.service
    systemctl enable --now redis.service
fi

