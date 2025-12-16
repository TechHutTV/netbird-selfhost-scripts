#!/bin/bash

# =============================================================================
# NetBird Self-Hosted with PocketID - Interactive Setup Script
# =============================================================================
# This script walks you through the complete setup process for deploying
# NetBird with PocketID as the identity provider.
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Color Configuration
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

print_banner() {
    echo -e "${CYAN}"
    echo "========================================================================"
    echo ""
    echo "       NetBird Self-Hosted with PocketID"
    echo "       Interactive Setup Script"
    echo ""
    echo "========================================================================"
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BLUE}------------------------------------------------------------------------${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}>${NC} $1"
}

print_info() {
    echo -e "${CYAN}i${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}x${NC} $1"
}

print_success() {
    echo -e "${GREEN}+${NC} $1"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    if [[ "$default" == "y" ]]; then
        prompt_text="$prompt [Y/n]: "
    else
        prompt_text="$prompt [y/N]: "
    fi

    echo -en "${MAGENTA}?${NC} $prompt_text"
    read -r response

    response=${response:-$default}
    [[ "$response" =~ ^[Yy]$ ]]
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local response

    if [[ -n "$default" ]]; then
        echo -en "${MAGENTA}?${NC} $prompt [${default}]: "
    else
        echo -en "${MAGENTA}?${NC} $prompt: "
    fi

    read -r response
    response=${response:-$default}

    eval "$var_name='$response'"
}

prompt_secret() {
    local prompt="$1"
    local var_name="$2"
    local response

    echo -en "${MAGENTA}?${NC} $prompt: "
    read -rs response
    echo ""

    eval "$var_name='$response'"
}

generate_secret() {
    openssl rand -base64 32 | tr -d '=+/' | cut -c1-32
}

# -----------------------------------------------------------------------------
# Package Manager Detection
# -----------------------------------------------------------------------------

detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="sudo apt-get install -y"
        PKG_UPDATE="sudo apt-get update"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="sudo dnf install -y"
        PKG_UPDATE="sudo dnf check-update || true"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="sudo yum install -y"
        PKG_UPDATE="sudo yum check-update || true"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="sudo pacman -S --noconfirm"
        PKG_UPDATE="sudo pacman -Sy"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
        PKG_INSTALL="sudo apk add"
        PKG_UPDATE="sudo apk update"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="sudo zypper install -y"
        PKG_UPDATE="sudo zypper refresh"
    else
        PKG_MANAGER=""
        PKG_INSTALL=""
        PKG_UPDATE=""
    fi
}

# -----------------------------------------------------------------------------
# Prerequisite Installation Functions
# -----------------------------------------------------------------------------

install_docker() {
    print_step "Installing Docker..."

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        # Install Docker using official script for Debian/Ubuntu
        print_info "Using Docker's official installation script..."
        curl -fsSL https://get.docker.com | sudo sh

        # Add current user to docker group
        if [[ -n "$USER" ]] && [[ "$USER" != "root" ]]; then
            sudo usermod -aG docker "$USER"
            print_warning "Added $USER to docker group. You may need to log out and back in."
        fi
    elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
        # Fedora/RHEL/CentOS
        sudo $PKG_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
        sudo $PKG_INSTALL dnf-plugins-core 2>/dev/null || sudo $PKG_INSTALL yum-utils
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker

        if [[ -n "$USER" ]] && [[ "$USER" != "root" ]]; then
            sudo usermod -aG docker "$USER"
        fi
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        # Arch Linux
        sudo $PKG_INSTALL docker docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker

        if [[ -n "$USER" ]] && [[ "$USER" != "root" ]]; then
            sudo usermod -aG docker "$USER"
        fi
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        # Alpine
        sudo $PKG_INSTALL docker docker-compose
        sudo rc-update add docker boot
        sudo service docker start
    elif [[ "$PKG_MANAGER" == "zypper" ]]; then
        # openSUSE
        sudo $PKG_INSTALL docker docker-compose
        sudo systemctl start docker
        sudo systemctl enable docker

        if [[ -n "$USER" ]] && [[ "$USER" != "root" ]]; then
            sudo usermod -aG docker "$USER"
        fi
    else
        print_error "Could not determine how to install Docker on this system."
        print_info "Please install Docker manually: https://docs.docker.com/engine/install/"
        return 1
    fi

    # Verify installation
    if command -v docker &> /dev/null; then
        print_success "Docker installed successfully"
        return 0
    else
        print_error "Docker installation failed"
        return 1
    fi
}

