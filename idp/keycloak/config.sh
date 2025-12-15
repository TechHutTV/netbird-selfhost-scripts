#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - Keycloak IDP Configuration
# =============================================================================
# Configuration functions specific to Keycloak identity provider
# =============================================================================

# -----------------------------------------------------------------------------
# Collect Keycloak Configuration (Existing Instance)
# -----------------------------------------------------------------------------

collect_keycloak_existing_config() {
    echo ""
    print_info "Configure your existing Keycloak instance for NetBird."
    echo ""
    print_info "You'll need:"
    print_info "  - Keycloak URL (e.g., https://keycloak.yourdomain.com)"
    print_info "  - Realm name (default: netbird)"
    print_info "  - Frontend Client ID (for dashboard/CLI)"
    print_info "  - Backend Client ID and Secret (for management API)"
    echo ""

    # Keycloak URL
    while true; do
        prompt_input "Enter your Keycloak URL" "" "IDP_URL"
        if [[ -n "$IDP_URL" ]]; then
            IDP_URL="${IDP_URL%/}"  # Remove trailing slash
            break
        fi
        print_error "Keycloak URL is required"
    done

    # Realm name
    prompt_input "Enter Keycloak Realm name" "netbird" "KEYCLOAK_REALM"

    # Frontend Client ID
    while true; do
        prompt_input "Enter Frontend Client ID (for dashboard)" "netbird-client" "IDP_CLIENT_ID"
        if [[ -n "$IDP_CLIENT_ID" ]]; then
            break
        fi
        print_error "Frontend Client ID is required"
    done

    # Backend Client ID
    prompt_input "Enter Backend Client ID (for management)" "netbird-backend" "IDP_MGMT_CLIENT_ID"

    # Backend Client Secret
    while true; do
        prompt_secret "Enter Backend Client Secret" "IDP_MGMT_CLIENT_SECRET"
        if [[ -n "$IDP_MGMT_CLIENT_SECRET" ]]; then
            break
        fi
        print_error "Client Secret is required"
    done

    # Build OIDC and Admin endpoints
    IDP_OIDC_ENDPOINT="${IDP_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"
    IDP_ADMIN_ENDPOINT="${IDP_URL}/admin/realms/${KEYCLOAK_REALM}"
}

# -----------------------------------------------------------------------------
# Collect Keycloak Configuration (Deploy New Instance)
# -----------------------------------------------------------------------------

collect_keycloak_deploy_config() {
    echo ""
    print_info "Keycloak will be deployed as part of this stack."
    echo ""

    while true; do
        prompt_input "Enter domain for Keycloak (e.g., keycloak.yourdomain.com)" "" "IDP_DOMAIN"
        if validate_domain "$IDP_DOMAIN"; then
            break
        fi
        print_error "Please enter a valid domain name"
    done

    IDP_URL="https://${IDP_DOMAIN}"
    KEYCLOAK_REALM="netbird"
    IDP_OIDC_ENDPOINT="${IDP_URL}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration"
    IDP_ADMIN_ENDPOINT="${IDP_URL}/admin/realms/${KEYCLOAK_REALM}"

    # Generate placeholder values - user will configure after deployment
    IDP_CLIENT_ID="netbird-client"
    IDP_MGMT_CLIENT_ID="netbird-backend"
    IDP_MGMT_CLIENT_SECRET="pending-keycloak-setup"

    echo ""
    print_warning "After deployment, you'll need to:"
    print_info "  1. Access Keycloak at ${IDP_URL}"
    print_info "  2. Login with admin credentials (see .env for password)"
    print_info "  3. Create 'netbird' realm"
    print_info "  4. Create 'netbird-client' (frontend) and 'netbird-backend' clients"
    print_info "  5. Configure client scopes and audience mapper"
    print_info "  6. Run './setup.sh --update-credentials' to update configuration"
    echo ""
}

# -----------------------------------------------------------------------------
# Generate Keycloak Management.json Configuration
# -----------------------------------------------------------------------------

generate_keycloak_management_json() {
    local netbird_domain="$1"
    local relay_secret="$2"

    cat << EOF
{
    "Stuns": [
        {
            "Proto": "udp",
            "URI": "stun:${netbird_domain}:3478"
        }
    ],
    "Relay": {
        "Addresses": ["rels://${netbird_domain}:443/relay"],
        "CredentialsTTL": "24h",
        "Secret": "${relay_secret}"
    },
    "Signal": {
        "Proto": "https",
        "URI": "${netbird_domain}:443"
    },
    "HttpConfig": {
        "AuthIssuer": "${IDP_URL}/realms/${KEYCLOAK_REALM}",
        "AuthAudience": "${IDP_CLIENT_ID}",
        "OIDCConfigEndpoint": "${IDP_OIDC_ENDPOINT}"
    },
    "IdpManagerConfig": {
        "ManagerType": "keycloak",
        "ClientID": "${IDP_MGMT_CLIENT_ID}",
        "ClientSecret": "${IDP_MGMT_CLIENT_SECRET}",
        "GrantType": "client_credentials",
        "Extra": {
            "AdminEndpoint": "${IDP_ADMIN_ENDPOINT}"
        }
    },
    "DeviceAuthorizationFlow": {
        "Provider": "none"
    },
    "PKCEAuthorizationFlow": {
        "ProviderConfig": {
            "Audience": "${IDP_CLIENT_ID}",
            "ClientID": "${IDP_CLIENT_ID}",
            "Scope": "openid profile email offline_access api",
            "RedirectURLs": ["http://localhost:53000", "http://localhost:54000"]
        }
    }
}
EOF
}

