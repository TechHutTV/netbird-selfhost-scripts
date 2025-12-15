# NetBird Self-Hosted Deployment Scripts

Deploy NetBird self-hosted with your choice of identity provider. This repository provides an interactive setup script and modular configuration for multiple IDPs.

## Supported Identity Providers

| Provider | Description | Best For |
|----------|-------------|----------|
| **Zitadel** | Full-featured identity platform with device auth, SCIM, passkeys | Production environments needing enterprise features |
| **Authentik** | Flexible, security-focused alternative to Okta/Auth0 | Users wanting extensive customization |
| **Keycloak** | Popular enterprise IAM with extensive integrations | Organizations with existing Keycloak deployments |
| **PocketID** | Lightweight, simple identity management | Simple setups, homelabs, minimal resource usage |

## Quick Start

```bash
# Clone the repository
git clone https://github.com/TechHutTV/netbird-selfhost-scripts.git
cd netbird-selfhost-scripts

# Run the interactive setup
./setup.sh
```

The setup script will:
1. Check prerequisites (Docker, Docker Compose, etc.)
2. Let you choose your identity provider
3. Ask if you have an existing IDP or want to deploy one
4. Configure your NetBird domain
5. Generate secure secrets
6. Create all configuration files
7. Optionally start the services

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured
- Ports 80, 443, 3478 (UDP), and 49152-65535 (UDP) available

## DNS Configuration

Create A records pointing to your server IP:

| Subdomain | Purpose | Required |
|-----------|---------|----------|
| `netbird.yourdomain.com` | NetBird Dashboard, Management, Signal, Relay | Yes |
| `auth.yourdomain.com` | Identity Provider (if deploying with stack) | If deploying IDP |

## Project Structure

```
netbird-selfhost-scripts/
├── setup.sh                 # Interactive setup script
├── compose.yaml             # Base NetBird services (no IDP)
├── .env                     # Environment variables (generated)
├── dashboard.env            # Dashboard configuration (generated)
├── relay.env                # Relay configuration (generated)
├── management.json          # Management configuration (generated)
├── turnserver.conf          # TURN server configuration (generated)
└── idp/                     # Identity provider modules
    ├── common.sh            # Shared IDP functions
    ├── zitadel/
    │   ├── config.sh        # Zitadel configuration logic
    │   ├── compose.yaml     # Zitadel Docker services
    │   └── README.md        # Zitadel setup guide
    ├── authentik/
    │   ├── config.sh
    │   ├── compose.yaml
    │   └── README.md
    ├── keycloak/
    │   ├── config.sh
    │   ├── compose.yaml
    │   └── README.md
    └── pocketid/
        ├── config.sh
        ├── compose.yaml
        └── README.md
```

## Setup Script Options

```bash
./setup.sh                    # Interactive setup wizard
./setup.sh --update-credentials  # Update IDP credentials after setup
./setup.sh --reset            # Reset all configuration files
./setup.sh --check            # Check prerequisites only
./setup.sh --help             # Show help
```

## Deployment Options

### Option 1: Deploy IDP with NetBird (Recommended for new setups)

The setup script can deploy your chosen IDP alongside NetBird:

```bash
# After running ./setup.sh and choosing to deploy IDP:
docker compose -f compose.yaml -f idp/<provider>/compose.yaml up -d
```

### Option 2: Use Existing IDP

If you already have an identity provider:

```bash
# After running ./setup.sh with existing IDP configuration:
docker compose up -d
```

## Post-Installation

After the initial deployment:

1. **Configure NGINX Proxy Manager** (if deployed)
   - Access: `http://YOUR_SERVER_IP:81`
   - Default login: `admin@example.com` / `changeme`
   - Create proxy hosts for your domains

2. **Configure your IDP**
   - Follow the provider-specific README in `idp/<provider>/README.md`
   - Create OIDC client and obtain credentials

3. **Update NetBird Configuration**
   ```bash
   ./setup.sh --update-credentials
   ```

4. **Access NetBird Dashboard**
   - Navigate to `https://netbird.yourdomain.com`
   - Login with your IDP credentials

## Connecting Clients

```bash
# Install NetBird client
curl -fsSL https://pkgs.netbird.io/install.sh | sh

# Connect with SSO
netbird up --management-url https://netbird.yourdomain.com

# Or with setup key
netbird up --management-url https://netbird.yourdomain.com --setup-key YOUR_KEY
```

## NGINX Proxy Manager Configuration

Create proxy hosts with these settings:

### IDP Proxy Host (if deploying IDP)

