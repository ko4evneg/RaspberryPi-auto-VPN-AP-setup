#!/bin/sh
LBLUE='\033[0;36m'
NC='\033[0m'
SSID='RpiFi'
pw="$1"
pwV2R="$2"
V2Rsub="$3"
if [ -z "$pw" ]; then
  read -p "Enter your desired password for AP RpiFi: " pw
fi
if [ -z "pwV2R" ]; then
  read -p "Enter your desired admin password: " pwV2R
fi
if [ -z "pwV2R" ]; then
  read -p "Enter your subscription URL: " V2Rsub
fi
sudo echo "export pwV2R='${pwV2R}'" >> ~/.bashrc

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
sudo systemctl --system
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
sudo systemctl start dnsmasq.service hostapd.service

echo "${LBLUE}Installing geoips...${NC}"
sudo mkdir -p /usr/local/share/v2ray
cd /usr/local/share/v2ray
sudo wget -O geoip.dat    https://github.com/ko4evneg/RaspberryPi-auto-VPN-AP-setup/raw/refs/heads/main/pkgs/geoip.dat
sudo wget -O geosite.dat  https://github.com/ko4evneg/RaspberryPi-auto-VPN-AP-setup/raw/refs/heads/main/pkgs/geosite.dat
cd ~
echo "${LBLUE}Geoips successfully installed.${NC}"

echo "${LBLUE}Installing v2ray...${NC}"
wget https://github.com/ko4evneg/RaspberryPi-auto-VPN-AP-setup/raw/refs/heads/main/pkgs/v2ray-5.22.0-1-aarch64.pkg.tar.xz -O v2ray_5.pkg.tar.xz
mkdir ~/v2ray5
tar -I zstd -xf v2ray_5.pkg.tar.xz -C ~/v2ray5/
sudo cp -a ~/v2ray5/* /
rm -rf ~/v2ray5
rm -rf ~/v2ray_5.pkg.tar.zst
echo "${LBLUE}V2ray successfully installed.${NC}"

echo "${LBLUE}Installing v2rayA...${NC}"
wget https://github.com/ko4evneg/RaspberryPi-auto-VPN-AP-setup/raw/refs/heads/main/pkgs/v2raya_arch_arm64_2.2.6.7.pkg.tar.zst -O v2raya.pkg.tar.zst
mkdir ~/v2raya-tmp
tar -I zstd -xf v2raya.pkg.tar.zst -C ~/v2raya-tmp/
sudo cp -a ~/v2raya-tmp/* /
rm -rf ~/v2raya-tmp
rm -rf ~/v2raya.pkg.tar.zst
echo "${LBLUE}V2rayA successfully installed.${NC}"

sudo systemctl stop v2raya
sudo v2raya --reset-password
sudo systemctl restart v2raya
sleep 3
curl -X POST "http://172.16.1.1:2021/api/account" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"'"$pwV2R"'"}'
TOKEN=$(curl -X POST "http://172.16.1.1:2021/api/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"'"$pwV2R"'"}'|sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
curl -X POST "http://172.16.1.1:2021/api/import" \
  -H "Content-Type: application/json" \
  -H "Authorization: ${TOKEN}" \
  -d "{\"url\":\"${V2Rsub}\"}"
curl -X POST "http://172.16.1.1:2021/api/setting" -H "Content-Type: application/json" -H "Authorization: ${TOKEN}" \
-d '{"proxyModeWhenSubscribe":"direct","pacAutoUpdateMode":"none","pacAutoUpdateIntervalHour":0,"subscriptionAutoUpdateMode":"none","subscriptionAutoUpdateIntervalHour":0,"pacMode":"whitelist","tcpFastOpen":"default","inboundSniffing":"http,tls,quic","muxOn":"no","mux":8,"transparent":"proxy","transparentType":"redirect","ipforward":true,"portSharing":false,"dnsforward":"no","antipollution":"closed","specialMode":"none"}'
curl -X POST "http://172.16.1.1:2021/api/connection" -H "Content-Type: application/json" -H "Authorization: ${TOKEN}" \
-d '{"id":4,"_type":"subscriptionServer","sub":0,"outbound":"proxy"}'
curl -X POST "http://172.16.1.1:2021/api/v2ray" -H "Content-Type: application/json" -H "Authorization: ${TOKEN}"

sudo systemctl daemon-reload
sudo systemctl enable --now v2raya.service
