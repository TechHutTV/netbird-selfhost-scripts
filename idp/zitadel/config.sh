#!/bin/bash

# =============================================================================
# NetBird Self-Hosted - Zitadel IDP Configuration
# =============================================================================
# Configuration functions specific to Zitadel identity provider
# =============================================================================

# -----------------------------------------------------------------------------
# Collect Zitadel Configuration (Existing Instance)
# -----------------------------------------------------------------------------

collect_zitadel_existing_config() {
    echo ""
    print_info "Configure your existing Zitadel instance for NetBird."
    echo ""
    print_info "You'll need:"
    print_info "  - Zitadel URL (e.g., https://zitadel.yourdomain.com)"
    print_info "  - OIDC Client ID (from your Zitadel application)"
    print_info "  - Service User Client ID and Secret"
    echo ""

    # Zitadel URL
    while true; do
        prompt_input "Enter your Zitadel URL" "" "IDP_URL"
        if [[ -n "$IDP_URL" ]]; then
            IDP_URL="${IDP_URL%/}"  # Remove trailing slash
            break
        fi
        print_error "Zitadel URL is required"
    done

    # OIDC Client ID
    while true; do
        prompt_input "Enter your OIDC Client ID" "" "IDP_CLIENT_ID"
        if [[ -n "$IDP_CLIENT_ID" ]]; then
            break
        fi
        print_error "Client ID is required"
    done

    # Service User Client ID (for management API)
    prompt_input "Enter Service User Client ID" "netbird" "IDP_MGMT_CLIENT_ID"

    # Service User Client Secret
    while true; do
        prompt_secret "Enter Service User Client Secret" "IDP_MGMT_CLIENT_SECRET"
        if [[ -n "$IDP_MGMT_CLIENT_SECRET" ]]; then
            break
        fi
        print_error "Client Secret is required"
    done

    # Build OIDC and Management endpoints
    IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
    IDP_MGMT_ENDPOINT="${IDP_URL}/management/v1"
}

# -----------------------------------------------------------------------------
# Collect Zitadel Configuration (Deploy New Instance)
# -----------------------------------------------------------------------------

collect_zitadel_deploy_config() {
    echo ""
    print_info "Zitadel will be deployed as part of this stack."
    echo ""

    while true; do
        prompt_input "Enter domain for Zitadel (e.g., zitadel.yourdomain.com)" "" "IDP_DOMAIN"
        if validate_domain "$IDP_DOMAIN"; then
            break
        fi
        print_error "Please enter a valid domain name"
    done

    IDP_URL="https://${IDP_DOMAIN}"
    IDP_OIDC_ENDPOINT="${IDP_URL}/.well-known/openid-configuration"
    IDP_MGMT_ENDPOINT="${IDP_URL}/management/v1"

    # Generate placeholder values - user will configure after deployment
    IDP_CLIENT_ID="pending-zitadel-setup"
    IDP_MGMT_CLIENT_ID="netbird"
    IDP_MGMT_CLIENT_SECRET="pending-zitadel-setup"

    echo ""
    print_warning "After deployment, you'll need to:"
    print_info "  1. Access Zitadel at ${IDP_URL}"
    print_info "  2. Complete initial setup and create admin user"
    print_info "  3. Create a 'NETBIRD' project and 'netbird' application"
    print_info "  4. Create a service user with 'Org User Manager' role"
    print_info "  5. Run './setup.sh --update-credentials' to update configuration"
    echo ""
}

# -----------------------------------------------------------------------------
# Generate Zitadel Management.json Configuration
# -----------------------------------------------------------------------------

generate_zitadel_management_json() {
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
        "ManagerType": "zitadel",
        "ClientID": "${IDP_MGMT_CLIENT_ID}",
        "ClientSecret": "${IDP_MGMT_CLIENT_SECRET}",
        "GrantType": "client_credentials",
        "Extra": {
            "ManagementEndpoint": "${IDP_MGMT_ENDPOINT}"
        }
    },
    "DeviceAuthorizationFlow": {
        "Provider": "hosted",
        "ProviderConfig": {
            "Audience": "${IDP_CLIENT_ID}",
            "ClientID": "${IDP_CLIENT_ID}",
            "Scope": "openid profile email offline_access api"
        }
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
# Generate Zitadel Dashboard.env
# -----------------------------------------------------------------------------

generate_zitadel_dashboard_env() {
    local netbird_domain="$1"

    cat << EOF
# =============================================================================
# NetBird Dashboard - Environment Configuration
# =============================================================================
# Generated by setup.sh on $(date)
# Identity Provider: Zitadel
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

# SSL Configuration
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
EOF
}

# -----------------------------------------------------------------------------
# Get Zitadel-specific management command flags
# -----------------------------------------------------------------------------

get_zitadel_mgmt_flags() {
    echo "--idp-sign-key-refresh-enabled"
}

# -----------------------------------------------------------------------------
# Print Zitadel Post-Installation Instructions
# -----------------------------------------------------------------------------

print_zitadel_post_install() {
    if [[ "$IDP_MODE" == "deploy" ]]; then
        echo -e "${BOLD}1. Configure Zitadel${NC}"
        echo ""
        echo "   Access Zitadel: ${IDP_URL}"
        echo ""
        echo "   a. Complete the initial setup wizard"
        echo "   b. Create a new project named 'NETBIRD'"
        echo "   c. Create an application:"
        echo "      - Name: netbird"
        echo "      - Type: User Agent"
        echo "      - Authentication: PKCE"
        echo "      - Redirect URIs:"
        echo "        - https://${NETBIRD_DOMAIN}/auth"
        echo "        - https://${NETBIRD_DOMAIN}/silent-auth"
        echo "        - http://localhost:53000"
        echo "      - Post Logout URI: https://${NETBIRD_DOMAIN}/"
        echo "   d. In Token Settings:"
        echo "      - Auth Token Type: JWT"
        echo "      - Enable 'Add user roles to access token'"
        echo "   e. Copy the Client ID"
        echo ""
        echo "   f. Create a Service User:"
        echo "      - Username: netbird"
        echo "      - Access Token Type: JWT"
        echo "      - Generate Client Secret and copy it"
        echo "   g. Grant 'Org User Manager' role to the service user"
        echo ""
        echo -e "${BOLD}2. Update Configuration${NC}"
        echo ""
        echo "   Run: ./setup.sh --update-credentials"
        echo "   Enter the Client ID and Service User credentials"
        echo ""
    else
        echo -e "${BOLD}Zitadel Configuration${NC}"
        echo ""
        echo "   Your existing Zitadel instance is configured."
        echo "   Make sure the following are set in Zitadel:"
        echo ""
        echo "   Redirect URIs:"
        echo "     - https://${NETBIRD_DOMAIN}/auth"
        echo "     - https://${NETBIRD_DOMAIN}/silent-auth"
        echo "     - http://localhost:53000"
        echo ""
        echo "   Post Logout URI: https://${NETBIRD_DOMAIN}/"
        echo ""
    fi
}
