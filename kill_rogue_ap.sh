#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <INTERNET_INTERFACE> <AP_INTERFACE> <AP_INTERFACE_IP> <AP_SUBNET>"
    exit 1
fi


# Get the input parameters
INTERNET_INTERFACE=$1
AP_INTERFACE=$2
AP_INTERFACE_IP=$3
AP_SUBNET=$4

# Stop the services
sudo systemctl stop dnsmasq
sudo systemctl stop hostapd

# Restore the backup configuration files if they exist
if [ -f /etc/hostapd/hostapd.conf.bak ]; then
    echo "Restoring /etc/hostapd/hostapd.conf from backup"
    sudo mv /etc/hostapd/hostapd.conf.bak /etc/hostapd/hostapd.conf
fi

if [ -f /etc/dnsmasq.conf.bak ]; then
    echo "Restoring /etc/dnsmasq.conf from backup"
    sudo mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
fi

# Reset IP forwarding
echo 0 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

# Check and remove iptables rules
if sudo iptables -t nat -C POSTROUTING -o $INTERNET_INTERFACE -j MASQUERADE; then
    sudo iptables -t nat -D POSTROUTING -o $INTERNET_INTERFACE -j MASQUERADE
fi

if sudo iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT; then
    sudo iptables -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
fi

if sudo iptables -C FORWARD -i $AP_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT; then
    sudo iptables -D FORWARD -i $AP_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT
fi

# Check and delete the static IP from AP_INTERFACE
if ip addr show $AP_INTERFACE | grep -q $IP/$SUBNET; then
    sudo ip addr del $AP_INTERFACE_IP/$AP_SUBNET dev $AP_INTERFACE
fi

# Restart dnsmasq
sudo systemctl restart dnsmasq

echo "Reverted to original configuration."

