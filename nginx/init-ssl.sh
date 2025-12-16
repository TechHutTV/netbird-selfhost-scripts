#!/bin/bash

# =============================================================================
# SSL Certificate Initialization Script
# =============================================================================
# This script obtains SSL certificates from Let's Encrypt using certbot
# for both the NetBird domain and PocketID domain.
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}▶${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✖${NC} $1"
}

print_success() {
    echo -e "${GREEN}✔${NC} $1"
}

# Check if running as root or with sudo
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo or as root"
        exit 1
    fi
}

# Load configuration from .env
load_config() {
    if [[ -f "../.env" ]]; then
        source "../.env"
    elif [[ -f ".env" ]]; then
        source ".env"
    else
        print_error "Could not find .env file"
        exit 1
    fi

    # Extract PocketID domain from URL
    if [[ -n "$POCKETID_URL" ]]; then
        POCKETID_DOMAIN=$(echo "$POCKETID_URL" | sed 's|https://||' | sed 's|http://||' | cut -d'/' -f1)
    fi

    if [[ -z "$NETBIRD_DOMAIN" ]] || [[ -z "$POCKETID_DOMAIN" ]] || [[ -z "$LETSENCRYPT_EMAIL" ]]; then
        print_error "Missing required configuration. Please ensure .env contains:"
        print_error "  NETBIRD_DOMAIN, POCKETID_URL, and LETSENCRYPT_EMAIL"
        exit 1
    fi
}

# Check if certbot is installed
check_certbot() {
    if ! command -v certbot &> /dev/null; then
        print_step "Installing certbot..."

        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y certbot
        elif command -v dnf &> /dev/null; then
            dnf install -y certbot
        elif command -v yum &> /dev/null; then
            yum install -y certbot
        else
            print_error "Could not install certbot. Please install it manually."
            exit 1
        fi
    fi
    print_success "certbot is installed"
}

# Stop nginx if running (to free port 80)
stop_nginx() {
    print_step "Stopping nginx if running..."
    docker stop nginx 2>/dev/null || true

    # Also stop any system nginx
    systemctl stop nginx 2>/dev/null || true
}

# Obtain certificate for a domain
obtain_cert() {
    local domain="$1"
    local email="$2"

    print_step "Obtaining certificate for $domain..."

    # Check if certificate already exists and is valid
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        if certbot certificates -d "$domain" 2>/dev/null | grep -q "VALID"; then
            print_success "Valid certificate already exists for $domain"
            return 0
        fi
    fi

    # Obtain new certificate using standalone mode
    certbot certonly \
        --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        --domain "$domain" \
        --preferred-challenges http \
        || {
            print_error "Failed to obtain certificate for $domain"
            return 1
        }

    print_success "Certificate obtained for $domain"
}

# Copy certificates to Docker volume
copy_to_docker_volume() {
    print_step "Copying certificates to Docker volume..."

    # Create a temporary container to access the volume
    docker run --rm \
        -v letsencrypt_certs:/etc/letsencrypt \
        -v /etc/letsencrypt:/host-certs:ro \
        alpine sh -c "cp -rL /host-certs/* /etc/letsencrypt/ 2>/dev/null || cp -r /host-certs/* /etc/letsencrypt/"

    print_success "Certificates copied to Docker volume"
}

# Main function
main() {
    echo ""
    echo "==========================================="
    echo "  SSL Certificate Initialization"
    echo "==========================================="
    echo ""

    check_root
    load_config
    check_certbot
    stop_nginx

    echo ""
    print_step "Domains to configure:"
    echo "  - NetBird: $NETBIRD_DOMAIN"
    echo "  - PocketID: $POCKETID_DOMAIN"
    echo "  - Email: $LETSENCRYPT_EMAIL"
    echo ""

    # Obtain certificates
    obtain_cert "$NETBIRD_DOMAIN" "$LETSENCRYPT_EMAIL"
    obtain_cert "$POCKETID_DOMAIN" "$LETSENCRYPT_EMAIL"

    # Copy to Docker volume
    copy_to_docker_volume

    echo ""
    print_success "SSL certificates initialized successfully!"
    echo ""
    echo "You can now start the services with: docker compose up -d"
    echo ""
}

main "$@"
