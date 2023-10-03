#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "hysteria2-installer by DEATHLINE | @NamelesGhoul" 0.1
echo ""
echo ""

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "openssl")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y $pkg > /dev/null 2>&1
        fi
    done
}

# Check if the directory /root/hysteria already exists
if [ -d "/root/hysteria" ]; then
    echo "Hysteria seems to be already installed."
    echo ""
    echo "Choose an option:"
    echo ""
    echo "1) Reinstall"
    echo ""
    echo "2) Modify"
    echo ""
    echo "3) Uninstall"
    echo ""
    read -p "Enter your choice: " choice
    case $choice in
        1)
            # Reinstall
            rm -rf /root/hysteria
            systemctl stop hysteria
            pkill -f 'hysteria*'
            systemctl disable hysteria > /dev/null 2>&1
            rm /etc/systemd/system/hysteria.service
            ;;
        2)
            # Modify
            cd /root/hysteria
        
            # Get the current port and password from config.yaml
            current_port=$(grep -oP 'listen: :\K\d+' config.yaml)
            current_password=$(grep -m 1 'password:' config.yaml | awk -F': ' '{print $2}' | tr -d '[:space:]')
        
            # Prompt the user for a new port and password
            echo ""
            read -p "Enter a new port (or press enter to keep the current one [$current_port]): " new_port
            [ -z "$new_port" ] && new_port=$current_port
            echo ""
            read -p "Enter a new password (or press enter to keep the current one [$current_password]): " new_password
            [ -z "$new_password" ] && new_password=$current_password
            echo ""
        
            # Update the port and password in config.yaml
            sed -i "s/listen: :${current_port}/listen: :${new_port}/" config.yaml
            sed -i "0,/password: ${current_password}/s//password: ${new_password}/" config.yaml

            
            # Kill the existing hysteria process, reload systemd and restart the hysteria service
            pkill -f 'hysteria*'
            systemctl daemon-reload
            systemctl start hysteria

            # Print client configs
            PUBLIC_IP=$(curl -s https://api.ipify.org)

            echo "v2rayN client config:"
            v2rayN_config="server: $PUBLIC_IP:$new_port
auth: $new_password
transport:
  type: udp
tls:
  sni: bing.com
  insecure: true
bandwidth:
  up: 100 mbps
  down: 100 mbps
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  keepAlivePeriod: 60s
  disablePathMTUDiscovery: false
fastOpen: true
lazy: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
            echo "$v2rayN_config"
            echo ""

            echo "NekoBox/NekoRay URL:"
            nekobox_url="hysteria2://$new_password@$PUBLIC_IP:$new_port/?insecure=1&sni=bing.com"
            echo "$nekobox_url"
            echo ""
            exit 0
            ;;
        3)
            # Uninstall
            rm -rf /root/hysteria
            systemctl stop hysteria
            pkill -f 'hysteria'
            systemctl disable hysteria > /dev/null 2>&1
            rm /etc/systemd/system/hysteria.service
            echo "Hysteria uninstalled successfully!"
            echo ""
            exit 0
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
fi

# Install required packages if not already installed
install_required_packages

# Step 1: Check OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

# Determine binary name
BINARY_NAME=""
case "$OS" in
  Linux)
    case "$ARCH" in
      x86_64) BINARY_NAME="hysteria-linux-amd64";;
      386) BINARY_NAME="hysteria-linux-386";;
      amd64) BINARY_NAME="hysteria-linux-amd64";;
      arm64) BINARY_NAME="hysteria-linux-arm64";;
      mipsle) BINARY_NAME="hysteria-linux-mipsle";;
      s390x) BINARY_NAME="hysteria-linux-s390x";;
      amd64-avx) BINARY_NAME="hysteria-linux-amd64-avx";;
      arm) BINARY_NAME="hysteria-linux-arm";;
      armv5) BINARY_NAME="hysteria-linux-armv5";;
      mipsle-sf) BINARY_NAME="hysteria-linux-mipsle-sf";;
      *) echo "Unsupported architecture"; exit 1;;
    esac;;
  # Add more OS checks if needed
  *) echo "Unsupported OS"; exit 1;;
esac


# Step 2: Download the binary
mkdir -p /root/hysteria
cd /root/hysteria
wget -q "https://github.com/apernet/hysteria/releases/latest/download/$BINARY_NAME"
chmod 755 "$BINARY_NAME"

# Step 3: Create self-signed certs
openssl ecparam -genkey -name prime256v1 -out ca.key
openssl req -new -x509 -days 36500 -key ca.key -out ca.crt -subj "/CN=bing.com"

# Step 4: Prompt user for input
echo ""
read -p "Enter a port (or press enter for a random port): " port
[ -z "$port" ] && port=$((RANDOM + 10000))

echo ""
read -p "Enter a password (or press enter for a random password): " password
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)

# Create new config.yaml template based on your requirement
config_yaml="listen: :$port
tls:
  cert: /root/hysteria/ca.crt
  key: /root/hysteria/ca.key
auth:
  type: password
  password: $password
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  maxIncomingStreams: 1024
  disablePathMTUDiscovery: false
bandwidth:
  up: 1 gbps
  down: 1 gbps
ignoreClientBandwidth: false
disableUDP: false
udpIdleTimeout: 60s
resolver:
  type: udp
  tcp:
    addr: 8.8.8.8:53
    timeout: 4s
  udp:
    addr: 8.8.4.4:53
    timeout: 4s
  tls:
    addr: 1.1.1.1:853
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
  https:
    addr: 1.1.1.1:443
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false"
    
echo "$config_yaml" > config.yaml

# Step 5: Run the binary and check the log
/root/hysteria/$BINARY_NAME server -c /root/hysteria/config.yaml > hysteria.log 2>&1 &

# Step 6: Create a system service
cat > /etc/systemd/system/hysteria.service <<EOL
[Unit]
Description=Hysteria VPN Service
After=network.target nss-lookup.target

[Service]
User=root
WorkingDirectory=/root/hysteria
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/root/hysteria/$BINARY_NAME server -c /root/hysteria/config.yaml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOL

systemctl daemon-reload
systemctl enable hysteria > /dev/null 2>&1
systemctl start hysteria

# Step 7: Generate and print client config files
PUBLIC_IP=$(curl -s https://api.ipify.org)
echo ""
echo "v2rayN client config:"
echo ""
v2rayN_config="server: $PUBLIC_IP:$port
auth: $password
transport:
  type: udp
tls:
  sni: bing.com
  insecure: true
bandwidth:
  up: 100 mbps
  down: 100 mbps
quic:
  initStreamReceiveWindow: 8388608
  maxStreamReceiveWindow: 8388608
  initConnReceiveWindow: 20971520
  maxConnReceiveWindow: 20971520
  maxIdleTimeout: 60s
  keepAlivePeriod: 60s
  disablePathMTUDiscovery: false
fastOpen: true
lazy: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
echo ""
echo "$v2rayN_config"
echo ""
echo "NekoBox/NekoRay URL:"
echo ""
nekobox_url="hysteria2://$password@$PUBLIC_IP:$port/?insecure=1&sni=bing.com"
echo ""
echo "$nekobox_url"
echo ""
