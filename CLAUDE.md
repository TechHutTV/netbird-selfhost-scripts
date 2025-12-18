# NetBird Self-Hosted Deployment Scripts

This repository contains deployment scripts to make NetBird self-hosted installation easy with PocketID as the identity provider and NGINX as the reverse proxy.

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

### Firewall Requirements (UFW on Ubuntu)

If you're running UFW (Uncomplicated Firewall) on Ubuntu, follow these steps to open the required ports for NetBird:

#### Step 1: Check UFW Status

```bash
sudo ufw status
```

If UFW is inactive, enable it (ensure SSH is allowed first):

```bash
sudo ufw allow OpenSSH
sudo ufw enable
```

#### Step 2: Allow Required TCP Ports

```bash
# HTTP (Let's Encrypt certificate validation)
sudo ufw allow 80/tcp comment 'NetBird - HTTP/Let'\''s Encrypt'

# HTTPS (Dashboard, Management API, Signal)
sudo ufw allow 443/tcp comment 'NetBird - HTTPS/Dashboard/Management'

# Signal gRPC API (if using non-standard port)
sudo ufw allow 10000/tcp comment 'NetBird - Signal gRPC'

# Relay WebSocket
sudo ufw allow 33080/tcp comment 'NetBird - Relay WebSocket'
```

#### Step 3: Allow Required UDP Ports

```bash
# Coturn STUN/TURN
sudo ufw allow 3478/udp comment 'NetBird - Coturn STUN/TURN'

# Relay QUIC
sudo ufw allow 33080/udp comment 'NetBird - Relay QUIC'
```

#### Step 4: Verify Configuration

```bash
sudo ufw status verbose
```

Expected output should show:

```
To                         Action      From
--                         ------      ----
OpenSSH                    ALLOW       Anywhere
80/tcp                     ALLOW       Anywhere                   # NetBird - HTTP/Let's Encrypt
443/tcp                    ALLOW       Anywhere                   # NetBird - HTTPS/Dashboard/Management
10000/tcp                  ALLOW       Anywhere                   # NetBird - Signal gRPC
33080/tcp                  ALLOW       Anywhere                   # NetBird - Relay WebSocket
3478/udp                   ALLOW       Anywhere                   # NetBird - Coturn STUN/TURN
33080/udp                  ALLOW       Anywhere                   # NetBird - Relay QUIC
```

#### Step 5: Reload UFW (if needed)

```bash
sudo ufw reload
```

#### Quick One-Liner Setup

For convenience, run all firewall rules at once:

```bash
sudo ufw allow OpenSSH && \
sudo ufw allow 80/tcp && \
sudo ufw allow 443/tcp && \
sudo ufw allow 10000/tcp && \
sudo ufw allow 33080/tcp && \
sudo ufw allow 3478/udp && \
sudo ufw allow 33080/udp && \
sudo ufw --force enable && \
sudo ufw status
```

#### Troubleshooting UFW Issues

- **Locked out of SSH?** Use cloud provider console to disable UFW or add SSH rule
- **Coturn not working?** Ensure UDP 3478 is open
- **Peers can't connect?** Verify both TCP and UDP on port 33080 are allowed
- **Let's Encrypt failing?** Confirm port 80/tcp is open and not blocked by cloud firewall

## Identity Provider

NetBird uses OpenID Connect (OIDC) for authentication. This deployment uses **PocketID** as the identity provider.

### PocketID

| Provider | Description | `NETBIRD_MGMT_IDP` Value |
|----------|-------------|--------------------------|
| **PocketID** | Simplified identity management. Lightweight and easy to deploy. | `pocketid` |

PocketID is a lightweight, self-hosted identity provider that integrates seamlessly with NetBird. It provides:
- Simple OIDC authentication
- User and group management
- API key support for management integration

## Core Configuration Variables

### setup.env Base Variables

