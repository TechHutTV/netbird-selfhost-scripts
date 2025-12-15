#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - Interactive Setup Script
# =============================================================================
# This script walks you through the complete setup process for deploying
# NetBird with your choice of identity provider.
#
# Supported IDPs:
#   - Zitadel     (Full-featured, device auth, recommended)
#   - Authentik   (Flexible, security-focused)
#   - Keycloak    (Popular enterprise IAM)
#   - PocketID    (Lightweight, simple)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Script Directory
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "==============================================================================="
    echo "                                                                               "
    echo "       ${BOLD}NetBird Self-Hosted${NC}${CYAN}                                                  "
    echo "       Interactive Setup Script                                                "
    echo "                                                                               "
    echo "==============================================================================="
    echo -e "${NC}"
}

print_section() {
    echo ""
    echo -e "${BLUE}-------------------------------------------------------------------------------${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BLUE}-------------------------------------------------------------------------------${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}>>>${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[x]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
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

    if [[ -z "$domain" ]]; then
        return 1
    fi

    if [[ "$domain" == *"example.com"* ]]; then
        print_warning "You're using an example.com domain. Make sure to use your real domain."
        return 0
    fi

    if command -v dig &> /dev/null; then
        if ! dig +short "$domain" &> /dev/null; then
            print_warning "Could not resolve $domain - make sure DNS is configured"
        fi
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Source IDP Common Functions
# -----------------------------------------------------------------------------

source "${SCRIPT_DIR}/idp/common.sh"

# -----------------------------------------------------------------------------
# Prerequisites Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    print_section "Checking Prerequisites"

    local all_good=true

    check_command "docker" || all_good=false
    check_docker_compose || all_good=false
    check_command "curl" || all_good=false
    check_command "openssl" || all_good=false

    if ! check_command "jq"; then
        print_warning "jq is optional but recommended for JSON validation"
    fi

    if [[ "$all_good" == "false" ]]; then
        echo ""
        print_error "Please install missing prerequisites and try again."
        echo ""
        echo "Install Docker: https://docs.docker.com/engine/install/"
        echo "Install curl: sudo apt install curl (Debian/Ubuntu)"
        echo "Install openssl: sudo apt install openssl (Debian/Ubuntu)"
        exit 1
    fi

    echo ""
    print_success "All prerequisites are met!"
}

# -----------------------------------------------------------------------------
# IDP Selection
# -----------------------------------------------------------------------------

select_identity_provider() {
    print_section "Identity Provider Selection"

    print_info "NetBird requires an OpenID Connect (OIDC) identity provider."
    print_info "Choose from the following self-hosted options:"

    select_idp  # From common.sh

    # Source IDP-specific configuration
    source "${SCRIPT_DIR}/idp/${SELECTED_IDP}/config.sh"

    # Ask about existing vs deploy
    select_idp_mode "$SELECTED_IDP"
}

# -----------------------------------------------------------------------------
# Configuration Collection
# -----------------------------------------------------------------------------

collect_configuration() {
    print_section "Domain Configuration"

    # NetBird Domain
    echo -e "${BOLD}NetBird Domain${NC}"
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

    # Collect IDP-specific configuration
    if [[ "$IDP_MODE" == "existing" ]]; then
        "collect_${SELECTED_IDP}_existing_config"
    else
        "collect_${SELECTED_IDP}_deploy_config"
    fi

    echo ""

    # NGINX Proxy Manager Configuration
    print_section "Reverse Proxy Configuration"

    if prompt_yes_no "Do you have an existing NGINX Proxy Manager instance?" "n"; then
        EXISTING_NPM=true
        DEPLOY_NPM=false
        print_info "You'll configure your existing NGINX Proxy Manager to proxy NetBird."
        print_warning "Make sure your NPM can reach the Docker network for this stack."
    else
        EXISTING_NPM=false
        if prompt_yes_no "Deploy NGINX Proxy Manager as part of this stack?" "y"; then
            DEPLOY_NPM=true
            print_info "NGINX Proxy Manager will be deployed on ports 80, 443, and 81 (admin)."
        else
            DEPLOY_NPM=false
            print_warning "You'll need to configure your own reverse proxy."
            print_info "See the README for proxy configuration requirements."
        fi
    fi

    # Display Summary
    display_configuration_summary
}

