#!/bin/bash

# Function to print characters with delay
print_with_delay() {
    text="$1"
    delay="$2"
    for ((i = 0; i < ${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep "$delay"
    done
    echo
}

# Introduction animation
echo ""
echo ""
print_with_delay "hysteria2-installer by DEATHLINE | @NamelesGhoul" 0.1
echo ""
echo ""

# Ensure root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Check for and install required packages
install_required_packages() {
    REQUIRED_PACKAGES=("curl" "certbot")
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            apt-get update > /dev/null 2>&1
            apt-get install -y "$pkg" > /dev/null 2>&1
        fi
    done
}

# Function to update Hysteria binary
update_hysteria() {
    echo "Updating Hysteria to the latest version..."
    bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1
    systemctl restart hysteria-server
    echo "Hysteria updated successfully!"
}

# Check if the directory /etc/hysteria already exists
if [ -d "/etc/hysteria" ] && [ -f "/etc/hysteria/config.yaml" ]; then
    echo "Hysteria seems to be already installed."
    echo ""
    echo "Choose an option:"
    echo ""
    echo "1) Reinstall"
    echo ""
    echo "2) Modify (Change port/password)"
    echo ""
    echo "3) Update Hysteria"
    echo ""
    echo "4) Uninstall"
    echo ""
    echo "5) Show current link"
    echo ""
    read -r -p "Enter your choice: " choice
    case $choice in
        1)
            # Reinstall
            systemctl stop hysteria-server
            systemctl disable hysteria-server > /dev/null 2>&1
            rm -rf /etc/hysteria
            rm -rf /etc/systemd/system/hysteria-server.service.d
            systemctl daemon-reload
            ;;
        2)
            # Modify
            # Read current settings from config
            current_port=$(grep -oP 'listen: :\K\d+' /etc/hysteria/config.yaml || echo "443")
            current_password=$(awk '/^auth:/{f=1; next} f && /^[^ ]/{f=0} f && /password:/{print $2; exit}' /etc/hysteria/config.yaml)
            current_domain=$(grep -oP 'cert: .*/live/\K[^/]+' /etc/hysteria/config.yaml || echo "example.com")
            current_obfs_password=$(awk '/^obfs:/{f=1; next} f && /^[^ ]/{f=0} f && /password:/{print $2; exit}' /etc/hysteria/config.yaml)
            
            echo ""
            read -r -p "Enter a new port (or press enter to keep the current one [$current_port]): " new_port
            [ -z "$new_port" ] && new_port=$current_port
            echo ""
            read -r -p "Enter a new password (or press enter to keep the current one [$current_password]): " new_password
            [ -z "$new_password" ] && new_password=$current_password
            echo ""

            # Obfs modification
            if [ -n "$current_obfs_password" ]; then
                echo "Obfuscation (Salamander) is currently ENABLED (password: $current_obfs_password)"
                read -r -p "Keep obfs enabled? (y/n, default: y): " keep_obfs
                if [ "$keep_obfs" = "n" ] || [ "$keep_obfs" = "N" ]; then
                    new_obfs_password=""
                else
                    read -r -p "Enter a new obfs password (or press enter to keep the current one): " new_obfs_password
                    [ -z "$new_obfs_password" ] && new_obfs_password=$current_obfs_password
                fi
            else
                echo "Obfuscation (Salamander) is currently DISABLED"
                read -r -p "Enable obfs? (y/n, default: n): " enable_obfs
                if [ "$enable_obfs" = "y" ] || [ "$enable_obfs" = "Y" ]; then
                    read -r -p "Enter an obfs password (or press enter for a random one): " new_obfs_password
                    [ -z "$new_obfs_password" ] && new_obfs_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
                else
                    new_obfs_password=""
                fi
            fi
            echo ""

            # Parse current routing configuration
            current_routing="2"
            if grep -q "mode: 4" /etc/hysteria/config.yaml && ! grep -q "mode: 46" /etc/hysteria/config.yaml; then
                current_routing="3"
            elif ! grep -q "mode:" /etc/hysteria/config.yaml; then
                current_routing="1"
            fi

            echo ""
            echo "Select outbound routing mode:"
            echo "1) Default (Dual-stack auto)"
            echo "2) Prefer IPv4 (Recommended for VPS with broken/slow IPv6)"
            echo "3) Force IPv4 only"
            read -r -p "Enter choice [1-3, default: $current_routing]: " route_choice
            [ -z "$route_choice" ] && route_choice=$current_routing

            resolver_yaml=""
            outbounds_yaml=""

            if [ "$route_choice" = "2" ]; then
                resolver_yaml="
resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53"
                outbounds_yaml="
outbounds:
  - name: direct
    type: direct
    direct:
      mode: 46"
            elif [ "$route_choice" = "3" ]; then
                resolver_yaml="
resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53"
                outbounds_yaml="
outbounds:
  - name: direct
    type: direct
    direct:
      mode: 4"
            fi

            # Rebuild config.yaml
            current_cert=$(grep 'cert:' /etc/hysteria/config.yaml | awk '{print $2}')
            current_key=$(grep 'key:' /etc/hysteria/config.yaml | awk '{print $2}')

            config_yaml="listen: :$new_port
tls:
  cert: $current_cert
  key: $current_key
auth:
  type: password
  password: $new_password"

            if [ -n "$new_obfs_password" ]; then
                config_yaml="$config_yaml
obfs:
  type: salamander
  salamander:
    password: $new_obfs_password"
            fi

            config_yaml="$config_yaml$resolver_yaml$outbounds_yaml"

            echo "$config_yaml" > /etc/hysteria/config.yaml

            # Restart the hysteria service
            systemctl restart hysteria-server

            # Print client configs
            echo "v2rayN client config:"
            v2rayN_config="server: $current_domain:$new_port
auth: $new_password
tls:
  sni: $current_domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
            if [ -n "$new_obfs_password" ]; then
                v2rayN_config="server: $current_domain:$new_port
auth: $new_password
obfs:
  type: salamander
  salamander:
    password: $new_obfs_password
tls:
  sni: $current_domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
            fi
            echo "$v2rayN_config"
            echo ""

            echo "NekoBox/NekoRay URL:"
            if [ -n "$new_obfs_password" ]; then
                nekobox_url="hysteria2://$new_password@$current_domain:$new_port/?insecure=0&sni=$current_domain&obfs=salamander&obfs-password=$new_obfs_password#Hysteria2-$((RANDOM % 9000 + 1000))"
            else
                nekobox_url="hysteria2://$new_password@$current_domain:$new_port/?insecure=0&sni=$current_domain#Hysteria2-$((RANDOM % 9000 + 1000))"
            fi
            echo "$nekobox_url"
            echo ""
            exit 0
            ;;
        3)
            # Update
            update_hysteria
            exit 0
            ;;
        4)
            # Uninstall
            systemctl stop hysteria-server
            systemctl disable hysteria-server > /dev/null 2>&1
            rm -rf /etc/hysteria
            rm -f /usr/local/bin/hysteria
            rm -f /etc/systemd/system/hysteria-server.service
            rm -f /etc/systemd/system/hysteria-server@.service
            rm -rf /etc/systemd/system/hysteria-server.service.d
            systemctl daemon-reload
            echo "Hysteria uninstalled successfully!"
            echo ""
            exit 0
            ;;
        5)
            # Show current link
            current_port=$(grep -oP 'listen: :\K\d+' /etc/hysteria/config.yaml || echo "443")
            current_password=$(awk '/^auth:/{f=1; next} f && /^[^ ]/{f=0} f && /password:/{print $2; exit}' /etc/hysteria/config.yaml)
            current_domain=$(grep -oP 'cert: .*/live/\K[^/]+' /etc/hysteria/config.yaml || echo "example.com")
            current_obfs_password=$(awk '/^obfs:/{f=1; next} f && /^[^ ]/{f=0} f && /password:/{print $2; exit}' /etc/hysteria/config.yaml)

            echo ""
            echo "v2rayN client config:"
            v2rayN_config="server: $current_domain:$current_port