```bash
# Domain Configuration
NETBIRD_DOMAIN=""                    # Your NetBird domain (e.g., netbird.example.com)
NETBIRD_LETSENCRYPT_EMAIL=""         # Email for Let's Encrypt certificates

# OIDC Authentication (PocketID)
NETBIRD_AUTH_OIDC_CONFIGURATION_ENDPOINT=""  # PocketID's .well-known/openid-configuration URL
NETBIRD_AUTH_CLIENT_ID=""                     # OAuth Client ID
NETBIRD_AUTH_AUDIENCE=""                      # Token audience (same as Client ID)
NETBIRD_AUTH_SUPPORTED_SCOPES=""              # OAuth scopes: openid profile email groups offline_access
NETBIRD_USE_AUTH0="false"                     # Always false for PocketID

# Device Authentication
NETBIRD_AUTH_DEVICE_AUTH_PROVIDER="none"      # PocketID uses "none"

# IDP Management Integration
NETBIRD_MGMT_IDP="pocketid"                   # IDP type
NETBIRD_IDP_MGMT_CLIENT_ID=""                 # PocketID client ID
NETBIRD_IDP_MGMT_API_TOKEN=""                 # PocketID API token

# Reverse Proxy Configuration
NETBIRD_DISABLE_LETSENCRYPT="false"           # Set to "true" for custom reverse proxy
NETBIRD_MGMT_API_PORT="443"                   # Management API port
NETBIRD_SIGNAL_PORT="443"                     # Signal service port

# Database Configuration
NETBIRD_STORE_CONFIG_ENGINE="sqlite"          # "sqlite" or "postgres"
```

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

This deployment uses NGINX as the reverse proxy with automatic SSL via Let's Encrypt. The following endpoints are configured:

| Endpoint | Protocol | Target Service |
|----------|----------|----------------|
| `/` | HTTP | dashboard:80 |
| `/signalexchange.SignalExchange/` | gRPC (HTTP/2) | signal:80 |
| `/ws-proxy/signal` | WebSocket | signal:80 |
| `/api` | HTTP | management:80 |
| `/management.ManagementService/` | gRPC (HTTP/2) | management:80 |
| `/ws-proxy/management` | WebSocket | management:80 |
| `/relay` | WebSocket | relay:33080 |

**Important:** gRPC requires HTTP/2 protocol support in the reverse proxy.

---

# Script Blueprint

## Directory Structure

```
netbird-selfhost-scripts/
├── CLAUDE.md                      # This file
├── README.md                      # User documentation
├── setup.sh                       # Interactive setup script
├── compose.yaml                   # Docker Compose stack definition
├── .env                           # Main environment variables
├── dashboard.env                  # Dashboard configuration
├── relay.env                      # Relay server configuration
├── management.json                # Management server configuration
├── turnserver.conf                # Coturn TURN/STUN configuration
├── idp/                           # Identity Provider utilities
│   └── common.sh                  # PocketID utility functions
├── nginx/                         # NGINX configuration
│   ├── nginx.conf                 # Main NGINX config
│   ├── netbird.conf.template      # Site configuration template
│   └── init-ssl.sh                # SSL initialization script
└── reverse-proxy/                 # Additional reverse proxy options
    └── nginx/
        ├── setup.sh
        └── README.md
```

## Main Installer Flow (setup.sh)

```
1. Welcome & Prerequisites Check
   ├── Check OS compatibility (Linux)
   ├── Check Docker & Docker Compose
   ├── Check curl, openssl, certbot installed
   └── Offer to install missing prerequisites

2. Domain Configuration
   ├── Get NetBird domain name
   ├── Get PocketID domain name
   ├── Validate DNS resolution
   └── Get Let's Encrypt email

3. PocketID Configuration
   ├── Existing PocketID: Get URL, Client ID, API Token
   └── New PocketID: Will be deployed with stack

4. Secret Generation
   ├── Generate TURN password
   └── Generate relay auth secret

5. Configuration Generation
   ├── Generate .env
   ├── Generate dashboard.env
   ├── Generate relay.env
   ├── Generate management.json
   ├── Generate turnserver.conf
   └── Generate NGINX configuration

6. SSL Certificate Acquisition
   ├── Stop any services on port 80
   ├── Run certbot for NetBird domain
   └── Run certbot for PocketID domain

7. Deployment
   ├── Pull Docker images
   ├── Start services
   └── Display service status

8. Post-Installation
   ├── Display PocketID setup instructions
   ├── Display dashboard URL
   └── Display client connection commands
```

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
- Coturn handles UDP directly on host network
- Port 3478 (STUN/TURN) must be open

### Browser Client Support (v0.59.0+)
- Requires WebSocket proxy endpoints:
  - `/ws-proxy/management`
  - `/ws-proxy/signal`

## Testing Checklist

- [ ] Dashboard accessible via HTTPS
- [ ] Login with PocketID works
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
