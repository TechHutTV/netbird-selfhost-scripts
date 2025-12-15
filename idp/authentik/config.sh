#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - Authentik IDP Configuration
# =============================================================================
# Configuration functions specific to Authentik identity provider
# =============================================================================

# -----------------------------------------------------------------------------
# Collect Authentik Configuration (Existing Instance)
# -----------------------------------------------------------------------------

collect_authentik_existing_config() {
    echo ""
    print_info "Configure your existing Authentik instance for NetBird."
    echo ""
    print_info "You'll need:"
    print_info "  - Authentik URL (e.g., https://authentik.yourdomain.com)"
    print_info "  - OAuth2/OpenID Provider Client ID"
    print_info "  - Service Account username and app password"
    echo ""

    # Authentik URL
    while true; do
        prompt_input "Enter your Authentik URL" "" "IDP_URL"
        if [[ -n "$IDP_URL" ]]; then
            IDP_URL="${IDP_URL%/}"  # Remove trailing slash
            break
        fi
        print_error "Authentik URL is required"
    done

    # OIDC Client ID
    while true; do
        prompt_input "Enter your Provider Client ID" "" "IDP_CLIENT_ID"
        if [[ -n "$IDP_CLIENT_ID" ]]; then
            break
        fi
        print_error "Client ID is required"
    done

    # Service Account Username
    prompt_input "Enter Service Account Username" "Netbird" "IDP_MGMT_USERNAME"

    # Service Account App Password
    while true; do
        prompt_secret "Enter Service Account App Password" "IDP_MGMT_PASSWORD"
        if [[ -n "$IDP_MGMT_PASSWORD" ]]; then
            break
        fi
        print_error "App Password is required"
    done

    # Build OIDC endpoint
    IDP_OIDC_ENDPOINT="${IDP_URL}/application/o/netbird/.well-known/openid-configuration"
}

# -----------------------------------------------------------------------------
# Collect Authentik Configuration (Deploy New Instance)
# -----------------------------------------------------------------------------

collect_authentik_deploy_config() {
    echo ""
    print_info "Authentik will be deployed as part of this stack."
    print_info "Note: Authentik requires more resources than lighter IDPs."
    echo ""

    while true; do
        prompt_input "Enter domain for Authentik (e.g., authentik.yourdomain.com)" "" "IDP_DOMAIN"
        if validate_domain "$IDP_DOMAIN"; then
            break
        fi
        print_error "Please enter a valid domain name"
    done

    IDP_URL="https://${IDP_DOMAIN}"
    IDP_OIDC_ENDPOINT="${IDP_URL}/application/o/netbird/.well-known/openid-configuration"

    # Generate placeholder values - user will configure after deployment
    IDP_CLIENT_ID="pending-authentik-setup"
    IDP_MGMT_USERNAME="Netbird"
    IDP_MGMT_PASSWORD="pending-authentik-setup"

    echo ""
    print_warning "After deployment, you'll need to:"
    print_info "  1. Access Authentik at ${IDP_URL}"
    print_info "  2. Complete initial setup (check logs for bootstrap password)"
    print_info "  3. Create OAuth2/OpenID Provider named 'Netbird'"
    print_info "  4. Create Application for NetBird"
    print_info "  5. Create Service Account with admin group membership"
    print_info "  6. Create device code flow for CLI authentication"
    print_info "  7. Run './setup.sh --update-credentials' to update configuration"
    echo ""
}

# -----------------------------------------------------------------------------
# Generate Authentik Management.json Configuration
# -----------------------------------------------------------------------------

generate_authentik_management_json() {
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
        "ManagerType": "authentik",
        "ClientID": "${IDP_CLIENT_ID}",
        "Extra": {
            "Username": "${IDP_MGMT_USERNAME}",
            "Password": "${IDP_MGMT_PASSWORD}"
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
# Generate Authentik Dashboard.env
# -----------------------------------------------------------------------------

generate_authentik_dashboard_env() {
    local netbird_domain="$1"

    cat << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: Authentik
# =============================================================================

# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://${netbird_domain}
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://${netbird_domain}

# OIDC Configuration
AUTH_AUDIENCE=${IDP_CLIENT_ID}
AUTH_CLIENT_ID=${IDP_CLIENT_ID}
AUTH_AUTHORITY=${IDP_URL}
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email offline_access api
AUTH_REDIRECT_URI=/auth
AUTH_SILENT_REDIRECT_URI=/silent-auth

# Authentik-specific settings
# Disable prompt=login due to Authentik compatibility issue
# See: https://github.com/netbirdio/netbird/issues/3654
NETBIRD_AUTH_PKCE_DISABLE_PROMPT_LOGIN=true

# SSL Configuration
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
EOF
}

# -----------------------------------------------------------------------------
# Get Authentik-specific management command flags
# -----------------------------------------------------------------------------

get_authentik_mgmt_flags() {
    echo ""
}

# -----------------------------------------------------------------------------
# Print Authentik Post-Installation Instructions
# -----------------------------------------------------------------------------

print_authentik_post_install() {
    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo -e "${BOLD}1. Configure Authentik${NC}"
        echo ""
        echo "   Access Authentik: ${IDP_URL}"
        echo ""
        echo "   Get the bootstrap password:"
        echo "   docker compose logs authentik 2>&1 | grep -i password"
        echo ""
        echo "   a. Create OAuth2/OpenID Provider:"
        echo "      - Name: Netbird"
        echo "      - Authentication Flow: default-authentication-flow"
        echo "      - Authorization Flow: default-provider-authorization-explicit-consent"
        echo "      - Client type: Public"
        echo "      - Redirect URIs:"
        echo "        - Regex: https://${NETBIRD_DOMAIN}/.*"
        echo "        - Strict: http://localhost:53000"
        echo "      - Signing Key: Select any available certificate"
        echo ""
        echo "   b. Create Application:"
        echo "      - Name: Netbird"
        echo "      - Slug: netbird"
        echo "      - Provider: Netbird"
        echo ""
        echo "   c. Create Service Account:"
        echo "      - Username: Netbird"
        echo "      - Add to 'authentik Admins' group"
        echo "      - Create App Password in Directory > Tokens and App passwords"
        echo ""
        echo "   d. Create Device Code Flow:"
        echo "      - Go to Flows and Stages > Flows > Create"
        echo "      - Name: default-device-code-flow"
        echo "      - Designation: Stage Configuration"
        echo "      - Set as Device code flow in System > Brands"
        echo ""
        echo -e "${BOLD}2. Update Configuration${NC}"
        echo ""
        echo "   Run: ./setup.sh --update-credentials"
        echo "   Enter the Provider Client ID and Service Account credentials"
        echo ""
    else
        echo -e "${BOLD}Authentik Configuration${NC}"
        echo ""
        echo "   Your existing Authentik instance is configured."
        echo "   Make sure the following are set in Authentik:"
        echo ""
        echo "   Provider Redirect URIs:"
        echo "     - Regex: https://${NETBIRD_DOMAIN}/.*"
        echo "     - Strict: http://localhost:53000"
        echo ""
        echo "   Application slug must be: netbird"
        echo "   (OIDC endpoint: /application/o/netbird/.well-known/openid-configuration)"
        echo ""
    fi
}