| Setting | Value |
|---------|-------|
| Domain | `auth.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname | `<idp-container-name>` |
| Forward Port | `80` (or `8080` for Zitadel/Keycloak) |
| SSL | Request new certificate, Force SSL |
| Websockets | Enabled |

### NetBird Proxy Host

| Setting | Value |
|---------|-------|
| Domain | `netbird.yourdomain.com` |
| Scheme | `http` |
| Forward Hostname | `dashboard` |
| Forward Port | `80` |
| SSL | Request new certificate, Force SSL |
| Websockets | Enabled |

Add these custom locations (Advanced tab):

```nginx
# Relay
location /relay {
    proxy_pass http://relay:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}

# Signal gRPC
location /signalexchange.SignalExchange/ {
    grpc_pass grpc://signal:80;
    grpc_set_header Host $host;
}

location /signal {
    proxy_pass http://signal:80;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
}

# Management API
location /api {
    proxy_pass http://management:80;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}

location /management.ManagementService/ {
    grpc_pass grpc://management:80;
    grpc_set_header Host $host;
}
```

## Firewall Requirements

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (Let's Encrypt, redirects) |
| 443 | TCP | HTTPS, WebSocket, gRPC |
| 3478 | UDP | STUN |
| 5349 | TCP | TURN over TLS |
| 49152-65535 | UDP | TURN relay ports |

For UFW (Ubuntu):
```bash
sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 3478/udp && \
sudo ufw allow 5349/tcp && sudo ufw allow 49152:65535/udp && sudo ufw reload
```

## Identity Provider Guides

Each IDP has detailed setup instructions:

- [Zitadel Setup Guide](idp/zitadel/README.md)
- [Authentik Setup Guide](idp/authentik/README.md)
- [Keycloak Setup Guide](idp/keycloak/README.md)
- [PocketID Setup Guide](idp/pocketid/README.md)

## Troubleshooting

### Check service logs

```bash
# All services (with IDP)
docker compose -f compose.yaml -f idp/<provider>/compose.yaml logs -f

# Specific service
docker compose logs -f management

# Without IDP in stack
docker compose logs -f
```

### Common Issues

**OIDC Configuration Error**
- Verify IDP is accessible at the configured URL
- Check that client IDs match in all configuration files
- Ensure callback URLs exactly match

**Connection Timeouts**
- Verify firewall rules allow required ports
- Check that DNS records resolve correctly
- Ensure SSL certificates are valid

**Management API Errors**
- Check `management.json` syntax: `jq . management.json`
- Verify the OIDC configuration endpoint is accessible

## Data Persistence

Docker volumes store persistent data:

| Volume | Purpose | Backup Priority |
|--------|---------|-----------------|
| `npm_data` | NGINX Proxy Manager config | Medium |
| `npm_letsencrypt` | SSL certificates | Medium |
| `netbird_management` | NetBird peers, networks, ACLs | High |
| IDP volumes | Users, OIDC clients | High |

## Architecture

```
                                    Internet
                                       │
                              ┌────────┼────────┐
                              │        │        │
                           TCP 80   TCP 443   UDP 3478
                              │        │        │
                              ▼        ▼        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NGINX Proxy Manager                          │
│  Routes:                                                        │
│  • auth.domain.com     → IDP:80                                │
│  • netbird.domain.com/ → dashboard:80                          │
│  • /api                → management:80                         │
│  • /relay              → relay:80                              │
│  • /signalexchange.*   → signal:80 (gRPC)                     │
│  • /management.*       → management:80 (gRPC)                  │
└─────────────────────────────────────────────────────────────────┘
         │              │              │              │
         ▼              ▼              ▼              ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
    │   IDP   │   │Dashboard│   │ Mgmt    │   │ Signal  │
    │(Zitadel/│   │ (Web UI)│   │ (API)   │   │         │
    │Authentik│   │         │   │         │   │         │
    │Keycloak/│   │         │   │         │   │         │
    │PocketID)│   │         │   │         │   │         │
    └─────────┘   └─────────┘   └─────────┘   └─────────┘
                                     │
                                     ▼
                               ┌─────────┐
                               │  Relay  │
                               └─────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      Coturn (host network)                      │
│  UDP 3478 (STUN) • TCP 5349 (TURN TLS) • UDP 49152-65535       │
└─────────────────────────────────────────────────────────────────┘
```

## References

- [NetBird Documentation](https://docs.netbird.io/)
- [NetBird Self-Hosting Guide](https://docs.netbird.io/selfhosted/selfhosted-guide)
- [NGINX Proxy Manager](https://nginxproxymanager.com/)
