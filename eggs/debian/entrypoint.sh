#!/bin/bash
sleep 2

cd /home/container
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`

# Make internal Docker IP address available to processes.
export INTERNAL_IP=`ip route get 1 | awk '{print $NF;exit}'`
curl -Lo ./start.sh https://raw.githubusercontent.com/spiritLHLS/pterodactyl/main/eggs/ubuntu/start.sh
chmod +x ./start.sh
# Run the Server
bash ./start.sh