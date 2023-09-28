#!/bin/bash
# from
# https://github.com/spiritLHLS/pterodactyl
# 2023.09.28


cd /root >/dev/null 2>&1
if [ -f "/var/www/pterodactyl/database/Seeders/eggs" ]; then
    wget https://github.com/spiritLHLS/pterodactyl/archive/refs/heads/main.zip
    chmod 777 main.zip
    unzip main.zip
    if [ ! -f "/var/www/pterodactyl/database/Seeders/eggs/vps" ]; then
        mkdir -p /var/www/pterodactyl/database/Seeders/eggs/vps
    fi
    if [ ! -f "/var/www/pterodactyl/database/Seeders/eggs/vps/debian" ]; then
        mkdir -p /var/www/pterodactyl/database/Seeders/eggs/vps/debian
    fi
    if [ ! -f "/var/www/pterodactyl/database/Seeders/eggs/vps/ubuntu" ]; then
        mkdir -p /var/www/pterodactyl/database/Seeders/eggs/vps/ubuntu
    fi
    cp ./pterodactyl-main/eggs/debian/* /var/www/pterodactyl/database/Seeders/eggs/vps/debian/
    cp ./pterodactyl-main/eggs/ubuntu/* /var/www/pterodactyl/database/Seeders/eggs/vps/ubuntu/
    cp ./pterodactyl-main/eggs/EggSeeder.php /var/www/pterodactyl/database/Seeders/
    cp ./pterodactyl-main/eggs/NestSeeder.php /var/www/pterodactyl/database/Seeders/
    rm -rf pterodactyl_eggs* 
    rm -rf pterodactyl-main*
    rm -rf main.zip*
fi