install_curl() {
    print_step "Installing curl..."

    if [[ -z "$PKG_MANAGER" ]]; then
        print_error "Could not determine package manager"
        return 1
    fi

    $PKG_UPDATE
    $PKG_INSTALL curl

    if command -v curl &> /dev/null; then
        print_success "curl installed successfully"
        return 0
    else
        print_error "curl installation failed"
        return 1
    fi
}

install_openssl() {
    print_step "Installing openssl..."

    if [[ -z "$PKG_MANAGER" ]]; then
        print_error "Could not determine package manager"
        return 1
    fi

    $PKG_UPDATE
    $PKG_INSTALL openssl

    if command -v openssl &> /dev/null; then
        print_success "openssl installed successfully"
        return 0
    else
        print_error "openssl installation failed"
        return 1
    fi
}

install_jq() {
    print_step "Installing jq..."

    if [[ -z "$PKG_MANAGER" ]]; then
        print_error "Could not determine package manager"
        return 1
    fi

    $PKG_UPDATE
    $PKG_INSTALL jq

    if command -v jq &> /dev/null; then
        print_success "jq installed successfully"
        return 0
    else
        print_error "jq installation failed"
        return 1
    fi
}

install_certbot() {
    print_step "Installing certbot..."

    if [[ -z "$PKG_MANAGER" ]]; then
        print_error "Could not determine package manager"
        return 1
    fi

    $PKG_UPDATE

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        $PKG_INSTALL certbot
    elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
        $PKG_INSTALL certbot
    elif [[ "$PKG_MANAGER" == "pacman" ]]; then
        $PKG_INSTALL certbot
    elif [[ "$PKG_MANAGER" == "apk" ]]; then
        $PKG_INSTALL certbot
    elif [[ "$PKG_MANAGER" == "zypper" ]]; then
        $PKG_INSTALL certbot
    fi

    if command -v certbot &> /dev/null; then
        print_success "certbot installed successfully"
        return 0
    else
        print_error "certbot installation failed"
        return 1
    fi
}