display_configuration_summary() {
    print_section "Configuration Summary"

    echo -e "  ${BOLD}NetBird Domain:${NC}      $NETBIRD_DOMAIN"
    echo -e "  ${BOLD}Identity Provider:${NC}   ${IDP_NAMES[$SELECTED_IDP]}"
    echo -e "  ${BOLD}IDP URL:${NC}             ${IDP_URL}"

    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo -e "  ${BOLD}IDP Deployment:${NC}      Will be deployed with stack"
    else
        echo -e "  ${BOLD}IDP Deployment:${NC}      Using existing instance"
    fi

    if [[ "$DEPLOY_NPM" == "true" ]]; then
        echo -e "  ${BOLD}NGINX Proxy Mgr:${NC}     Will be deployed"
    else
        echo -e "  ${BOLD}NGINX Proxy Mgr:${NC}     External/manual"
    fi

    echo ""

    if ! prompt_yes_no "Does this look correct?" "y"; then
        print_info "Let's start over..."
        select_identity_provider
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

    # Generate IDP-specific secrets if deploying
    if [[ "$IDP_MODE" == "deploy" ]]; then
        case "$SELECTED_IDP" in
            zitadel)
                print_step "Generating Zitadel secrets..."
                ZITADEL_DB_PASSWORD=$(generate_secret)
                ZITADEL_MASTERKEY=$(openssl rand -base64 32)
                ZITADEL_ADMIN_PASSWORD="Admin$(generate_secret | cut -c1-8)!"
                print_success "Zitadel secrets generated"
                ;;
            authentik)
                print_step "Generating Authentik secrets..."
                AUTHENTIK_DB_PASSWORD=$(generate_secret)
                AUTHENTIK_SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
                print_success "Authentik secrets generated"
                ;;
            keycloak)
                print_step "Generating Keycloak secrets..."
                KEYCLOAK_DB_PASSWORD=$(generate_secret)
                KEYCLOAK_ADMIN_PASSWORD="Admin$(generate_secret | cut -c1-8)!"
                print_success "Keycloak secrets generated"
                ;;
        esac
    fi

    echo ""
    print_success "All secrets generated securely!"
}

# -----------------------------------------------------------------------------
# Update Configuration Files
# -----------------------------------------------------------------------------

update_configuration_files() {
    print_section "Updating Configuration Files"

    # Backup existing files
    for file in .env dashboard.env relay.env management.json turnserver.conf; do
        if [[ -f "$file" ]]; then
            if ! grep -q "example.com" "$file" 2>/dev/null; then
                print_warning "Backing up existing $file to $file.bak"
                cp "$file" "$file.bak"
            fi
        fi
    done

    # Generate .env
    print_step "Generating .env..."
    generate_env_file
    print_success ".env generated"

    # Generate dashboard.env using IDP-specific function
    print_step "Generating dashboard.env..."
    "generate_${SELECTED_IDP}_dashboard_env" "$NETBIRD_DOMAIN" > dashboard.env
    print_success "dashboard.env generated"

    # Generate relay.env
    print_step "Generating relay.env..."
    generate_relay_env
    print_success "relay.env generated"

    # Generate turnserver.conf
    print_step "Generating turnserver.conf..."
    generate_turnserver_conf
    print_success "turnserver.conf generated"

    # Generate management.json using IDP-specific function
    print_step "Generating management.json..."
    "generate_${SELECTED_IDP}_management_json" "$NETBIRD_DOMAIN" "$RELAY_AUTH_SECRET" > management.json
    print_success "management.json generated"

    echo ""
    print_success "All configuration files generated!"
}

