FROM ubuntu:jammy-20250619@sha256:3c61d3759c2639d4b836d32a2d3c83fa0214e36f195a3421018dbaaf79cbe37f

# Set noninteractive mode
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y wget bash curl ca-certificates iproute2 zip unzip sudo dos2unix sshpass openssh-server iputils-ping \
    && apt-get install -y --no-install-recommends python3 python3-pip gnupg2 \
    && apt-get install -y git \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --gecos "" --home /home/container container \
    && mkdir -p /opt/pterodactyl /home/container \
    && chown -R container:container /home/container

COPY ./ssh.sh /opt/pterodactyl/ssh.sh
COPY ./start.sh /opt/pterodactyl/start.sh
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod 0755 /opt/pterodactyl/ssh.sh /opt/pterodactyl/start.sh /entrypoint.sh

ENV USER=container
ENV HOME=/home/container
WORKDIR /home/container

CMD ["/bin/bash", "/entrypoint.sh"]