offer_install_prereq() {
    local prereq="$1"
    local install_func="install_$prereq"

    echo ""
    if prompt_yes_no "Would you like to install $prereq now?" "y"; then
        if $install_func; then
            return 0
        else
            return 1
        fi
    else
        print_info "Skipping $prereq installation"
        return 1
    fi
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

check_docker_compose() {
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        print_success "Docker Compose (plugin) is available"
        return 0
    elif command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        print_success "Docker Compose (standalone) is available"
        return 0
    else
        print_error "Docker Compose is not installed"
        return 1
    fi
}

validate_domain() {
    local domain="$1"

    # Basic domain validation
    if [[ -z "$domain" ]]; then
        return 1
    fi

    if [[ "$domain" == *"example.com"* ]]; then
        print_warning "You're using an example.com domain. Make sure to use your real domain."
        return 0
    fi

    # Check if domain resolves (optional - just a warning)
    if command -v dig &> /dev/null; then
        if ! dig +short "$domain" &> /dev/null; then
            print_warning "Could not resolve $domain - make sure DNS is configured"
        fi
    fi

    return 0
}

validate_email() {
    local email="$1"

    if [[ -z "$email" ]]; then
        return 1
    fi

    # Basic email validation
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    print_section "Checking Prerequisites"

    # Detect package manager first for potential installations
    detect_package_manager

    local all_good=true
    local missing_prereqs=()
    local docker_user_added=false

    # Check Docker
    if ! check_command "docker"; then
        missing_prereqs+=("docker")
        if [[ -n "$PKG_MANAGER" ]]; then
            if offer_install_prereq "docker"; then
                docker_user_added=true
            else
                all_good=false
            fi
        else
            all_good=false
        fi
    fi

    # Check Docker Compose
    if ! check_docker_compose; then
        # Docker Compose is usually installed with Docker now
        if command -v docker &> /dev/null; then
            print_warning "Docker is installed but Docker Compose is not available"
            print_info "Docker Compose should be installed with Docker. Try reinstalling Docker."
        fi
        all_good=false
    fi

    # Check curl
    if ! check_command "curl"; then
        if [[ -n "$PKG_MANAGER" ]]; then
            if ! offer_install_prereq "curl"; then
                all_good=false
            fi
        else
            all_good=false
        fi
    fi

    # Check openssl
    if ! check_command "openssl"; then
        if [[ -n "$PKG_MANAGER" ]]; then
            if ! offer_install_prereq "openssl"; then
                all_good=false
            fi
        else
            all_good=false
        fi
    fi

    # Check certbot
    if ! check_command "certbot"; then
        if [[ -n "$PKG_MANAGER" ]]; then
            if ! offer_install_prereq "certbot"; then
                print_warning "certbot not installed - SSL certificates will need manual setup"
            fi
        fi
    fi

    # jq is optional but helpful
    if ! check_command "jq"; then
        print_warning "jq is optional but recommended for JSON validation"
        if [[ -n "$PKG_MANAGER" ]]; then
            if prompt_yes_no "Would you like to install jq? (recommended)" "y"; then
                install_jq || print_warning "jq installation failed, continuing anyway"
            fi
        fi
    fi

    if [[ "$all_good" == "false" ]]; then
        echo ""
        print_error "Some required prerequisites are missing."
        echo ""
        if [[ -z "$PKG_MANAGER" ]]; then
            print_info "Could not detect your package manager for automatic installation."
            echo ""
        fi
        echo "Manual installation instructions:"
        echo "  Docker: https://docs.docker.com/engine/install/"
        echo "  curl: sudo apt install curl (Debian/Ubuntu) or equivalent"
        echo "  openssl: sudo apt install openssl (Debian/Ubuntu) or equivalent"
        echo "  certbot: sudo apt install certbot (Debian/Ubuntu) or equivalent"
        exit 1
    fi

    echo ""
    print_success "All prerequisites are met!"

    # Warn user if they were added to docker group
    if [[ "$docker_user_added" == "true" ]]; then
        echo ""
        print_warning "You were added to the docker group."
        print_warning "Please log out and back in for this to take effect, then run this script again."
        echo ""
        if ! prompt_yes_no "Continue anyway? (may require 'sudo' for docker commands)" "n"; then
            exit 0
        fi
    fi
}

# -----------------------------------------------------------------------------
# Configuration Collection
# -----------------------------------------------------------------------------

collect_configuration() {
    print_section "Configuration"

    # NetBird Domain
    echo -e "${BOLD}Domain Configuration${NC}"
    echo ""
    print_info "NetBird requires a domain name for secure HTTPS connections."
    print_info "Example: netbird.yourdomain.com"
    echo ""

    while true; do
        prompt_input "Enter your NetBird domain" "" "NETBIRD_DOMAIN"
        if validate_domain "$NETBIRD_DOMAIN"; then
            break
        fi
        print_error "Please enter a valid domain name"
    done

    echo ""

    # Let's Encrypt Email
    echo -e "${BOLD}SSL Certificate Configuration${NC}"
    echo ""
    print_info "An email address is required for Let's Encrypt SSL certificates."
    print_info "You'll receive expiration notices at this address."
    echo ""

    while true; do
        prompt_input "Enter your email for Let's Encrypt" "" "LETSENCRYPT_EMAIL"
        if validate_email "$LETSENCRYPT_EMAIL"; then
            break
        fi
        print_error "Please enter a valid email address"
    done

    echo ""

    # PocketID Configuration
    echo -e "${BOLD}PocketID Identity Provider${NC}"
    echo ""

    if prompt_yes_no "Do you have an existing PocketID instance?" "n"; then
        EXISTING_POCKETID=true
        print_info "You'll configure NetBird to use your existing PocketID instance."
        echo ""

        prompt_input "Enter your PocketID URL (e.g., https://auth.yourdomain.com)" "" "POCKETID_URL"

        # Remove trailing slash if present
        POCKETID_URL="${POCKETID_URL%/}"

        # Extract domain from URL
        POCKETID_DOMAIN=$(echo "$POCKETID_URL" | sed 's|https://||' | sed 's|http://||' | cut -d'/' -f1)

        echo ""
        print_info "You'll need to create an OIDC client and API key in PocketID."
        print_info "See the README for detailed instructions."
        echo ""

        prompt_input "Enter your PocketID OIDC Client ID" "" "POCKETID_CLIENT_ID"
        prompt_secret "Enter your PocketID API Token" "POCKETID_API_TOKEN"

    else
        EXISTING_POCKETID=false
        print_info "PocketID will be deployed as part of this stack."
        echo ""

        while true; do
            prompt_input "Enter domain for PocketID (e.g., auth.yourdomain.com)" "" "POCKETID_DOMAIN"
            if validate_domain "$POCKETID_DOMAIN"; then
                break
            fi
            print_error "Please enter a valid domain name"
        done

        POCKETID_URL="https://$POCKETID_DOMAIN"
        POCKETID_CLIENT_ID=""
        POCKETID_API_TOKEN=""

        print_info "You'll configure PocketID after the initial deployment."
    fi

    echo ""

    # Summary
    print_section "Configuration Summary"

    echo -e "  ${BOLD}NetBird Domain:${NC}      $NETBIRD_DOMAIN"
    echo -e "  ${BOLD}PocketID Domain:${NC}     $POCKETID_DOMAIN"
    echo -e "  ${BOLD}PocketID URL:${NC}        $POCKETID_URL"
    echo -e "  ${BOLD}Let's Encrypt Email:${NC} $LETSENCRYPT_EMAIL"
    if [[ "$EXISTING_POCKETID" == "true" ]]; then
        echo -e "  ${BOLD}PocketID:${NC}            Using existing instance"
        echo -e "  ${BOLD}Client ID:${NC}           $POCKETID_CLIENT_ID"
        echo -e "  ${BOLD}API Token:${NC}           ********"
    else
        echo -e "  ${BOLD}PocketID:${NC}            Will be deployed"
    fi
    echo -e "  ${BOLD}Reverse Proxy:${NC}       NGINX with automatic SSL"

    echo ""

    if ! prompt_yes_no "Does this look correct?" "y"; then
        print_info "Let's start over..."
        collect_configuration
    fi
}

# -----------------------------------------------------------------------------
# Generate Secrets
# -----------------------------------------------------------------------------

generate_secrets() {
    print_section "Generating Secrets"

    print_step "Generating TURN password..."
    TURN_PASSWORD=$(generate_secret)
    print_success "TURN password generated"

    print_step "Generating relay auth secret..."
    RELAY_AUTH_SECRET=$(generate_secret)
    print_success "Relay auth secret generated"

    echo ""
    print_success "All secrets generated securely!"
}

# -----------------------------------------------------------------------------
# Generate NGINX Configuration
# -----------------------------------------------------------------------------

generate_nginx_config() {
    print_section "Generating NGINX Configuration"

    # Create nginx directories
    print_step "Creating nginx configuration directories..."
    mkdir -p nginx

    # Note: The nginx site configuration uses a template file (nginx/netbird.conf.template)
    # which is processed by Docker's nginx envsubst feature at container startup.
    # This allows dynamic domain substitution without rebuilding.
    print_step "Verifying nginx site configuration template exists..."

    if [[ ! -f "nginx/netbird.conf.template" ]]; then
        print_error "nginx/netbird.conf.template not found!"
        print_info "Please ensure the template file exists in the nginx directory."
        exit 1
    fi

    print_success "nginx site configuration template verified"

    # Generate a backup/reference config with actual values for debugging
    # This file is NOT used by the Docker container - it's for reference only
    print_step "Creating reference configuration (for debugging)..."
    mkdir -p nginx/conf.d

    cat > nginx/conf.d/netbird.conf.reference << EOF
# =============================================================================
# NetBird NGINX Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# =============================================================================

# Upstream definitions
upstream dashboard {
    server dashboard:80;
}

upstream management_http {
    server management:80;
}

upstream management_grpc {
    server management:80;
}

upstream signal_grpc {
    server signal:80;
}

upstream relay {
    server relay:33080;
}

upstream pocketid {
    server pocketid:1411;
}

# HTTP -> HTTPS redirect for NetBird domain
server {
    listen 80;
    listen [::]:80;
    server_name $NETBIRD_DOMAIN;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTP -> HTTPS redirect for PocketID domain
server {
    listen 80;
    listen [::]:80;
    server_name $POCKETID_DOMAIN;

    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# =============================================================================
# NetBird Main Domain - HTTPS
# =============================================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $NETBIRD_DOMAIN;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$NETBIRD_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$NETBIRD_DOMAIN/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # -------------------------------------------------------------------------
    # Signal Server - gRPC
    # -------------------------------------------------------------------------
    location /signalexchange.SignalExchange/ {
        grpc_pass grpc://signal_grpc;
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto \$scheme;

        # gRPC timeouts
        grpc_read_timeout 3600s;
        grpc_send_timeout 3600s;
    }

    # -------------------------------------------------------------------------
    # Signal Server - WebSocket Proxy (for browser clients)
    # -------------------------------------------------------------------------
    location /ws-proxy/signal {
        proxy_pass http://signal_grpc/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # -------------------------------------------------------------------------
    # Management Server - gRPC
    # -------------------------------------------------------------------------
    location /management.ManagementService/ {
        grpc_pass grpc://management_grpc;
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_set_header X-Forwarded-Proto \$scheme;

        # gRPC timeouts
        grpc_read_timeout 3600s;
        grpc_send_timeout 3600s;
    }

    # -------------------------------------------------------------------------
    # Management Server - WebSocket Proxy (for browser clients)
    # -------------------------------------------------------------------------
    location /ws-proxy/management {
        proxy_pass http://management_http/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # -------------------------------------------------------------------------
    # Management Server - HTTP API
    # -------------------------------------------------------------------------
    location /api {
        proxy_pass http://management_http;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Disable buffering for streaming
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # -------------------------------------------------------------------------
    # Relay Server - WebSocket
    # -------------------------------------------------------------------------
    location /relay {
        proxy_pass http://relay;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket timeouts
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # -------------------------------------------------------------------------
    # Dashboard - Default location
    # -------------------------------------------------------------------------
    location / {
        proxy_pass http://dashboard;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

# =============================================================================
# PocketID Domain - HTTPS
# =============================================================================
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $POCKETID_DOMAIN;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$POCKETID_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$POCKETID_DOMAIN/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Proxy all requests to PocketID
    location / {
        proxy_pass http://pocketid;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support (if needed)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    print_success "nginx reference configuration generated (nginx/conf.d/netbird.conf.reference)"
    print_info "Note: The actual config is generated from nginx/netbird.conf.template at container startup"

    # Copy main nginx.conf if it doesn't exist
    if [[ ! -f "nginx/nginx.conf" ]]; then
        print_step "Creating main nginx.conf..."
        cat > nginx/nginx.conf << 'EOF'
# =============================================================================
# NGINX Main Configuration for NetBird
# =============================================================================

user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    # Performance settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;

    # Client body size (for file uploads if needed)
    client_max_body_size 100M;

    # Include server configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF
        print_success "main nginx.conf created"
    fi

    echo ""
    print_success "NGINX configuration generated!"
}

# -----------------------------------------------------------------------------
# Obtain SSL Certificates
# -----------------------------------------------------------------------------

obtain_ssl_certificates() {
    print_section "Obtaining SSL Certificates"

    if ! command -v certbot &> /dev/null; then
        print_warning "certbot is not installed. Skipping automatic SSL certificate generation."
        print_info "You'll need to obtain SSL certificates manually before starting the services."
        return 1
    fi

    print_info "This will obtain SSL certificates from Let's Encrypt."
    print_info "Make sure your DNS records are properly configured and ports 80/443 are available."
    echo ""

    if ! prompt_yes_no "Obtain SSL certificates now?" "y"; then
        print_info "Skipping SSL certificate generation."
        print_info "You'll need to run: sudo certbot certonly --standalone -d $NETBIRD_DOMAIN -d $POCKETID_DOMAIN"
        return 0
    fi

    # Check if port 80 is available
    if lsof -i :80 &> /dev/null; then
        print_warning "Port 80 is in use. Stopping any services using it..."
        $DOCKER_COMPOSE_CMD down 2>/dev/null || true
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true
        sleep 2
    fi

    # Obtain certificates
    print_step "Obtaining certificate for $NETBIRD_DOMAIN..."
    if sudo certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$LETSENCRYPT_EMAIL" \
        --domain "$NETBIRD_DOMAIN"; then
        print_success "Certificate obtained for $NETBIRD_DOMAIN"
    else
        print_error "Failed to obtain certificate for $NETBIRD_DOMAIN"
        print_info "Make sure DNS is configured and port 80 is accessible"
        return 1
    fi

    # Only get PocketID cert if different domain
    if [[ "$POCKETID_DOMAIN" != "$NETBIRD_DOMAIN" ]]; then
        print_step "Obtaining certificate for $POCKETID_DOMAIN..."
        if sudo certbot certonly \
            --standalone \
            --non-interactive \
            --agree-tos \
            --email "$LETSENCRYPT_EMAIL" \
            --domain "$POCKETID_DOMAIN"; then
            print_success "Certificate obtained for $POCKETID_DOMAIN"
        else
            print_error "Failed to obtain certificate for $POCKETID_DOMAIN"
            print_info "Make sure DNS is configured and port 80 is accessible"
            return 1
        fi
    fi

    # Copy certificates to Docker-accessible location
    print_step "Setting up certificates for Docker..."

    # Create certificates directory
    mkdir -p certs

    # Copy certificates (using sudo since certbot creates root-owned files)
    sudo cp -rL /etc/letsencrypt/live certs/ 2>/dev/null || true
    sudo cp -rL /etc/letsencrypt/archive certs/ 2>/dev/null || true
    sudo chown -R $USER:$USER certs/ 2>/dev/null || true

    echo ""
    print_success "SSL certificates obtained successfully!"
}

# -----------------------------------------------------------------------------
# Update Configuration Files
# -----------------------------------------------------------------------------

update_configuration_files() {
    print_section "Updating Configuration Files"

    # Backup existing files if they have been modified
    for file in .env dashboard.env relay.env management.json turnserver.conf; do
        if [[ -f "$file" ]]; then
            if ! grep -q "example.com" "$file" 2>/dev/null; then
                print_warning "Backing up existing $file to $file.bak"
                cp "$file" "$file.bak"
            fi
        fi
    done

    # Update .env
    print_step "Updating .env..."
    cat > .env << EOF
# =============================================================================
# NetBird Self-Hosted with PocketID - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# =============================================================================

# Domain Configuration
NETBIRD_DOMAIN=$NETBIRD_DOMAIN
POCKETID_DOMAIN=$POCKETID_DOMAIN
POCKETID_URL=$POCKETID_URL
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL

# Secrets (auto-generated)
TURN_PASSWORD=$TURN_PASSWORD
RELAY_AUTH_SECRET=$RELAY_AUTH_SECRET

# Optional: MaxMind GeoIP Database
MAXMIND_LICENSE_KEY=
EOF
    print_success ".env updated"

    # Update dashboard.env
    print_step "Updating dashboard.env..."
    cat > dashboard.env << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# =============================================================================

# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://$NETBIRD_DOMAIN
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://$NETBIRD_DOMAIN

# OIDC Configuration
AUTH_AUDIENCE=${POCKETID_CLIENT_ID:-your-pocketid-client-id}
AUTH_CLIENT_ID=${POCKETID_CLIENT_ID:-your-pocketid-client-id}
AUTH_AUTHORITY=$POCKETID_URL
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email groups offline_access
AUTH_REDIRECT_URI=/auth
AUTH_SILENT_REDIRECT_URI=/silent-auth

# Token Configuration
NETBIRD_TOKEN_SOURCE=idToken

# SSL Configuration
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
EOF
    print_success "dashboard.env updated"

    # Update relay.env
    print_step "Updating relay.env..."
    cat > relay.env << EOF
# =============================================================================
# NetBird Relay Server - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# =============================================================================

# Logging
NB_LOG_LEVEL=info

# Relay Server Configuration
NB_LISTEN_ADDRESS=:80

# Exposed Address
NB_EXPOSED_ADDRESS=rels://$NETBIRD_DOMAIN:443/relay

# Authentication Secret
NB_AUTH_SECRET=$RELAY_AUTH_SECRET
EOF
    print_success "relay.env updated"

    # Update turnserver.conf
    print_step "Updating turnserver.conf..."
    cat > turnserver.conf << EOF
# =============================================================================
# Coturn TURN Server - Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# =============================================================================

# Listening ports
listening-port=3478
tls-listening-port=5349

# Port range for relay connections
min-port=49152
max-port=65535

# Enable fingerprint in TURN messages
fingerprint

# Long-term credential mechanism
lt-cred-mech

# TURN user credentials
user=netbird:$TURN_PASSWORD

# Realm
realm=$NETBIRD_DOMAIN

# Logging
log-file=stdout

# Additional settings
no-software-attribute
pidfile="/var/tmp/turnserver.pid"
no-cli
EOF
    print_success "turnserver.conf updated"

    # Update management.json
    print_step "Updating management.json..."
    cat > management.json << EOF
{
    "Stuns": [
        {
            "Proto": "udp",
            "URI": "stun:$NETBIRD_DOMAIN:3478"
        }
    ],
    "Relay": {
        "Addresses": ["rels://$NETBIRD_DOMAIN:443/relay"],
        "CredentialsTTL": "24h",
        "Secret": "$RELAY_AUTH_SECRET"
    },
    "Signal": {
        "Proto": "https",
        "URI": "$NETBIRD_DOMAIN:443"
    },
    "HttpConfig": {
        "AuthIssuer": "$POCKETID_URL",
        "AuthAudience": "${POCKETID_CLIENT_ID:-your-pocketid-client-id}",
        "OIDCConfigEndpoint": "$POCKETID_URL/.well-known/openid-configuration"
    },
    "IdpManagerConfig": {
        "ManagerType": "pocketid",
        "ClientID": "netbird",
        "Extra": {
            "ManagementEndpoint": "$POCKETID_URL",
            "ApiToken": "${POCKETID_API_TOKEN:-your-pocketid-api-token-here}"
        }
    },
    "DeviceAuthorizationFlow": {
        "Provider": "none"
    },
    "PKCEAuthorizationFlow": {
        "ProviderConfig": {
            "Audience": "${POCKETID_CLIENT_ID:-your-pocketid-client-id}",
            "ClientID": "${POCKETID_CLIENT_ID:-your-pocketid-client-id}",
            "Scope": "openid profile email groups offline_access",
            "RedirectURLs": ["http://localhost:53000", "http://localhost:54000"]
        }
    }
}
EOF
    print_success "management.json updated"

    # Handle existing PocketID
    if [[ "$EXISTING_POCKETID" == "true" ]]; then
        print_warning "Using external PocketID - you may want to remove the pocketid service from compose.yaml"
    fi

    echo ""
    print_success "All configuration files updated!"
}

# -----------------------------------------------------------------------------
# Update compose.yaml for SSL
# -----------------------------------------------------------------------------

update_compose_for_ssl() {
    print_section "Updating Docker Compose Configuration"

    # Check if certificates are in /etc/letsencrypt or local certs directory
    if [[ -d "/etc/letsencrypt/live/$NETBIRD_DOMAIN" ]]; then
        print_step "Updating compose.yaml to use system Let's Encrypt certificates..."

        # Update compose.yaml to mount /etc/letsencrypt
        sed -i 's|letsencrypt_certs:/etc/letsencrypt:ro|/etc/letsencrypt:/etc/letsencrypt:ro|g' compose.yaml
        print_success "compose.yaml updated to use /etc/letsencrypt"
    else
        print_info "Using Docker volume for certificates"
    fi
}

# -----------------------------------------------------------------------------
# Start Services
# -----------------------------------------------------------------------------

start_services() {
    print_section "Starting Services"

    if ! prompt_yes_no "Start the Docker services now?" "y"; then
        print_info "You can start the services later with: docker compose up -d"
        return
    fi

    print_step "Pulling Docker images..."
    $DOCKER_COMPOSE_CMD pull
    print_success "Images pulled"

    print_step "Starting services..."
    $DOCKER_COMPOSE_CMD up -d
    print_success "Services started"

    echo ""
    print_step "Waiting for services to be healthy..."
    sleep 5

    # Check service status
    echo ""
    $DOCKER_COMPOSE_CMD ps
}

# -----------------------------------------------------------------------------
# Print Next Steps
# -----------------------------------------------------------------------------

print_next_steps() {
    print_section "Next Steps"

    if [[ "$EXISTING_POCKETID" == "false" ]]; then
        echo -e "${BOLD}1. Configure PocketID${NC}"
        echo ""
        echo "   Access PocketID: $POCKETID_URL"
        echo "   Complete the initial setup wizard."
        echo ""
        echo "   Create OIDC Client:"
        echo "   - Name: NetBird"
        echo "   - Callback URLs:"
        echo "     - http://localhost:53000"
        echo "     - https://$NETBIRD_DOMAIN/auth"
        echo "     - https://$NETBIRD_DOMAIN/silent-auth"
        echo "   - Logout URL: https://$NETBIRD_DOMAIN/"
        echo "   - Public Client: On"
        echo "   - PKCE: On"
        echo ""
        echo "   Create API Key:"
        echo "   - Name: NetBird Management"
        echo ""
        echo -e "${BOLD}2. Update Configuration with PocketID Credentials${NC}"
        echo ""
        echo "   Run this script again with --update-pocketid flag, or manually update:"
        echo "   - dashboard.env: AUTH_CLIENT_ID and AUTH_AUDIENCE"
        echo "   - management.json: All client ID and API token references"
        echo ""
        echo "   Then restart: docker compose restart dashboard management"
        echo ""
    fi

    echo -e "${BOLD}Verify Installation${NC}"
    echo ""
    echo "   Dashboard: https://$NETBIRD_DOMAIN"
    echo "   Login with your PocketID credentials"
    echo ""

    echo -e "${BOLD}Connect Clients${NC}"
    echo ""
    echo "   netbird up --management-url https://$NETBIRD_DOMAIN"
    echo ""

    echo -e "${BOLD}SSL Certificate Renewal${NC}"
    echo ""
    echo "   Certificates will auto-renew via the certbot container."
    echo "   To manually renew: docker compose exec certbot certbot renew"
    echo ""

    echo -e "${BOLD}Troubleshooting${NC}"
    echo ""
    echo "   View logs: docker compose logs -f"
    echo "   Check status: docker compose ps"
    echo "   Restart: docker compose restart"
    echo ""

    print_success "Setup complete!"
}

# -----------------------------------------------------------------------------
# Update PocketID Credentials (for after initial setup)
# -----------------------------------------------------------------------------

update_pocketid_credentials() {
    print_section "Update PocketID Credentials"

    print_info "This will update the configuration files with your PocketID credentials."
    echo ""

    prompt_input "Enter your PocketID OIDC Client ID" "" "POCKETID_CLIENT_ID"
    prompt_secret "Enter your PocketID API Token" "POCKETID_API_TOKEN"

    if [[ -z "$POCKETID_CLIENT_ID" ]] || [[ -z "$POCKETID_API_TOKEN" ]]; then
        print_error "Both Client ID and API Token are required"
        exit 1
    fi

    # Read current domain from .env
    if [[ -f ".env" ]]; then
        source .env 2>/dev/null || true
    fi

    if [[ -z "$NETBIRD_DOMAIN" ]]; then
        prompt_input "Enter your NetBird domain" "" "NETBIRD_DOMAIN"
    fi

    if [[ -z "$POCKETID_URL" ]]; then
        prompt_input "Enter your PocketID URL" "" "POCKETID_URL"
    fi

    print_step "Updating dashboard.env..."
    sed -i "s|AUTH_AUDIENCE=.*|AUTH_AUDIENCE=$POCKETID_CLIENT_ID|g" dashboard.env
    sed -i "s|AUTH_CLIENT_ID=.*|AUTH_CLIENT_ID=$POCKETID_CLIENT_ID|g" dashboard.env
    print_success "dashboard.env updated"

    print_step "Updating management.json..."
    # Update management.json using sed (safer than jq for preserving formatting)
    sed -i "s|\"AuthAudience\": \"[^\"]*\"|\"AuthAudience\": \"$POCKETID_CLIENT_ID\"|g" management.json
    sed -i "s|\"ApiToken\": \"[^\"]*\"|\"ApiToken\": \"$POCKETID_API_TOKEN\"|g" management.json
    sed -i "s|\"Audience\": \"[^\"]*\"|\"Audience\": \"$POCKETID_CLIENT_ID\"|g" management.json
    sed -i "s|\"ClientID\": \"[^\"]*\"|\"ClientID\": \"$POCKETID_CLIENT_ID\"|g" management.json
    print_success "management.json updated"

    echo ""
    print_success "PocketID credentials updated!"
    echo ""

    if prompt_yes_no "Restart dashboard and management services?" "y"; then
        $DOCKER_COMPOSE_CMD restart dashboard management
        print_success "Services restarted"
    else
        print_info "Remember to restart services: docker compose restart dashboard management"
    fi
}

# -----------------------------------------------------------------------------
# Reset Configuration
# -----------------------------------------------------------------------------

reset_configuration() {
    print_section "Reset Configuration"

    print_warning "This will reset all configuration files to their default state."
    print_warning "All custom settings will be lost!"
    echo ""

    if ! prompt_yes_no "Are you sure you want to reset?" "n"; then
        print_info "Reset cancelled"
        exit 0
    fi

    # Stop services if running
    if $DOCKER_COMPOSE_CMD ps -q &> /dev/null; then
        print_step "Stopping services..."
        $DOCKER_COMPOSE_CMD down
    fi

    # Remove configuration files
    print_step "Removing configuration files..."
    rm -f .env dashboard.env relay.env management.json turnserver.conf
    rm -f .env.bak dashboard.env.bak relay.env.bak management.json.bak turnserver.conf.bak
    rm -rf nginx/conf.d

    # Restore from git if possible
    if command -v git &> /dev/null && [[ -d ".git" ]]; then
        print_step "Restoring default files from git..."
        git checkout -- .env dashboard.env relay.env management.json turnserver.conf 2>/dev/null || true
    fi

    print_success "Configuration reset complete!"
    print_info "Run ./setup.sh to reconfigure"
}

# -----------------------------------------------------------------------------
# Show Help
# -----------------------------------------------------------------------------

show_help() {
    echo "NetBird Self-Hosted with PocketID - Setup Script"
    echo ""
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h              Show this help message"
    echo "  --update-pocketid       Update PocketID client ID and API token"
    echo "  --reset                 Reset all configuration files"
    echo "  --check                 Check prerequisites only"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                      Run interactive setup"
    echo "  ./setup.sh --update-pocketid    Update PocketID credentials after initial setup"
    echo "  ./setup.sh --reset              Reset configuration to defaults"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Change to script directory
    cd "$(dirname "$0")"

    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --update-pocketid)
            print_banner
            check_prerequisites
            update_pocketid_credentials
            exit 0
            ;;
        --reset)
            print_banner
            reset_configuration
            exit 0
            ;;
        --check)
            print_banner
            check_prerequisites
            exit 0
            ;;
        "")
            # Normal setup
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac

    print_banner

    echo "Welcome! This script will help you set up NetBird with PocketID."
    echo ""
    echo "What you'll need:"
    echo "  - A domain name with DNS configured"
    echo "  - Docker and Docker Compose installed"
    echo "  - Ports 80, 443, 3478 (UDP), 49152-65535 (UDP) available"
    echo ""

    if ! prompt_yes_no "Ready to begin?" "y"; then
        echo ""
        print_info "Run this script again when you're ready!"
        exit 0
    fi

    check_prerequisites
    collect_configuration
    generate_secrets
    generate_nginx_config
    update_configuration_files
    obtain_ssl_certificates
    update_compose_for_ssl
    start_services
    print_next_steps
}

main "$@"