generate_env_file() {
    cat > .env << EOF
# =============================================================================
# NetBird Self-Hosted - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: ${IDP_NAMES[$SELECTED_IDP]}
# =============================================================================

# Domain Configuration
NETBIRD_DOMAIN=${NETBIRD_DOMAIN}

# Identity Provider
SELECTED_IDP=${SELECTED_IDP}
IDP_URL=${IDP_URL}
IDP_MODE=${IDP_MODE}
EOF

    # Add IDP-specific domain if deploying
    if [[ "$IDP_MODE" == "deploy" ]]; then
        case "$SELECTED_IDP" in
            pocketid)
                echo "POCKETID_URL=${IDP_URL}" >> .env
                ;;
            zitadel)
                echo "ZITADEL_DOMAIN=${IDP_DOMAIN}" >> .env
                echo "ZITADEL_DB_PASSWORD=${ZITADEL_DB_PASSWORD}" >> .env
                echo "ZITADEL_MASTERKEY=${ZITADEL_MASTERKEY}" >> .env
                echo "ZITADEL_ADMIN_PASSWORD=${ZITADEL_ADMIN_PASSWORD}" >> .env
                ;;
            authentik)
                echo "AUTHENTIK_DOMAIN=${IDP_DOMAIN}" >> .env
                echo "AUTHENTIK_DB_PASSWORD=${AUTHENTIK_DB_PASSWORD}" >> .env
                echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}" >> .env
                ;;
            keycloak)
                echo "KEYCLOAK_DOMAIN=${IDP_DOMAIN}" >> .env
                echo "KEYCLOAK_DB_PASSWORD=${KEYCLOAK_DB_PASSWORD}" >> .env
                echo "KEYCLOAK_ADMIN_USER=admin" >> .env
                echo "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}" >> .env
                ;;
        esac
    fi

    cat >> .env << EOF

# Secrets (auto-generated)
TURN_PASSWORD=${TURN_PASSWORD}
RELAY_AUTH_SECRET=${RELAY_AUTH_SECRET}

# Optional: MaxMind GeoIP Database
MAXMIND_LICENSE_KEY=
EOF
}

generate_relay_env() {
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
NB_EXPOSED_ADDRESS=rels://${NETBIRD_DOMAIN}:443/relay

# Authentication Secret
NB_AUTH_SECRET=${RELAY_AUTH_SECRET}
EOF
}

generate_turnserver_conf() {
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
user=netbird:${TURN_PASSWORD}

# Realm
realm=${NETBIRD_DOMAIN}

# Logging
log-file=stdout

# Additional settings
no-software-attribute
pidfile="/var/tmp/turnserver.pid"
no-cli
EOF
}

# -----------------------------------------------------------------------------
# Start Services
# -----------------------------------------------------------------------------

start_services() {
    print_section "Starting Services"

    if ! prompt_yes_no "Start the Docker services now?" "y"; then
        print_info "You can start the services later."
        print_start_commands
        return
    fi

    # Determine compose command based on IDP mode
    local compose_cmd="$DOCKER_COMPOSE_CMD"

    if [[ "$IDP_MODE" == "deploy" ]]; then
        local idp_compose="${SCRIPT_DIR}/idp/${SELECTED_IDP}/compose.yaml"
        if [[ -f "$idp_compose" ]]; then
            compose_cmd="$DOCKER_COMPOSE_CMD -f compose.yaml -f $idp_compose"
            print_info "Including ${IDP_NAMES[$SELECTED_IDP]} services"
        fi
    fi

    # Remove NPM service if not deploying
    if [[ "$DEPLOY_NPM" == "false" ]]; then
        print_warning "NGINX Proxy Manager not included - using external reverse proxy"
    fi

    # Create network first
    print_step "Creating Docker network..."
    docker network create netbird 2>/dev/null || true

    print_step "Pulling Docker images..."
    $compose_cmd pull
    print_success "Images pulled"

    print_step "Starting services..."
    $compose_cmd up -d
    print_success "Services started"

    echo ""
    print_step "Waiting for services to be healthy..."
    sleep 5

    echo ""
    $compose_cmd ps
}

