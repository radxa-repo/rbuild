#!/bin/bash

HOST_NAME="radxa"
USER_NAME="radxa"
USER_PASSWORD="$USER_NAME"
USER_FULLNAME="Radxa"

rm /etc/resolv.conf
echo $HOST_NAME > /etc/hostname
cat << EOF > /etc/hosts
127.0.0.1 localhost
127.0.1.1 $HOST_NAME

# The following lines are desirable for IPv6 capable hosts
#::1     localhost ip6-localhost ip6-loopback
#fe00::0 ip6-localnet
#ff00::0 ip6-mcastprefix
#ff02::1 ip6-allnodes
#ff02::2 ip6-allrouters
EOF

adduser --gecos $USER_FULLNAME --disabled-password $USER_NAME
adduser $USER_NAME sudo
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

echo locales locales/default_environment_locale select en_US.UTF-8 | debconf-set-selections
echo locales locales/locales_to_be_generated multiselect en_US.UTF-8 UTF-8 | debconf-set-selections

rm /etc/locale.gen
dpkg-reconfigure --frontend noninteractive locales

rm /etc/ssh/ssh_host_*
systemctl disable ssh

systemctl enable haveged rsetup-first-boot