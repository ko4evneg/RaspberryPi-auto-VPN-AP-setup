#!/bin/sh
LBLUE='\033[0;36m'
NC='\033[0m'
SSID='RpiFi'
pw="$1"
if [ -z "$pw" ]; then
  read -p "Enter your desired password for AP RpiFi: " pw
fi

echo "\n${LBLUE}#####   START AUTO-CONFIGURATION SCRIPT   #####${NC}"

echo "${LBLUE}Updating system...${NC}"
sudo apt update
sudo apt full-upgrade -y -q --show-progress
sudo apt install lshw -y -q
echo "${LBLUE}System updated successfully...${NC}"

echo "${LBLUE}Configuring ethernet management interface...${NC}"
ETH_UUID=$(nmcli -t -f UUID,DEVICE connection show|awk -F: '$2=="eth0"{print $1}')
echo "${LBLUE}Detected ethernet connection UUID:${ETH_UUID}${NC}"
sudo nmcli connection modify $ETH_UUID connection.id mgmt connection.autoconnect yes
sudo nmcli connection modify mgmt \
  ipv4.addresses 172.16.100.1/24 \
  ipv4.method manual \
  ipv4.ignore-auto-routes yes \
  ipv4.never-default yes \
  ipv4.ignore-auto-dns yes
sudo nmcli connection down mgmt
sudo nmcli connection up mgmt
echo "${LBLUE}Management connection successfully configured. IP: 172.16.100.1/24${NC}"

INTERNET_WLAN_IF=$(sudo lshw -c network| awk '/bus info: usb/{getline; if (/logical name:/) print $3}')
AP_WLAN_IF=$(ls /sys/class/net | grep '^wlan' | grep -v "^${INTERNET_WLAN_IF}$")
echo "${LBLUE}Detected USB interface ${INTERNET_WLAN_IF}. Assuming it is internet gateway. Configuring ${AP_WLAN_IF} as access point...${NC}"

sudo raspi-config nonint do_wifi_country RU
sudo apt-get install dnsmasq hostapd -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent
sudo sed -i "\$ainterface ${AP_WLAN_IF}\nstatic ip_address=172.16.1.1/24\nnohook wpa_supplicant" /etc/dhcpcd.conf
sudo touch /etc/sysctl.d/routed-ap.conf
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/routed-ap.conf
sudo iptables -t nat -A POSTROUTING -o $INTERNET_WLAN_IF -j MASQUERADE
sudo netfilter-persistent save
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo touch /etc/dnsmasq.conf
echo "interface=${AP_WLAN_IF}" | sudo tee /etc/dnsmasq.conf
sudo sed -i '$adhcp-range=172.16.1.10,172.16.1.100,255.255.255.0,24\ndomain=ap\naddress=/rpi.ap/172.16.1.1' /etc/dnsmasq.conf
sudo touch /etc/hostapd/hostapd.conf
echo "country_code=RU" | sudo tee /etc/hostapd/hostapd.conf
sudo sed -i -e '$a\' -e "interface=${AP_WLAN_IF}\nssid=${SSID}\nhw_mode=g\nchannel=2\nmacaddr_acl=0\nauth_algs=1\nignore_broadcast_ssid=0\nwpa=2\nwpa_passphrase=${pw}\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=TKIP\nrsn_pairwise=CCMP" /etc/hostapd/hostapd.conf
sudo systemctl unmask hostapd.service
sudo systemctl enable hostapd.service
sudo sed -i '/^ExecStart=/i ExecStartPre=/sbin/ifconfig wlan0 172.16.1.1 netmask 255.255.255.0 up' /lib/systemd/system/hostapd.service
sudo sed -i -e '/^After=/d' -e '/\[Unit\]/a After=network-online.target' /lib/systemd/system/hostapd.service
sudo systemctl stop dnsmasq.service hostapd.service
echo "${LBLUE}Access point successfully configured on ${AP_WLAN_IF}. AP IP: 172.16.1.1/24${NC}"

echo "${LBLUE}Installing v2ray VPN...${NC}"
sudo apt install snapd -y
sudo snap install v2raya
sudo systemctl start dnsmasq.service hostapd.service
echo "${LBLUE}V2ray VPN successfully installed. Web-interface available on port 2017.${NC}"

#TODO add port-forward for public IP
#TODO add auto-start (possibly tunnel)
