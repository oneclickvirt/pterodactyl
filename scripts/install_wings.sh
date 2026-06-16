#!/bin/bash
# https://github.com/oneclickvirt/pterodactyl
# 2025.04.13
# 将自动安装docker和docker-compose

#######################
# 1. 全局变量与辅助函数
#######################
cd /root >/dev/null 2>&1 || cd /tmp || exit 1
export DEBIAN_FRONTEND=noninteractive
temp_file_apt_fix="/tmp/apt_fix.txt"

# 定义颜色输出函数
_red() { printf '\033[31m\033[01m%s\033[0m\n' "$*"; }
_green() { printf '\033[32m\033[01m%s\033[0m\n' "$*"; }
_yellow() { printf '\033[33m\033[01m%s\033[0m\n' "$*"; }
_blue() { printf '\033[36m\033[01m%s\033[0m\n' "$*"; }
reading() { read -rp "$(_green "$1")" "$2"; }

# 系统识别变量
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "arch")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Arch")
PACKAGE_UPDATE=("! apt-get update && apt-get --fix-broken install -y && apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "pacman -Sy")
CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')" "$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)")

#######################
# 2. 系统检测与初始化
#######################
check_root() {
    if [ "$(id -u)" != "0" ]; then
        if command -v sudo >/dev/null 2>&1; then
            _yellow "Re-running with sudo. / 正在使用 sudo 重新执行。"
            exec sudo -E bash "$0" "$@"
        fi
        _red "此脚本必须以 root 身份运行，或由具备 sudo 权限的用户运行 / This script requires root or sudo." 1>&2
        exit 1
    fi
}

setup_locale() {
    utf8_locale=$(locale -a 2>/dev/null | grep -i -m 1 -E "UTF-8|utf8")
    if [[ -z "$utf8_locale" ]]; then
        echo "未找到 UTF-8 语言环境"
    else
        export LC_ALL="$utf8_locale"
        export LANG="$utf8_locale"
        export LANGUAGE="$utf8_locale"
        echo "语言环境设置为 $utf8_locale"
    fi
}

detect_system() {
    SYS="${CMD[0]}"
    [[ -n $SYS ]] || exit 1
    for ((int = 0; int < ${#REGEX[@]}; int++)); do
        if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
            SYSTEM="${RELEASE[int]}"
            [[ -n $SYSTEM ]] && break
        fi
    done

    # 检查是否是支持的系统
    if [[ "${SYSTEM:-}" != "Debian" && "${SYSTEM:-}" != "Ubuntu" && "${SYSTEM:-}" != "CentOS" ]]; then
        _red "Unsupported OS for the Wings installer: ${SYSTEM:-$SYS}. Supported: Debian, Ubuntu, CentOS. / Wings 安装脚本不支持当前系统：${SYSTEM:-$SYS}。支持：Debian、Ubuntu、CentOS。"
        exit 1
    fi
}

create_directories() {
    if [ ! -d /usr/local/bin ]; then
        mkdir -p /usr/local/bin
    fi

    if [ ! -d /etc/pterodactyl ]; then
        mkdir -p /etc/pterodactyl
    fi
}

#######################
# 3. 包管理与更新模块
#######################
check_update() {
    _yellow "正在更新包管理源"
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

#######################
# 4. 网络检测模块
#######################
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
                IPV4="$response"
                break
            fi
        done
    fi
    export IPV4
}

#######################
# 5. Docker安装模块
#######################
check_china() {
    _yellow "IP area being detected ......"
    if [[ -z "${CN}" ]]; then
        if [[ $(curl -m 6 -s https://ipapi.co/json | grep 'China') != "" ]]; then
            _yellow "根据ipapi.co提供的信息，当前IP可能在中国"
            if [ -t 0 ]; then
                read -e -r -p "是否选用中国镜像完成相关组件安装? ([y]/n) " input
            else
                input="${USE_CHINA_MIRROR:-n}"
                _yellow "非交互环境，使用 USE_CHINA_MIRROR=${input} / Non-interactive mode uses USE_CHINA_MIRROR=${input}"
            fi
            case $input in
            [yY][eE][sS] | [yY])
                echo "使用中国镜像"
                CN=true
                ;;
            [nN][oO] | [nN])
                echo "不使用中国镜像"
                ;;
            *)
                echo "使用中国镜像"
                CN=true
                ;;
            esac
        fi
    fi
}

install_docker_and_compose() {
    _green "This may stay for 2~3 minutes, please be patient..."
    _green "此处可能会停留2~3分钟，请耐心等待。。。"
    sleep 1
    if ! command -v docker >/dev/null 2>&1; then
        _yellow "Installing docker"
        if [[ -z "${CN}" || "${CN}" != true ]]; then
            curl -sSL https://get.docker.com/ | sh
        else
            bash <(curl -sSL https://gitee.com/SuperManito/LinuxMirrors/raw/main/DockerInstallation.sh)
        fi
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then
        if [[ -z "${CN}" || "${CN}" != true ]]; then
            _yellow "Installing docker-compose"
            curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            docker-compose --version
        fi
    fi
    sleep 1
}

#######################
# 6. 系统配置模块
#######################
configure_system() {
    # 配置GRUB以支持swap账户
    grub_config="/etc/default/grub"
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 swapaccount=1"/' "$grub_config"
    sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 swapaccount=1"/' "$grub_config"
    update-grub

    _green "你需要重启服务器以启用修改。"
    echo "1" >/usr/local/bin/reboot_pterodactyl.txt
}

#######################
# 7. Wings安装模块
#######################
install_pterodactyl_wings() {
    # 下载Wings二进制文件
    curl -fL --retry 3 --connect-timeout 15 --max-time 180 -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
}

#######################
# 8. 服务配置模块
#######################
configure_wings_service() {
    # 创建systemd服务
    cat <<EOF >/etc/systemd/system/wings.service
[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    # 启用服务
    systemctl daemon-reload
    systemctl enable --now wings
    verify_wings_health
}

verify_wings_health() {
    _yellow "检查Wings健康状态 / Checking Wings health"
    for _ in {1..12}; do
        if systemctl is-active --quiet wings; then
            break
        fi
        sleep 5
    done
    systemctl is-active --quiet wings
    if command -v ss >/dev/null 2>&1; then
        for _ in {1..12}; do
            if ss -ltn | awk '{print $4}' | grep -Eq ':8080$' && ss -ltn | awk '{print $4}' | grep -Eq ':2022$'; then
                _green "Wings健康检查通过 / Wings health check passed"
                return 0
            fi
            sleep 5
        done
        _red "Wings 未监听 8080/2022 端口，请检查 / Wings is not listening on 8080/2022; please check logs."
        systemctl status wings --no-pager || true
        return 1
    else
        _yellow "缺少 ss 命令，跳过端口检查 / ss command not found, skipping port check."
    fi
    _green "Wings健康检查通过 / Wings health check passed"
}

#######################
# 9. 主函数
#######################
main() {
    check_root "$@"
    setup_locale
    detect_system
    check_update
    check_ipv4
    create_directories
    if [ ! -f "/etc/pterodactyl/config.yml" ] && [ ! -f "/usr/local/bin/reboot_pterodactyl.txt" ]; then
        check_china
        install_docker_and_compose
        configure_system
    fi

    if [ ! -x "/usr/local/bin/wings" ]; then
        install_pterodactyl_wings
    fi

    if [ -f "/etc/pterodactyl/config.yml" ]; then
        configure_wings_service
    else
        _yellow "Wings binary installed, but /etc/pterodactyl/config.yml is missing. Run the generated wings configure command, then rerun this script for service and port checks."
        _yellow "Wings 二进制已安装，但缺少 /etc/pterodactyl/config.yml。请先执行导入脚本生成的 wings configure 命令，然后再次运行本脚本完成服务和端口检查。"
    fi
    _green "Pterodactyl Wings 安装/配置已完成!"
}

# 执行主函数
main "$@"
