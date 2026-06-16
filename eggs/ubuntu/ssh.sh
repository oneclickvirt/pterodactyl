#!/bin/bash
# from
# https://github.com/oneclickvirt/docker
# 2026.06.05

set -euo pipefail

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

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER="apk"
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER="pacman"
    elif command -v pkg >/dev/null 2>&1; then
        PACKAGE_MANAGER="pkg"
    else
        PACKAGE_MANAGER=""
    fi
}

install_packages() {
    if command -v sshd >/dev/null 2>&1 && command -v chpasswd >/dev/null 2>&1; then
        msg "SSH dependencies already exist." "SSH 依赖已存在。"
        return 0
    fi

    detect_package_manager
    msg "Installing SSH dependencies." "正在安装 SSH 依赖。"
    case "$PACKAGE_MANAGER" in
        apt)
            apt-get update -y
            apt-get install -y dos2unix wget sudo sshpass openssh-server ca-certificates
            ;;
        apk)
            apk add --no-cache bash dos2unix wget sudo sshpass openssh-server ca-certificates
            ;;
        dnf)
            dnf install -y dos2unix wget sudo sshpass openssh-server ca-certificates
            ;;
        yum)
            yum install -y dos2unix wget sudo sshpass openssh-server ca-certificates
            ;;
        pacman)
            pacman -Sy --noconfirm --needed dos2unix wget sudo sshpass openssh ca-certificates
            ;;
        pkg)
            pkg install -y bash dos2unix wget sudo openssh-portable ca_root_nss || true
            ;;
        *)
            msg "No supported package manager was found; keeping existing SSH packages." "未找到受支持的包管理器，将使用系统现有 SSH 组件。"
            ;;
    esac
}

random_chars() {
    local charset="$1" count="$2" chars
    set +o pipefail
    chars=$(LC_ALL=C tr -dc "$charset" </dev/urandom | head -c "$count")
    set -o pipefail
    if [ "${#chars}" -lt "$count" ]; then
        chars="${chars}$(date +%s)$(hostname | tr -dc 'A-Za-z0-9')"
        chars="${chars:0:$count}"
    fi
    printf '%s' "$chars"
}

generate_password() {
    local password
    password="$(random_chars 'a-z' 1)$(random_chars 'A-Z' 1)$(random_chars '0-9' 1)$(random_chars '@#%_+=:,.~' 1)$(random_chars 'A-Za-z0-9@#%_+=:,.~' 20)"
    printf '%s' "$password" | fold -w1 | awk '
        BEGIN { srand() }
        { chars[NR] = $0 }
        END {
            for (i = NR; i > 1; i--) {
                j = int(rand() * i) + 1
                tmp = chars[i]
                chars[i] = chars[j]
                chars[j] = tmp
            }
            for (i = 1; i <= NR; i++) {
                printf "%s", chars[i]
            }
        }
    '
}

set_root_password() {
    local password_file password
    password_file="${SSH_CREDENTIAL_FILE:-/root/.oneclickvirt_ssh_credentials}"
    if [ -n "${SSH_ROOT_PASSWORD:-}" ]; then
        password="$SSH_ROOT_PASSWORD"
    elif [ -f "$password_file" ] && grep -q '^password=' "$password_file"; then
        password="$(sed -n 's/^password=//p' "$password_file" | head -n 1)"
    else
        password="$(generate_password)"
    fi

    if command -v chpasswd >/dev/null 2>&1; then
        printf 'root:%s\n' "$password" | chpasswd
    else
        msg "chpasswd is not available; root password was not changed." "系统缺少 chpasswd，未修改 root 密码。"
        return 0
    fi

    umask 077
    {
        printf 'username=root\n'
        printf 'password=%s\n' "$password"
        printf 'ssh_port=%s\n' "${SSH_PORT:-22}"
        printf 'permit_root_login=%s\n' "${PERMIT_ROOT_LOGIN:-prohibit-password}"
        printf 'password_authentication=%s\n' "${PASSWORD_AUTHENTICATION:-yes}"
        printf 'pubkey_authentication=%s\n' "${PUBKEY_AUTHENTICATION:-yes}"
    } >"$password_file"
    chmod 600 "$password_file"
    msg "Root credentials were generated at $password_file." "root 凭据已生成到 $password_file。"
}

set_sshd_option() {
    local file key value tmp
    file="$1"
    key="$2"
    value="$3"

    [ -f "$file" ] || return 0
    tmp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        {
            token = $1
            sub(/^#/, "", token)
            if (tolower(token) == tolower(key)) {
                if (!done) {
                    print key " " value
                    done = 1
                }
                next
            }
            print
        }
        END {
            if (!done) {
                print key " " value
            }
        }
    ' "$file" >"$tmp"
    cat "$tmp" >"$file"
    rm -f "$tmp"
}

configure_sshd_file() {
    local file="$1"
    [ -f "$file" ] || return 0

    set_sshd_option "$file" Port "${SSH_PORT:-22}"
    set_sshd_option "$file" ListenAddress "0.0.0.0"
    set_sshd_option "$file" AddressFamily "any"
    set_sshd_option "$file" PubkeyAuthentication "${PUBKEY_AUTHENTICATION:-yes}"
    set_sshd_option "$file" PasswordAuthentication "${PASSWORD_AUTHENTICATION:-yes}"

    set_sshd_option "$file" PermitRootLogin "${PERMIT_ROOT_LOGIN:-prohibit-password}"
}

configure_selinux() {
    if [ "${DISABLE_SELINUX:-false}" != "true" ]; then
        msg "SELinux was not changed. Set DISABLE_SELINUX=true to opt in." "未修改 SELinux。如需明确关闭，请设置 DISABLE_SELINUX=true。"
        return 0
    fi

    msg "Disabling SELinux because DISABLE_SELINUX=true was set." "检测到 DISABLE_SELINUX=true，正在按用户选择关闭 SELinux。"
    if [ -f /etc/sysconfig/selinux ]; then
        sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/sysconfig/selinux
    fi
    if [ -f /etc/selinux/config ]; then
        sed -i.bak '/^SELINUX=/cSELINUX=disabled' /etc/selinux/config
    fi
    if command -v setenforce >/dev/null 2>&1; then
        setenforce 0 || true
    fi
}

restart_sshd() {
    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -A || true
    fi

    service ssh restart 2>/dev/null ||
        service sshd restart 2>/dev/null ||
        systemctl restart ssh 2>/dev/null ||
        systemctl restart sshd 2>/dev/null ||
        rc-service sshd restart 2>/dev/null ||
        msg "SSH service restart was skipped; service manager not available." "未找到可用服务管理器，已跳过 SSH 重启。"
}

write_motd() {
    if [ -f /etc/motd ]; then
        grep -q 'https://github.com/oneclickvirt/docker' /etc/motd 2>/dev/null ||
            printf '%s\n' 'Related repo https://github.com/oneclickvirt/docker' >>/etc/motd
        grep -q 'https://t.me/spiritlhl' /etc/motd 2>/dev/null ||
            printf '%s\n' '--by https://t.me/spiritlhl' >>/etc/motd
    fi
}

main() {
    need_root "$@"
    install_packages
    write_motd
    configure_selinux
    set_root_password
    configure_sshd_file /etc/ssh/sshd_config
    configure_sshd_file /etc/ssh/sshd_config.d/50-cloud-init.conf
    restart_sshd
    msg "SSH setup completed." "SSH 初始化完成。"
}

main "$@"
