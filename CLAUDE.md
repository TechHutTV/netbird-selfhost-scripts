# NetBird Self-Hosted Deployment Scripts

This repository contains deployment scripts to make NetBird self-hosted installation easy across various configurations including different identity providers (IDPs) and reverse proxy systems.

## NetBird Architecture Overview

NetBird is an open-source platform for creating secure private networks using WireGuard. It consists of four main components:

### Core Components

| Component | Description | Default Port |
|-----------|-------------|--------------|
| **Management Service** | Central coordination with UI dashboard. Handles peer registration, authentication, network state, IP management, ACLs, DNS, and activity logging. | 443 (HTTPS/gRPC) |
| **Signal Service** | Lightweight service for peer connection negotiation. No data storage, no traffic passes through it. | 80 (internal), 443 (external gRPC) |
| **Relay Service** | TURN server (Coturn) + WebSocket relay for fallback when direct P2P fails. Traffic remains encrypted. | 3478 (UDP/STUN), 33080 (WebSocket/QUIC) |
| **Dashboard** | Web UI for network management | 80 (internal HTTP) |

### Required Ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | Let's Encrypt / HTTP redirect |
| 443 | TCP | Dashboard HTTPS, Management gRPC & HTTP APIs |
| 33073 | TCP | Management HTTP API (alternative) |
| 10000 | TCP | Signal gRPC API |
| 33080 | TCP/UDP | Relay (WebSocket + QUIC) |
| 3478 | UDP | Coturn STUN/TURN |

## Identity Providers

NetBird uses OpenID Connect (OIDC) for authentication. The following providers are supported:

### Self-Hosted IDPs

| Provider | Description | `NETBIRD_MGMT_IDP` Value |
|----------|-------------|--------------------------|
| **Zitadel** | Open-source identity infrastructure. Multi-tenancy, FIDO2/passkeys, SCIM 2.0. Recommended for quickstart. | `zitadel` |
| **Keycloak** | Popular open-source IAM. SSO, social login, user federation, fine-grained authorization. | `keycloak` |
| **Authentik** | Flexible, security-focused. Self-hosted alternative to Okta/Auth0. | `authentik` |
| **PocketID** | Simplified identity management. Lightweight and easy to deploy. | `pocketid` |

### Managed IDPs

| Provider | Description | `NETBIRD_MGMT_IDP` Value |
|----------|-------------|--------------------------|
| **Auth0** | Flexible drop-in authentication service. Extensive customization. | `auth0` |
| **Microsoft Entra ID** (Azure AD) | Enterprise identity with Microsoft ecosystem integration. | `azure` |
| **Okta** | Enterprise IAM with thousands of pre-built integrations. | `okta` |
| **Google Workspace** | Identity management through Google's cloud infrastructure. | `google` |
| **JumpCloud** | Cloud directory platform with unified identity/device management. | `jumpcloud` |

## Core Configuration Variables

### setup.env Base Variables

```bash
# Domain Configuration
NETBIRD_DOMAIN=""                    # Your NetBird domain (e.g., netbird.example.com)
NETBIRD_LETSENCRYPT_EMAIL=""         # Email for Let's Encrypt certificates

# OIDC Authentication (Common to all IDPs)
NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT=""  # IDP's .well-known/openid-configuration URL
NETBIRD_AUTH_CLIENT_ID=""                     # OAuth Client ID
NETBIRD_AUTH_AUDIENCE=""                      # Token audience (often same as Client ID)
NETBIRD_AUTH_SUPPORTED_SCOPES=""              # OAuth scopes (usually: openid profile email offline_access)
NETBIRD_USE_AUTH0="false"                     # Set to "true" only for Auth0

# Device Authentication (Interactive SSO Login)
NETBIRD_AUTH_DEVICE_AUTH_PROVIDER=""          # "hosted", "none", or specific provider
NETBIRD_AUTH_DEVICE_AUTH_CLIENT_ID=""         # Device auth client ID
NETBIRD_AUTH_DEVICE_AUTH_AUDIENCE=""          # Device auth audience

# IDP Management Integration
NETBIRD_MGMT_IDP=""                           # IDP type (zitadel, keycloak, authentik, etc.)
NETBIRD_IDP_MGMT_CLIENT_ID=""                 # Backend client ID for user management
NETBIRD_IDP_MGMT_CLIENT_SECRET=""             # Backend client secret

# Reverse Proxy Configuration (when not using built-in Let's Encrypt)
NETBIRD_DISABLE_LETSENCRYPT="false"           # Set to "true" for custom reverse proxy
NETBIRD_MGMT_API_PORT="443"                   # Management API port
NETBIRD_SIGNAL_PORT="443"                     # Signal service port

# Database Configuration
NETBIRD_STORE_CONFIG_ENGINE="sqlite"          # "sqlite" or "postgres"
```

