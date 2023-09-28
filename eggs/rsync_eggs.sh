#!/bin/bash
# from
# https://github.com/spiritLHLS/pterodactyl
# 2023.09.28


cd /root >/dev/null 2>&1
if [ -f "/var/www/pterodactyl/database/Seeders/eggs" ]; then
    curl -slk https://github.com/spiritLHLS/pterodactyl/archive/refs/heads/main.zip -o pterodactyl_eggs.zip
    chmod 777 pterodactyl_eggs.zip
    unzip pterodactyl_eggs.zip
    cp -r ./pterodactyl_eggs/pterodactyl-main/eggs /var/www/pterodactyl/database/Seeders/eggs
    rm -rf pterodactyl_eggs*
fi