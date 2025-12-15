#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - PocketID IDP Configuration
# =============================================================================
# Configuration functions specific to PocketID identity provider
# =============================================================================

# -----------------------------------------------------------------------------
# Collect PocketID Configuration (Existing Instance)
# -----------------------------------------------------------------------------

collect_pocketid_existing_config() {
    echo ""
    print_info "Configure your existing PocketID instance for NetBird."
    echo ""
    print_info "You'll need:"
    print_info "  - PocketID URL (e.g., https://auth.yourdomain.com)"
    print_info "  - OIDC Client ID"
    print_info "  - API Token for management"
    echo ""

    # PocketID URL
    while true; do
        prompt_input "Enter your PocketID URL" "" "IDP_URL"
        if [[ -n "$IDP_URL" ]]; then
            IDP_URL="${IDP_URL%/}"  # Remove trailing slash
            break
        fi
        print_error "PocketID URL is required"
    done

    # OIDC Client ID
    while true; do
        prompt_input "Enter your OIDC Client ID" "" "IDP_CLIENT_ID"
        if [[ -n "$IDP_CLIENT_ID" ]]; then
            break
        fi
        print_error "Client ID is required"
    done

    # API Token
    while true; do
        prompt_secret "Enter your PocketID API Token" "IDP_API_TOKEN"
        if [[ -n "$IDP_API_TOKEN" ]]; then
            break
        fi
        print_error "API Token is required"
    done

    # Build OIDC endpoint
    IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
    IDP_MGMT_ENDPOINT="${IDP_URL}"
}

# -----------------------------------------------------------------------------
# Collect PocketID Configuration (Deploy New Instance)
# -----------------------------------------------------------------------------

collect_pocketid_deploy_config() {
    echo ""
    print_info "PocketID will be deployed as part of this stack."
    print_info "PocketID is lightweight and easy to configure."
    echo ""

    while true; do
        prompt_input "Enter domain for PocketID (e.g., auth.yourdomain.com)" "" "IDP_DOMAIN"
        if validate_domain "$IDP_DOMAIN"; then
            break
        fi
        print_error "Please enter a valid domain name"
    done

    IDP_URL="https://${IDP_DOMAIN}"
    IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
    IDP_MGMT_ENDPOINT="${IDP_URL}"

    # Generate placeholder values - user will configure after deployment
    IDP_CLIENT_ID="pending-pocketid-setup"
    IDP_API_TOKEN="pending-pocketid-setup"

    echo ""
    print_warning "After deployment, you'll need to:"
    print_info "  1. Access PocketID at ${IDP_URL}"
    print_info "  2. Complete the initial setup wizard"
    print_info "  3. Create an OIDC Client for NetBird"
    print_info "  4. Create an API Key for management"
    print_info "  5. Run './setup.sh --update-credentials' to update configuration"
    echo ""
}

# -----------------------------------------------------------------------------
# Generate PocketID Management.json Configuration
# -----------------------------------------------------------------------------

generate_pocketid_management_json() {
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
        "AuthIssuer": "${IDP_URL}",
        "AuthAudience": "${IDP_CLIENT_ID}",
        "OIDCConfigEndpoint": "${IDP_OIDC_ENDPOINT}"
    },
    "IdpManagerConfig": {
        "ManagerType": "pocketid",
        "ClientID": "netbird",
        "Extra": {
            "ManagementEndpoint": "${IDP_MGMT_ENDPOINT}",
            "ApiToken": "${IDP_API_TOKEN}"
        }
    },
    "DeviceAuthorizationFlow": {
        "Provider": "none"
    },
    "PKCEAuthorizationFlow": {
        "ProviderConfig": {
            "Audience": "${IDP_CLIENT_ID}",
            "ClientID": "${IDP_CLIENT_ID}",
            "Scope": "openid profile email groups offline_access",
            "RedirectURLs": ["http://localhost:53000", "http://localhost:54000"]
        }
    }
}
EOF
}

# -----------------------------------------------------------------------------
# Generate PocketID Dashboard.env
# -----------------------------------------------------------------------------

generate_pocketid_dashboard_env() {
    local netbird_domain="$1"

    cat << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: PocketID
# =============================================================================

# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://${netbird_domain}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://${netbird_domain}

# OIDC Configuration
AUTH_AUDIENCE=${IDP_CLIENT_ID}
AUTH_CLIENT_ID=${IDP_CLIENT_ID}
AUTH_AUTHORITY=${IDP_URL}
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
}

# -----------------------------------------------------------------------------
# Get PocketID-specific management command flags
# -----------------------------------------------------------------------------

get_pocketid_mgmt_flags() {
    echo "--idp-sign-key-refresh-enabled"
}

# -----------------------------------------------------------------------------
# Print PocketID Post-Installation Instructions
# -----------------------------------------------------------------------------

print_pocketid_post_install() {
    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo -e "${BOLD}1. Configure PocketID${NC}"
        echo ""
        echo "   Access PocketID: ${IDP_URL}"
        echo ""
        echo "   a. Complete the initial setup wizard"
        echo "   b. Create your admin account"
        echo ""
        echo "   c. Create OIDC Client:"
        echo "      - Go to Administration > OIDC Clients"
        echo "      - Name: NetBird"
        echo "      - Client Launch URL: https://${NETBIRD_DOMAIN}"
        echo "      - Callback URLs:"
        echo "        - http://localhost:53000"
        echo "        - https://${NETBIRD_DOMAIN}/auth"
        echo "        - https://${NETBIRD_DOMAIN}/silent-auth"
        echo "      - Logout Callback URL: https://${NETBIRD_DOMAIN}/"
        echo "      - Public Client: On"
        echo "      - PKCE: On"
        echo "      - Click Save and copy the Client ID"
        echo ""
        echo "   d. Create API Key:"
        echo "      - Go to Administration > API Keys"
        echo "      - Name: NetBird Management"
        echo "      - Set expiration date"
        echo "      - Click Save and copy the API Key"
        echo ""
        echo -e "${BOLD}2. Update Configuration${NC}"
        echo ""
        echo "   Run: ./setup.sh --update-credentials"
        echo "   Enter the Client ID and API Key"
        echo ""
    else
        echo -e "${BOLD}PocketID Configuration${NC}"
        echo ""
        echo "   Your existing PocketID instance is configured."
        echo "   Make sure the following are set in PocketID:"
        echo ""
        echo "   OIDC Client Callback URLs:"
        echo "     - http://localhost:53000"
        echo "     - https://${NETBIRD_DOMAIN}/auth"
        echo "     - https://${NETBIRD_DOMAIN}/silent-auth"
        echo ""
        echo "   Logout Callback URL: https://${NETBIRD_DOMAIN}/"
        echo ""
        echo "   Client Settings:"
        echo "     - Public Client: On"
        echo "     - PKCE: On"
        echo ""
    fi
}