print_start_commands() {
    echo ""
    print_info "To start services manually, run:"
    echo ""

    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo "  docker compose -f compose.yaml -f idp/${SELECTED_IDP}/compose.yaml up -d"
    else
        echo "  docker compose up -d"
    fi

    echo ""
}

# -----------------------------------------------------------------------------
# Print Next Steps
# -----------------------------------------------------------------------------

print_next_steps() {
    print_section "Next Steps"

    # NPM configuration
    if [[ "$DEPLOY_NPM" == "true" ]]; then
        echo -e "${BOLD}1. Configure NGINX Proxy Manager${NC}"
        echo ""
        echo "   Access NPM admin panel: http://YOUR_SERVER_IP:81"
        echo "   Default login: admin@example.com / changeme"
        echo ""
        echo "   Create proxy hosts for:"
        if [[ "$IDP_MODE" == "deploy" ]]; then
            echo "   - ${IDP_URL} -> ${SELECTED_IDP}:80"
        fi
        echo "   - https://${NETBIRD_DOMAIN} -> dashboard:80"
        echo ""
        echo "   See README.md for detailed NGINX configuration including"
        echo "   gRPC and WebSocket proxy settings."
        echo ""
    fi

    # IDP-specific instructions
    "print_${SELECTED_IDP}_post_install"

    # Verification
    echo -e "${BOLD}Verify Installation${NC}"
    echo ""
    echo "   Dashboard: https://${NETBIRD_DOMAIN}"
    echo "   Login with your ${IDP_NAMES[$SELECTED_IDP]} credentials"
    echo ""

    # Connect clients
    echo -e "${BOLD}Connect Clients${NC}"
    echo ""
    echo "   netbird up --management-url https://${NETBIRD_DOMAIN}"
    echo ""

    # Troubleshooting
    echo -e "${BOLD}Troubleshooting${NC}"
    echo ""
    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo "   View logs: docker compose -f compose.yaml -f idp/${SELECTED_IDP}/compose.yaml logs -f"
        echo "   Check status: docker compose -f compose.yaml -f idp/${SELECTED_IDP}/compose.yaml ps"
    else
        echo "   View logs: docker compose logs -f"
        echo "   Check status: docker compose ps"
    fi
    echo ""

    print_success "Setup complete!"
}

# -----------------------------------------------------------------------------
# Update Credentials (for after initial IDP setup)
# -----------------------------------------------------------------------------

