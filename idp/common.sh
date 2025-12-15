#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - Common IDP Functions
# =============================================================================
# Shared utility functions for all identity provider configurations
# =============================================================================

# -----------------------------------------------------------------------------
# IDP Registry
# -----------------------------------------------------------------------------

# Supported self-hosted IDPs
declare -A IDP_NAMES=(
    ["zitadel"]="Zitadel"
    ["authentik"]="Authentik"
    ["keycloak"]="Keycloak"
    ["pocketid"]="PocketID"
)

declare -A IDP_DESCRIPTIONS=(
    ["zitadel"]="Full-featured identity platform with device auth, SCIM, passkeys"
    ["authentik"]="Flexible, security-focused alternative to Okta/Auth0"
    ["keycloak"]="Popular enterprise IAM with extensive integrations"
    ["pocketid"]="Lightweight, simple identity management"
)

# IDP-specific OIDC endpoint patterns
declare -A IDP_OIDC_PATTERNS=(
    ["zitadel"]="/.well-known/openid-configuration"
    ["authentik"]="/application/o/netbird/.well-known/openid-configuration"
    ["keycloak"]="/realms/netbird/.well-known/openid-configuration"
    ["pocketid"]="/.well-known/openid-configuration"
)

# IDP-specific device auth provider settings
declare -A IDP_DEVICE_AUTH_PROVIDER=(
    ["zitadel"]="hosted"
    ["authentik"]=""
    ["keycloak"]=""
    ["pocketid"]="none"
)

# IDP-specific scopes
declare -A IDP_SCOPES=(
    ["zitadel"]="openid profile email offline_access api"
    ["authentik"]="openid profile email offline_access api"
    ["keycloak"]="openid profile email offline_access api"
    ["pocketid"]="openid profile email groups offline_access"
)

# IDP-specific token source
declare -A IDP_TOKEN_SOURCE=(
    ["zitadel"]=""
    ["authentik"]=""
    ["keycloak"]=""
    ["pocketid"]="idToken"
)

# -----------------------------------------------------------------------------
# IDP Selection Menu
# -----------------------------------------------------------------------------

show_idp_menu() {
    echo ""
    echo -e "${BOLD}Select your Identity Provider:${NC}"
    echo ""
    echo -e "  ${CYAN}Self-Hosted IDPs:${NC}"
    echo ""
    echo -e "    ${BOLD}1)${NC} Zitadel     - ${IDP_DESCRIPTIONS[zitadel]}"
    echo -e "    ${BOLD}2)${NC} Authentik   - ${IDP_DESCRIPTIONS[authentik]}"
    echo -e "    ${BOLD}3)${NC} Keycloak    - ${IDP_DESCRIPTIONS[keycloak]}"
    echo -e "    ${BOLD}4)${NC} PocketID    - ${IDP_DESCRIPTIONS[pocketid]}"
    echo ""
}

select_idp() {
    local choice
    while true; do
        show_idp_menu
        echo -en "${MAGENTA}?${NC} Enter your choice [1-4]: "
        read -r choice

        case "$choice" in
            1) SELECTED_IDP="zitadel"; break ;;
            2) SELECTED_IDP="authentik"; break ;;
            3) SELECTED_IDP="keycloak"; break ;;
            4) SELECTED_IDP="pocketid"; break ;;
            *)
                print_error "Invalid choice. Please enter 1-4."
                ;;
        esac
    done

    print_success "Selected: ${IDP_NAMES[$SELECTED_IDP]}"
}

# -----------------------------------------------------------------------------
# IDP Deployment Mode Selection
# -----------------------------------------------------------------------------

select_idp_mode() {
    local idp="$1"
    local idp_name="${IDP_NAMES[$idp]}"

    echo ""
    echo -e "${BOLD}${idp_name} Configuration${NC}"
    echo ""

    if prompt_yes_no "Do you have an existing ${idp_name} instance?" "n"; then
        IDP_MODE="existing"
        print_info "You'll configure NetBird to use your existing ${idp_name} instance."
    else
        IDP_MODE="deploy"
        print_info "${idp_name} will be deployed as part of this stack."
    fi
}

# -----------------------------------------------------------------------------
# Common OIDC Endpoint Builder
# -----------------------------------------------------------------------------

build_oidc_endpoint() {
    local idp="$1"
    local idp_url="$2"

    # Remove trailing slash from URL
    idp_url="${idp_url%/}"

    echo "${idp_url}${IDP_OIDC_PATTERNS[$idp]}"
}

# -----------------------------------------------------------------------------
# Management.json IdpManagerConfig Generators
# -----------------------------------------------------------------------------

