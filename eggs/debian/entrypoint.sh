#!/bin/bash
set -euo pipefail

cd /home/container

# Make internal Docker IP address available to processes.
INTERNAL_IP="$(ip route get 1 | awk '{print $NF;exit}')"
export INTERNAL_IP
export SSH_CREDENTIAL_FILE="${SSH_CREDENTIAL_FILE:-/home/container/.ssh_credentials}"

if [ ! -x ./start.sh ]; then
    cp /opt/pterodactyl/start.sh ./start.sh
    chmod +x ./start.sh
fi

if [ "$(id -u)" -eq 0 ]; then
    bash /opt/pterodactyl/ssh.sh
    chown container:container "$SSH_CREDENTIAL_FILE" ./start.sh 2>/dev/null || true
    service ssh start 2>/dev/null || service sshd start 2>/dev/null || /usr/sbin/sshd 2>/dev/null || true
    exec sudo -E -u container bash ./start.sh
fi

exec bash ./start.sh