auth: $current_password
tls:
  sni: $current_domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
            if [ -n "$current_obfs_password" ]; then
                v2rayN_config="server: $current_domain:$current_port
auth: $current_password
obfs:
  type: salamander
  salamander:
    password: $current_obfs_password
tls:
  sni: $current_domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
            fi
            echo "$v2rayN_config"
            echo ""

            echo "NekoBox/NekoRay URL:"
            if [ -n "$current_obfs_password" ]; then
                nekobox_url="hysteria2://$current_password@$current_domain:$current_port/?insecure=0&sni=$current_domain&obfs=salamander&obfs-password=$current_obfs_password#Hysteria2-$((RANDOM % 9000 + 1000))"
            else
                nekobox_url="hysteria2://$current_password@$current_domain:$current_port/?insecure=0&sni=$current_domain#Hysteria2-$((RANDOM % 9000 + 1000))"
            fi
            echo "$nekobox_url"
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

# Step 1: Install Hysteria using official script
echo "Installing Hysteria..."
bash <(curl -fsSL https://get.hy2.sh/) > /dev/null 2>&1

# Step 2: Certbot domain setup
echo ""
echo "Hysteria requires a valid SSL certificate."
echo "Ensure your domain's DNS A record points to this server's IP address."
echo "Also ensure Port 80 is open to obtain the Let's Encrypt certificate if you don't already have one."
read -r -p "Enter your domain name (e.g., vpn.example.com): " domain
if [ -z "$domain" ]; then
    echo "Domain is required. Exiting."
    exit 1
fi

# Check for existing certificates in common locations dynamically
cert_path=""
key_path=""

echo "Searching for existing certificates for $domain..."

# Explicit paths where cert and key might be in different directories or named exactly as the domain
explicit_certs=(
    "/etc/letsencrypt/live/$domain/fullchain.pem"
    "/etc/ssl/certs/$domain.crt"
    "/etc/ssl/certs/$domain.pem"
    "/etc/nginx/ssl/$domain.crt"
    "/root/cert/$domain.crt"
    "/root/certs/$domain.crt"
    "/root/cert/$domain/fullchain.pem"
)
explicit_keys=(
    "/etc/letsencrypt/live/$domain/privkey.pem"
    "/etc/ssl/private/$domain.key"
    "/etc/ssl/private/$domain.key"
    "/etc/nginx/ssl/$domain.key"
    "/root/cert/$domain.key"
    "/root/certs/$domain.key"
    "/root/cert/$domain/privkey.pem"
)

for i in "${!explicit_certs[@]}"; do
    if [ -f "${explicit_certs[$i]}" ] && [ -f "${explicit_keys[$i]}" ]; then
        cert_path="${explicit_certs[$i]}"
        key_path="${explicit_keys[$i]}"
        break
    fi
done

# If not found in explicit paths, search dynamically for a directory matching the domain
if [ -z "$cert_path" ] || [ -z "$key_path" ]; then
    # find directories up to 5 levels deep in common root locations
    search_dirs=$(find /etc /root /home -maxdepth 5 -type d \( -name "$domain" -o -name "${domain}_ecc" \) 2>/dev/null)
    
    for dir in $search_dirs; do
        possible_c=( "fullchain.pem" "fullchain.cer" "$domain.cer" "$domain.crt" "cert.pem" "cert.crt" )
        possible_k=( "privkey.pem" "$domain.key" "private.key" "key.pem" "cert.key" )
        
        found_c=""
        found_k=""
        
        for c in "${possible_c[@]}"; do
            if [ -f "$dir/$c" ]; then
                found_c="$dir/$c"
                break
            fi
        done
        
        for k in "${possible_k[@]}"; do
            if [ -f "$dir/$k" ]; then
                found_k="$dir/$k"
                break
            fi
        done
        
        if [ -n "$found_c" ] && [ -n "$found_k" ]; then
            cert_path="$found_c"
            key_path="$found_k"
            break
        fi
    done
fi

if [ -n "$cert_path" ] && [ -n "$key_path" ]; then
    echo "Found existing certificate for $domain at $cert_path"
else
    echo "No existing certificate found. Proceeding to generate one..."
    read -r -p "Enter your email address for Let's Encrypt renewal notices (optional, press enter to skip): " email
    if [ -z "$email" ]; then
        certbot_email_args=("--register-unsafely-without-email")
    else
        certbot_email_args=("-m" "$email")
    fi

    # Obtain certificate
    echo "Running Certbot to obtain certificates..."
    certbot certonly --standalone -d "$domain" --agree-tos "${certbot_email_args[@]}" --non-interactive

    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/$domain/privkey.pem" ]; then
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    else
        echo "Certificate generation failed! Please check if your domain points to this IP and port 80 is open."
        exit 1
    fi
fi

# Step 3: Prompt user for input
echo ""
read -r -p "Enter a port (or press enter for a random port): " port
[ -z "$port" ] && port=$((RANDOM + 10000))

echo ""
read -r -p "Enter a password (or press enter for a random password): " password
[ -z "$password" ] && password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)