### IDP-Specific Variables

Each IDP requires additional specific variables. See `ref/selfhosted/identity-providers/` for details.

## Database Storage

### SQLite (Default since v0.26.0)
- Default for new installations
- Suitable for small to medium deployments
- Data stored in `/var/lib/netbird/store.db`

### PostgreSQL (Available since v0.27.8)
- Better for larger deployments
- Requires additional configuration:
```bash
NETBIRD_STORE_CONFIG_ENGINE="postgres"
NETBIRD_STORE_ENGINE_POSTGRES_DSN="host=<PG_HOST> user=<PG_USER> password=<PG_PASSWORD> dbname=<PG_DB_NAME> port=<PG_PORT>"
```

## Reverse Proxy Configuration

When running NetBird behind a reverse proxy, the following endpoints must be configured:

| Endpoint | Protocol | Target Service |
|----------|----------|----------------|
| `/` | HTTP | dashboard:80 |
| `/signalexchange.SignalExchange/` | gRPC (HTTP/2) | signal:80 |
| `/ws-proxy/signal` | WebSocket | signal:80 |
| `/api` | HTTP | management:443 |
| `/management.ManagementService/` | gRPC (HTTP/2) | management:443 |
| `/ws-proxy/management` | WebSocket | management:443 |
| `/relay` | WebSocket | relay:33080 |
| `:33080` (UDP) | QUIC | relay:33080 (L4 proxy or direct) |

**Important:** gRPC requires HTTP/2 protocol support in the reverse proxy.

---

# Script Blueprint

## Directory Structure

```
netbird-selfhost-scripts/
├── CLAUDE.md                      # This file
├── README.md                      # User documentation
├── install.sh                     # Main interactive installer
├── lib/                           # Shared library functions
│   ├── common.sh                  # Common utilities (logging, validation)
│   ├── docker.sh                  # Docker/compose utilities
│   ├── ssl.sh                     # SSL/TLS utilities
│   └── network.sh                 # Network utilities (port checking, DNS)
├── idp/                           # Identity Provider configurations
│   ├── zitadel/
│   │   ├── setup.sh               # Zitadel-specific setup
│   │   ├── configure.sh           # Generate Zitadel config
│   │   └── templates/             # Docker-compose and config templates
│   ├── keycloak/
│   │   ├── setup.sh
│   │   ├── configure.sh
│   │   └── templates/
│   ├── authentik/
│   │   ├── setup.sh
│   │   ├── configure.sh
│   │   └── templates/
│   ├── pocketid/
│   │   ├── setup.sh
│   │   ├── configure.sh
│   │   └── templates/
│   ├── auth0/
│   │   ├── configure.sh           # Managed IDP - config only
│   │   └── README.md              # Manual setup instructions
│   ├── azure-ad/
│   │   ├── configure.sh
│   │   └── README.md
│   ├── okta/
│   │   ├── configure.sh
│   │   └── README.md
│   ├── google-workspace/
│   │   ├── configure.sh
│   │   └── README.md
│   └── jumpcloud/
│       ├── configure.sh
│       └── README.md
├── reverse-proxy/                 # Reverse proxy configurations
│   ├── none/                      # Built-in Caddy with Let's Encrypt
│   │   └── docker-compose.yml.tmpl
│   ├── nginx-proxy-manager/
│   │   ├── setup.sh
│   │   ├── docker-compose.yml.tmpl
│   │   └── README.md              # NPM configuration instructions
│   ├── traefik/
│   │   ├── setup.sh
│   │   ├── docker-compose.yml.tmpl
│   │   ├── traefik.yml.tmpl
│   │   └── README.md
│   ├── caddy/                     # Standalone Caddy (custom config)
│   │   ├── setup.sh
│   │   ├── docker-compose.yml.tmpl
│   │   ├── Caddyfile.tmpl
│   │   └── README.md
│   ├── nginx/                     # Standard Nginx
│   │   ├── setup.sh
│   │   ├── docker-compose.yml.tmpl
│   │   ├── nginx.conf.tmpl
│   │   └── README.md
│   ├── haproxy/
│   │   ├── setup.sh
│   │   ├── docker-compose.yml.tmpl
│   │   ├── haproxy.cfg.tmpl
│   │   └── README.md
│   └── cloudflare-tunnel/
│       ├── setup.sh
│       ├── docker-compose.yml.tmpl
│       └── README.md
├── database/                      # Database configurations
│   ├── sqlite/                    # Default SQLite
│   │   └── README.md
│   └── postgres/
│       ├── setup.sh
│       ├── docker-compose.yml.tmpl
│       ├── migrate.sh             # SQLite to Postgres migration
│       └── README.md
├── templates/                     # Base templates
│   ├── setup.env.tmpl             # Base environment template
│   ├── management.json.tmpl       # Management config template
│   ├── turnserver.conf.tmpl       # Coturn config template
│   └── docker-compose.base.yml    # Base docker-compose
├── tools/                         # Utility scripts
│   ├── backup.sh                  # Backup script
│   ├── restore.sh                 # Restore script
│   ├── upgrade.sh                 # Upgrade script
│   ├── health-check.sh            # Health check script
│   └── troubleshoot.sh            # Troubleshooting utilities
└── examples/                      # Complete example configurations
    ├── zitadel-builtin/           # Zitadel with built-in Caddy
    ├── keycloak-traefik/          # Keycloak with Traefik
    ├── authentik-npm/             # Authentik with Nginx Proxy Manager
    └── auth0-cloudflare/          # Auth0 with Cloudflare Tunnel
```

