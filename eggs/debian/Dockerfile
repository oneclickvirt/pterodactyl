FROM debian:latest

# Set noninteractive mode
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y wget bash curl ca-certificates iproute2 zip unzip sudo dos2unix sshpass openssh-server iputils-ping \
    && apt-get install -y --no-install-recommends python3 python3-pip gnupg2 \
    && apt-get install -y git \
    && curl -slk https://raw.githubusercontent.com/spiritLHLS/pterodactyl/main/eggs/ssh.sh -o ssh.sh \
    && bash ssh.sh
    && rm -rf /var/lib/apt/lists/*

RUN adduser --disabled-password --home / container
USER container
ENV USER container
ENV HOME /
WORKDIR /
COPY ./entrypoint.sh /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]