# Step 3.5: Obfuscation (Salamander)
echo ""
read -r -p "Enable Salamander obfuscation? (y/n, default: n): " enable_obfs
obfs_password=""
if [ "$enable_obfs" = "y" ] || [ "$enable_obfs" = "Y" ]; then
    read -r -p "Enter an obfs password (or press enter for a random one): " obfs_password
    [ -z "$obfs_password" ] && obfs_password=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
fi

# Step 3.6: Outbound Routing Mode
echo ""
echo "Select outbound routing mode:"
echo "1) Default (Dual-stack auto)"
echo "2) Prefer IPv4 (Recommended for VPS with broken/slow IPv6) [Default]"
echo "3) Force IPv4 only"
read -r -p "Enter choice [1-3, default: 2]: " route_choice
[ -z "$route_choice" ] && route_choice="2"

resolver_yaml=""
outbounds_yaml=""

if [ "$route_choice" = "2" ]; then
    resolver_yaml="
resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53"
    outbounds_yaml="
outbounds:
  - name: direct
    type: direct
    direct:
      mode: 46"
elif [ "$route_choice" = "3" ]; then
    resolver_yaml="
resolver:
  type: udp
  udp:
    addr: 1.1.1.1:53"
    outbounds_yaml="
outbounds:
  - name: direct
    type: direct
    direct:
      mode: 4"