## Main Installer Flow (install.sh)

```
1. Welcome & Prerequisites Check
   ├── Check OS compatibility (Linux)
   ├── Check Docker & Docker Compose
   ├── Check jq, curl installed
   └── Check required ports available

2. Domain Configuration
   ├── Get domain name
   ├── Validate DNS resolution
   └── Get Let's Encrypt email (if applicable)

3. Identity Provider Selection
   ├── Self-hosted Options:
   │   ├── Zitadel (Recommended - All-in-one)
   │   ├── Keycloak
   │   ├── Authentik
   │   └── PocketID
   └── Managed Options:
       ├── Auth0
       ├── Microsoft Entra ID
       ├── Okta
       ├── Google Workspace
       └── JumpCloud

4. Reverse Proxy Selection
   ├── Built-in (Caddy + Let's Encrypt) - Default
   ├── Nginx Proxy Manager
   ├── Traefik
   ├── Caddy (Standalone)
   ├── Nginx
   ├── HAProxy
   └── Cloudflare Tunnel

5. Database Selection
   ├── SQLite (Default)
   └── PostgreSQL

6. Advanced Options
   ├── Single account mode (default: enabled)
   ├── Custom TURN ports
   ├── Geolocation database
   └── User deletion from IDP

7. Configuration Generation
   ├── Generate setup.env
   ├── Run configure.sh
   └── Generate docker-compose.yml

8. Deployment
   ├── Pull Docker images
   ├── Start services
   └── Health check

9. Post-Installation
   ├── Display admin credentials (if applicable)
   ├── Display dashboard URL
   └── Next steps instructions
```

## Reverse Proxy Implementations

### Nginx Proxy Manager
- Popular GUI-based reverse proxy
- Requires: Proxy host configuration with WebSocket support
- Special considerations: gRPC requires custom Nginx config snippets

### Traefik
- Cloud-native reverse proxy with automatic service discovery
- Docker labels for configuration
- Built-in Let's Encrypt support
- Native HTTP/2 and gRPC support

### Caddy (Standalone)
- Simple configuration syntax
- Automatic HTTPS
- Native HTTP/2 and gRPC support

### Nginx
- Traditional reverse proxy
- Requires manual configuration for gRPC (grpc_pass)
- Stream module needed for UDP relay

### HAProxy
- High-performance load balancer
- HTTP/2 and gRPC support via h2 backend
- UDP mode for QUIC relay

### Cloudflare Tunnel
- Zero-trust access without opening ports
- Cloudflared container
- Limited: UDP/QUIC relay may need direct exposure

## Key Implementation Notes

### gRPC Proxying Requirements
- HTTP/2 protocol support required
- Proper header handling (content-type: application/grpc)
- No request body buffering
- Increased timeouts for streaming

### WebSocket Proxying
- Upgrade header handling
- Connection: Upgrade header
- Proper timeout configuration

### QUIC/UDP Relay
- Cannot be proxied through HTTP reverse proxies
- Options:
  1. Direct UDP exposure on port 33080
  2. L4 (transport layer) proxy supporting UDP
  3. Rely on WebSocket relay only (set appropriate config)

### Browser Client Support (v0.59.0+)
- Requires WebSocket proxy endpoints:
  - `/ws-proxy/management`
  - `/ws-proxy/signal`

## Testing Checklist

- [ ] Dashboard accessible via HTTPS
- [ ] Login with IDP works
- [ ] Peer registration works
- [ ] Peer-to-peer connection establishes
- [ ] TURN relay works (test with blocked UDP)
- [ ] Management API accessible
- [ ] Signal service reachable
- [ ] WebSocket endpoints work (browser client)

## Cloud Provider Considerations

### Hetzner
- Stateless firewall - add UDP port range from `ip_local_port_range`

### Oracle Cloud Infrastructure
- Default iptables rules block UDP 3478
- Run: `sudo iptables -I INPUT -p udp -m udp --dport 3478 -j ACCEPT`
- Don't use UFW, use iptables directly

## Reference Documentation

See `ref/` directory for official NetBird documentation used to build these scripts.
