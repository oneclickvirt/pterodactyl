#!/bin/bash
# from
# https://github.com/oneclickvirt/pterodactyl
# 2026.06.05

set -euo pipefail

REPO_ZIP_URL="${REPO_ZIP_URL:-https://github.com/oneclickvirt/pterodactyl/archive/refs/heads/main.zip}"
PANEL_SEEDER_DIR="${PANEL_SEEDER_DIR:-/var/www/pterodactyl/database/Seeders}"

msg() {
    printf '%s / %s\n' "$1" "$2"
}

need_root() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi
    if command -v sudo >/dev/null 2>&1; then
        exec sudo -E bash "$0" "$@"
    fi
    msg "This script needs root privileges or sudo." "此脚本需要 root 权限或 sudo。"
    exit 1
}

main() {
    need_root "$@"

    if ! command -v curl >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
        msg "curl and unzip are required." "需要先安装 curl 和 unzip。"
        exit 1
    fi

    workdir="$(mktemp -d)"
    trap 'rm -rf "$workdir"' EXIT

    zip_file="$workdir/pterodactyl-main.zip"
    msg "Downloading egg files." "正在下载 egg 文件。"
    curl -fL --retry 3 --connect-timeout 15 --max-time 120 "$REPO_ZIP_URL" -o "$zip_file"
    unzip -t "$zip_file" >/dev/null
    unzip -q "$zip_file" -d "$workdir"

    source_dir="$workdir/pterodactyl-main"
    if [ ! -d "$source_dir" ]; then
        msg "Unexpected archive layout." "压缩包目录结构异常。"
        exit 1
    fi

    install -d -m 0755 "$PANEL_SEEDER_DIR/eggs/vps"
    install -m 0644 "$source_dir/eggs/debian/egg-debian.json" "$PANEL_SEEDER_DIR/eggs/vps/egg-debian.json"
    install -m 0644 "$source_dir/eggs/ubuntu/egg-ubuntu.json" "$PANEL_SEEDER_DIR/eggs/vps/egg-ubuntu.json"
    install -m 0644 "$source_dir/back/EggSeeder.php" "$PANEL_SEEDER_DIR/EggSeeder.php"
    install -m 0644 "$source_dir/back/NestSeeder.php" "$PANEL_SEEDER_DIR/NestSeeder.php"

    msg "Egg seeders synchronized." "Egg Seeder 已同步。"
}

main "$@"