fi

# Step 4: Create configuration
mkdir -p /etc/hysteria
config_yaml="listen: :$port
tls:
  cert: $cert_path
  key: $key_path
auth:
  type: password
  password: $password"

if [ -n "$obfs_password" ]; then
    config_yaml="$config_yaml
obfs:
  type: salamander
  salamander:
    password: $obfs_password"
fi

config_yaml="$config_yaml$resolver_yaml$outbounds_yaml"

echo "$config_yaml" > /etc/hysteria/config.yaml

# Step 5: Override systemd user to root to access certs
echo "Configuring systemd service..."
mkdir -p /etc/systemd/system/hysteria-server.service.d/
cat > /etc/systemd/system/hysteria-server.service.d/override.conf <<EOL
[Service]
User=root
Group=root
EOL

systemctl daemon-reload
systemctl enable hysteria-server > /dev/null 2>&1
systemctl restart hysteria-server

# Step 6: Generate and print client config files
echo ""
echo "======================================"
echo "Hysteria 2 Installation Complete!"
echo "======================================"
echo ""
echo "v2rayN client config:"
echo ""
v2rayN_config="server: $domain:$port
auth: $password
tls:
  sni: $domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
if [ -n "$obfs_password" ]; then
    v2rayN_config="server: $domain:$port
auth: $password
obfs:
  type: salamander
  salamander:
    password: $obfs_password
tls:
  sni: $domain
  insecure: false
fastOpen: true
socks5:
  listen: 127.0.0.1:10808
http:
  listen: 127.0.0.1:10809"
fi
echo "$v2rayN_config"
echo ""
echo "NekoBox/NekoRay URL:"
echo ""
if [ -n "$obfs_password" ]; then
    nekobox_url="hysteria2://$password@$domain:$port/?insecure=0&sni=$domain&obfs=salamander&obfs-password=$obfs_password#Hysteria2-$((RANDOM % 9000 + 1000))"
else
    nekobox_url="hysteria2://$password@$domain:$port/?insecure=0&sni=$domain#Hysteria2-$((RANDOM % 9000 + 1000))"
fi
echo "$nekobox_url"
echo ""
