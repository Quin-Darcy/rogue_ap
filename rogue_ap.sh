#!/bin/bash


# Check if the correct number of arguments are provided
if [ "$#" -lt 5 ]; then 
    echo "Usage: $0 <INTERNET_INTERFACE> <AP_INTERFACE> <AP_INTERFACE_IP> <AP_SUBNET_MASK> <AP_SSID> [-p AP_PASSWORD]"
    exit 1
fi


# Get the input parameters
INTERNET_INTERFACE=$1
AP_INTERFACE=$2
AP_INTERFACE_IP=$3
AP_SUBNET_MASK=$4
AP_SSID=$5
AP_PASSWORD=""

# Check if the password is set
if [ "$6" == "-p" ] && [ -n "$7" ]; then
    AP_PASSWORD=$7
fi


# Backup original configuration files
if [ -f /etc/hostapd/hostapd.conf ]; then
    sudo cp /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.conf.bak
else 
    sudo touch /etc/hostapd/hostapd.conf
fi

if [ -f /etc/dnsmasq.conf ]; then
    sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak
else 
    sudo touch /etc/dnsmasq.conf
fi


# Stop the services
sudo systemctl stop dnsmasq
sudo systemctl stop hostapd


# Configure hostapd
if [ -n "$AP_PASSWORD" ]; then
    # WPA2 secured
    echo "interface=$AP_INTERFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$AP_PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP" | sudo tee /etc/hostapd/hostapd.conf >/dev/null
else 
    # Open network
    echo "interface=$AP_INTERFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0" | sudo tee /etc/hostapd/hostapd.conf >/dev/null
fi


# Configure dnsmasq
echo "interface=$AP_INTERFACE
port=53
dhcp-range=${AP_INTERFACE_IP%.*}.2,${AP_INTERFACE_IP%.*}.254,$AP_SUBNET_MASK,24h
server=8.8.8.8
server=8.8.4.4" | sudo tee /etc/dnsmasq.conf >/dev/null


# Check and set IP forwarding 
IP_FORWARD_CHECK=$(cat /proc/sys/net/ipv4/ip_forward)
if [ $IP_FORWARD_CHECK -ne 1 ]; then
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
fi


# Check and add iptables rules
IPTABLES_NAT_CHECK=$(sudo iptables -t nat -C POSTROUTING -o $INTERNET_INTERFACE -j MASQUERADE 2> /dev/null; echo $?)
if [ $IPTABLES_NAT_CHECK -ne 0 ]; then
    sudo iptables -t nat -A POSTROUTING -o $INTERNET_INTERFACE -j MASQUERADE
fi

IPTABLES_FORWARD_CHECK=$(sudo iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2> /dev/null; echo $?)
if [ $IPTABLES_FORWARD_CHECK -ne 0 ]; then
    sudo iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
fi

IPTABLES_INCOMING_CHECK=$(sudo iptables -C FORWARD -i $AP_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT 2> /dev/null; echo $?)
if [ $IPTABLES_INCOMING_CHECK -ne 0 ]; then
    sudo iptables -A FORWARD -i $AP_INTERFACE -o $INTERNET_INTERFACE -j ACCEPT
fi


# Assign static IP to AP
sudo ip addr add $AP_INTERFACE_IP/$AP_SUBNET_MASK dev $AP_INTERFACE


# Service restart flag
success=true

if ! sudo systemctl restart dnsmasq; then
    echo "Failed to restart dnsmasq"
    success=false
fi


if ! sudo systemctl restart hostapd; then
    echo "Failed to restart hostapd"
    success=false
fi

if $success; then
    echo "Configuration applied successfully"
else
    echo "Failed to apply configuration. Restoring from backup"

    if [ -f /etc/hostapd.conf.bak ]; then
	echo "Restoring /etc/hostapd/hostapd.conf from backup"
    	sudo mv /etc/hostapd/hostapd.conf.bak /etc/hostapd/hostapd.conf
    	sudo mv /etc/hostapd/hostapd.conf.bak /tmp/
    else 
	echo "No backup of /etc/hostapd/hostapd.conf found"
    fi

    if [ -f /etc/dnsmasq.conf.bak ]; then
	echo "Restoring /etc/dnsmasq.conf from backup"
        sudo mv /etc/dnsmasq.conf.bak /etc/dnsmasq.conf
        sudo mv /etc/dnsmasq.conf.bak /tmp/
    else 
       echo "No backup of /etc/dnsmasq.conf found"
    fi
fi