generate_idp_manager_config_zitadel() {
    local client_id="$1"
    local client_secret="$2"
    local mgmt_endpoint="$3"

    cat << EOF
    "IdpManagerConfig": {
        "ManagerType": "zitadel",
        "ClientID": "${client_id}",
        "ClientSecret": "${client_secret}",
        "GrantType": "client_credentials",
        "Extra": {
            "ManagementEndpoint": "${mgmt_endpoint}"
        }
    }
EOF
}

generate_idp_manager_config_authentik() {
    local client_id="$1"
    local username="$2"
    local password="$3"

    cat << EOF
    "IdpManagerConfig": {
        "ManagerType": "authentik",
        "ClientID": "${client_id}",
        "Extra": {
            "Username": "${username}",
            "Password": "${password}"
        }
    }
EOF
}

generate_idp_manager_config_keycloak() {
    local client_id="$1"
    local client_secret="$2"
    local admin_endpoint="$3"

    cat << EOF
    "IdpManagerConfig": {
        "ManagerType": "keycloak",
        "ClientID": "${client_id}",
        "ClientSecret": "${client_secret}",
        "GrantType": "client_credentials",
        "Extra": {
            "AdminEndpoint": "${admin_endpoint}"
        }
    }
EOF
}

generate_idp_manager_config_pocketid() {
    local client_id="$1"
    local api_token="$2"
    local mgmt_endpoint="$3"

    cat << EOF
    "IdpManagerConfig": {
        "ManagerType": "pocketid",
        "ClientID": "${client_id}",
        "Extra": {
            "ManagementEndpoint": "${mgmt_endpoint}",
            "ApiToken": "${api_token}"
        }
    }
EOF
}

# -----------------------------------------------------------------------------
# Device Authorization Flow Generators
# -----------------------------------------------------------------------------

generate_device_auth_flow() {
    local idp="$1"
    local provider="${IDP_DEVICE_AUTH_PROVIDER[$idp]}"

    if [[ -n "$provider" ]]; then
        cat << EOF
    "DeviceAuthorizationFlow": {
        "Provider": "${provider}"
    }
EOF
    else
        cat << EOF
    "DeviceAuthorizationFlow": {
        "Provider": "none"
    }
EOF
    fi
}

# -----------------------------------------------------------------------------
# Dashboard.env Generator
# -----------------------------------------------------------------------------

generate_dashboard_env() {
    local idp="$1"
    local netbird_domain="$2"
    local idp_url="$3"
    local client_id="$4"

    local scopes="${IDP_SCOPES[$idp]}"
    local token_source="${IDP_TOKEN_SOURCE[$idp]}"

    cat << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: ${IDP_NAMES[$idp]}
# =============================================================================

# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://${netbird_domain}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://${netbird_domain}

# OIDC Configuration
AUTH_AUDIENCE=${client_id}
AUTH_CLIENT_ID=${client_id}
AUTH_AUTHORITY=${idp_url}
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=${scopes}
AUTH_REDIRECT_URI=/auth
AUTH_SILENT_REDIRECT_URI=/silent-auth
EOF

    # Add token source if needed (PocketID)
    if [[ -n "$token_source" ]]; then
        echo ""
        echo "# Token Configuration"
        echo "NETBIRD_TOKEN_SOURCE=${token_source}"
    fi

    cat << EOF

# SSL Configuration
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
EOF

    # Add Authentik-specific config
    if [[ "$idp" == "authentik" ]]; then
        echo ""
        echo "# Authentik-specific settings"
        echo "NETBIRD_AUTH_PKCE_DISABLE_PROMPT_LOGIN=true"
    fi
}

# -----------------------------------------------------------------------------
# Utility: Source IDP-specific configuration script
# -----------------------------------------------------------------------------

source_idp_config() {
    local idp="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local idp_config="${script_dir}/${idp}/config.sh"

    if [[ -f "$idp_config" ]]; then
        source "$idp_config"
    else
        print_error "IDP configuration script not found: $idp_config"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Utility: Get IDP compose file path
# -----------------------------------------------------------------------------

get_idp_compose_file() {
    local idp="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "${script_dir}/${idp}/compose.yaml"
}

# -----------------------------------------------------------------------------
# Utility: Check if IDP URL is reachable
# -----------------------------------------------------------------------------

check_idp_connectivity() {
    local idp_url="$1"
    local oidc_endpoint="$2"

    print_step "Checking IDP connectivity..."

    if curl -s --max-time 10 "${oidc_endpoint}" > /dev/null 2>&1; then
        print_success "IDP OIDC endpoint is reachable"
        return 0
    else
        print_warning "Could not reach OIDC endpoint: ${oidc_endpoint}"
        print_info "Make sure your IDP is running and accessible"
        return 1
    fi
}