update_credentials() {
    print_section "Update IDP Credentials"

    # Load current configuration
    if [[ -f ".env" ]]; then
        source .env 2>/dev/null || true
    fi

    if [[ -z "$SELECTED_IDP" ]]; then
        print_error "No IDP configuration found. Run ./setup.sh first."
        exit 1
    fi

    print_info "Current IDP: ${IDP_NAMES[$SELECTED_IDP]}"
    print_info "Updating credentials for ${IDP_NAMES[$SELECTED_IDP]}..."
    echo ""

    # Source IDP config and collect credentials
    source "${SCRIPT_DIR}/idp/${SELECTED_IDP}/config.sh"

    # Set IDP_URL from saved config
    if [[ -n "$IDP_URL" ]]; then
        print_info "IDP URL: $IDP_URL"
    fi

    # Collect new credentials based on IDP type
    case "$SELECTED_IDP" in
        zitadel)
            prompt_input "Enter OIDC Client ID" "" "IDP_CLIENT_ID"
            prompt_input "Enter Service User Client ID" "netbird" "IDP_MGMT_CLIENT_ID"
            prompt_secret "Enter Service User Client Secret" "IDP_MGMT_CLIENT_SECRET"
            IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
            IDP_MGMT_ENDPOINT="${IDP_URL}/management/v1"
            ;;
        authentik)
            prompt_input "Enter Provider Client ID" "" "IDP_CLIENT_ID"
            prompt_input "Enter Service Account Username" "Netbird" "IDP_MGMT_USERNAME"
            prompt_secret "Enter Service Account App Password" "IDP_MGMT_PASSWORD"
            IDP_OIDC_ENDPOINT="${IDP_URL}/application/o/netbird/.well-known/openid-configuration"
            ;;
        keycloak)
            prompt_input "Enter Realm name" "netbird" "KEYCLOAK_REALM"
            prompt_input "Enter Frontend Client ID" "netbird-client" "IDP_CLIENT_ID"
            prompt_input "Enter Backend Client ID" "netbird-backend" "IDP_MGMT_CLIENT_ID"
            prompt_secret "Enter Backend Client Secret" "IDP_MGMT_CLIENT_SECRET"
            IDP_OIDC_ENDPOINT="${IDP_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"
            IDP_ADMIN_ENDPOINT="${IDP_URL}/admin/realms/${KEYCLOAK_REALM}"
            ;;
        pocketid)
            prompt_input "Enter OIDC Client ID" "" "IDP_CLIENT_ID"
            prompt_secret "Enter API Token" "IDP_API_TOKEN"
            IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
            IDP_MGMT_ENDPOINT="${IDP_URL}"
            ;;
    esac

    if [[ -z "$NETBIRD_DOMAIN" ]]; then
        prompt_input "Enter your NetBird domain" "" "NETBIRD_DOMAIN"
    fi

    if [[ -z "$RELAY_AUTH_SECRET" ]]; then
        RELAY_AUTH_SECRET=$(generate_secret)
    fi

    # Regenerate configuration files
    print_step "Updating dashboard.env..."
    "generate_${SELECTED_IDP}_dashboard_env" "$NETBIRD_DOMAIN" > dashboard.env
    print_success "dashboard.env updated"

    print_step "Updating management.json..."
    "generate_${SELECTED_IDP}_management_json" "$NETBIRD_DOMAIN" "$RELAY_AUTH_SECRET" > management.json
    print_success "management.json updated"

    echo ""
    print_success "Credentials updated!"
    echo ""

    if prompt_yes_no "Restart dashboard and management services?" "y"; then
        if [[ "$IDP_MODE" == "deploy" ]]; then
            $DOCKER_COMPOSE_CMD -f compose.yaml -f "idp/${SELECTED_IDP}/compose.yaml" restart dashboard management
        else
            $DOCKER_COMPOSE_CMD restart dashboard management
        fi
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
        $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    fi

    # Remove configuration files
    print_step "Removing configuration files..."
    rm -f .env dashboard.env relay.env management.json turnserver.conf
    rm -f .env.bak dashboard.env.bak relay.env.bak management.json.bak turnserver.conf.bak

    print_success "Configuration reset complete!"
    print_info "Run ./setup.sh to reconfigure"
}

# -----------------------------------------------------------------------------
# Show Help
# -----------------------------------------------------------------------------

show_help() {
    echo "NetBird Self-Hosted - Setup Script"
    echo ""
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help, -h              Show this help message"
    echo "  --update-credentials    Update IDP client ID and credentials"
    echo "  --reset                 Reset all configuration files"
    echo "  --check                 Check prerequisites only"
    echo ""
    echo "Supported Identity Providers:"
    echo "  - Zitadel     (Full-featured, device auth, recommended)"
    echo "  - Authentik   (Flexible, security-focused)"
    echo "  - Keycloak    (Popular enterprise IAM)"
    echo "  - PocketID    (Lightweight, simple)"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                      Run interactive setup"
    echo "  ./setup.sh --update-credentials Update IDP credentials after initial setup"
    echo "  ./setup.sh --reset              Reset configuration to defaults"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    # Change to script directory
    cd "$SCRIPT_DIR"

    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --update-credentials)
            print_banner
            check_prerequisites
            update_credentials
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

    echo "Welcome! This script will help you set up NetBird with your choice of"
    echo "identity provider."
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
    select_identity_provider
    collect_configuration
    generate_secrets
    update_configuration_files
    start_services
    print_next_steps
}

main "$@"
