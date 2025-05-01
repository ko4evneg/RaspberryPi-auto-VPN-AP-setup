echo "\n${GRE}Preparing VPN access point...${NC}"

read -p "Enter your desired WiFi Network Name: " RpiFi
read -p "Enter your desired password: " pw1

sudo nmcli
sudo raspi-config nonint do_wifi_country RU
sudo apt-get install dnsmasq hostapd -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent iptables-persistent
sudo sed -i '$ainterface wlan0\nstatic ip_address=172.16.1.1/24\nnohook wpa_supplicant' /etc/dhcpcd.conf
sudo touch /etc/sysctl.d/routed-ap.conf
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/routed-ap.conf
sudo iptables -t nat -A POSTROUTING -o wlan1 -j MASQUERADE
sudo netfilter-persistent save
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.orig
sudo touch /etc/dnsmasq.conf
echo "interface=wlan0" | sudo tee /etc/dnsmasq.conf
sudo sed -i '$adhcp-range=172.16.1.10,172.16.1.100,255.255.255.0,24\ndomain=ap\naddress=/rpi.ap/172.16.1.1' /etc/dnsmasq.conf
sudo touch /etc/hostapd/hostapd.conf
echo "country_code=RU" | sudo tee /etc/hostapd/hostapd.conf
sudo sed -i -e '$a\' -e "interface=wlan0\nssid=${ssid}\nhw_mode=g\nchannel=2\nmacaddr_acl=0\nauth_algs=1\nignore_broadcast_ssid=0\nwpa=2\nwpa_passphrase=${pw1}\nwpa_key_mgmt=WPA-PSK\nwpa_pairwise=TKIP\nrsn_pairwise=CCMP" /etc/hostapd/hostapd.conf
sudo systemctl unmask hostapd.service
sudo systemctl enable hostapd.service
echo "\n\n\n"
echo          "########## All Done! The RPi AP IP Address is 172.16.1.1 ##########"
echo "\n\n\n"

fi