# -----------------------------------------------------------------------------
# Generate Keycloak Dashboard.env
# -----------------------------------------------------------------------------

generate_keycloak_dashboard_env() {
    local netbird_domain="$1"

    cat << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: Keycloak
# =============================================================================

# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://${netbird_domain}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://${netbird_domain}

# OIDC Configuration
AUTH_AUDIENCE=${IDP_CLIENT_ID}
AUTH_CLIENT_ID=${IDP_CLIENT_ID}
AUTH_AUTHORITY=${IDP_URL}/realms/${KEYCLOAK_REALM}
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email offline_access api
AUTH_REDIRECT_URI=/auth
AUTH_SILENT_REDIRECT_URI=/silent-auth

# SSL Configuration
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
EOF
}

# -----------------------------------------------------------------------------
# Get Keycloak-specific management command flags
# -----------------------------------------------------------------------------

get_keycloak_mgmt_flags() {
    echo ""
}

# -----------------------------------------------------------------------------
# Print Keycloak Post-Installation Instructions
# -----------------------------------------------------------------------------

print_keycloak_post_install() {
    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo -e "${BOLD}1. Configure Keycloak${NC}"
        echo ""
        echo "   Access Keycloak: ${IDP_URL}"
        echo "   Admin credentials are in your .env file"
        echo ""
        echo "   a. Create Realm:"
        echo "      - Click dropdown in top-left (shows 'Master')"
        echo "      - Click 'Create Realm'"
        echo "      - Name: netbird"
        echo ""
        echo "   b. Create User:"
        echo "      - Go to Users > Create new user"
        echo "      - Set username and credentials"
        echo ""
        echo "   c. Create Frontend Client (netbird-client):"
        echo "      - Go to Clients > Create client"
        echo "      - Client ID: netbird-client"
        echo "      - Client type: OpenID Connect"
        echo "      - Enable: Standard flow, Device authorization grant"
        echo "      - Root URL: https://${NETBIRD_DOMAIN}/"
        echo "      - Valid redirect URIs: https://${NETBIRD_DOMAIN}/* and http://localhost:53000"
        echo "      - Web origins: +"
        echo ""
        echo "   d. Create Client Scope:"
        echo "      - Go to Client scopes > Create client scope"
        echo "      - Name: api, Type: Default"
        echo "      - Add Mapper > Audience"
        echo "      - Included Client Audience: netbird-client"
        echo "      - Add to access token: On"
        echo ""
        echo "   e. Add Scope to Client:"
        echo "      - Go to Clients > netbird-client > Client scopes"
        echo "      - Add client scope > api > Add as Default"
        echo ""
        echo "   f. Create Backend Client (netbird-backend):"
        echo "      - Client ID: netbird-backend"
        echo "      - Client authentication: On"
        echo "      - Service accounts roles: On"
        echo "      - Copy the Client Secret from Credentials tab"
        echo ""
        echo "   g. Grant Backend Permissions:"
        echo "      - Go to netbird-backend > Service account roles"
        echo "      - Assign role > Filter by clients > view-users"
        echo ""
        echo -e "${BOLD}2. Update Configuration${NC}"
        echo ""
        echo "   Run: ./setup.sh --update-credentials"
        echo "   Enter the Frontend Client ID and Backend Client Secret"
        echo ""
    else
        echo -e "${BOLD}Keycloak Configuration${NC}"
        echo ""
        echo "   Your existing Keycloak instance is configured."
        echo "   Make sure the following are set in Keycloak:"
        echo ""
        echo "   Frontend Client (${IDP_CLIENT_ID}):"
        echo "     - Valid redirect URIs:"
        echo "       - https://${NETBIRD_DOMAIN}/*"
        echo "       - http://localhost:53000"
        echo "     - Web origins: +"
        echo ""
        echo "   Backend Client (${IDP_MGMT_CLIENT_ID}):"
        echo "     - Service account enabled with view-users role"
        echo ""
        echo "   OIDC endpoint: ${IDP_OIDC_ENDPOINT}"
        echo ""
    fi
}
