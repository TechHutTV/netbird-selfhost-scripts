# NetBird Self-Hosted with PocketID

This guide walks you through deploying NetBird self-hosted with [PocketID](https://github.com/stonith404/pocket-id) as the identity provider and NGINX Proxy Manager for SSL/reverse proxy.

## File Structure

```
pocketid/
├── compose.yaml        # Docker Compose stack definition
├── .env                # Main environment variables (domains, secrets)
├── dashboard.env       # NetBird Dashboard configuration (OIDC settings)
├── relay.env           # NetBird Relay server configuration
├── management.json     # NetBird Management server configuration
├── turnserver.conf     # Coturn TURN/STUN server configuration
└── README.md           # This documentation
```

### Configuration Files Overview

| File | Purpose | Key Settings |
|------|---------|--------------|
| `.env` | Main environment variables | Domain names, TURN password, relay secret |
| `dashboard.env` | Dashboard web UI config | OIDC client ID, auth endpoints |
| `relay.env` | Relay server config | Exposed address, auth secret |
| `management.json` | Management API config | STUN/TURN servers, OIDC, IDP integration |
| `turnserver.conf` | Coturn config | Ports, credentials, realm |
| `compose.yaml` | Docker services | All container definitions |

## Overview

| Component | Purpose |
|-----------|---------|
| NGINX Proxy Manager | Reverse proxy with automatic SSL |
| PocketID | Lightweight OIDC identity provider |
| NetBird Dashboard | Web UI for managing your network |
| NetBird Management | Core management API server |
| NetBird Signal | Signaling server for peer connections |
| NetBird Relay | Relay server for fallback connectivity |
| Coturn | TURN/STUN server for NAT traversal |

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured (3 subdomains recommended)
- Ports 80, 443, 3478 (UDP), and 49152-65535 (UDP) available

## DNS Configuration

Create the following DNS A records pointing to your server IP:

| Subdomain | Purpose |
|-----------|---------|
| `netbird.example.com` | NetBird Dashboard & API |
| `auth.example.com` | PocketID authentication |
| `npm.example.com` | NGINX Proxy Manager admin (optional) |

## Setup Instructions

### Step 1: Clone and Navigate

```bash
# Clone the repository
git clone https://github.com/TechHutTV/netbird-selfhost-scripts.git
cd netbird-selfhost-scripts/pocketid
```

### Step 2: Generate Secrets

Generate secure passwords for TURN and relay authentication:

```bash
# Generate TURN password
openssl rand -base64 32

# Generate relay auth secret (use a different value)
openssl rand -base64 32
```

### Step 3: Update Configuration Files

All configuration files are ready to use - just update the placeholder values with your domain and secrets.

**Quick Setup (Optional):** Use `sed` to replace all placeholder domains at once:

```bash
# Set your domains
NETBIRD_DOMAIN="netbird.yourdomain.com"
POCKETID_DOMAIN="auth.yourdomain.com"

# Replace in all config files
sed -i "s/netbird.example.com/$NETBIRD_DOMAIN/g" .env dashboard.env relay.env management.json turnserver.conf
sed -i "s/auth.example.com/$POCKETID_DOMAIN/g" .env dashboard.env management.json
```

Then manually update the secrets (TURN password, relay secret) - these must be unique values.

#### `.env` (Main environment variables)

```bash
# Domain Configuration
NETBIRD_DOMAIN=netbird.example.com
POCKETID_URL=https://auth.example.com

# Generate these with: openssl rand -base64 32
TURN_PASSWORD=your-turn-password-here
RELAY_AUTH_SECRET=your-relay-secret-here
```

#### `dashboard.env`

```bash
# Endpoints
NETBIRD_MGMT_API_ENDPOINT=https://netbird.example.com
NETBIRD_MGMT_GRPC_API_ENDPOINT=https://netbird.example.com

# OIDC Configuration (update after PocketID setup)
AUTH_AUDIENCE=your-pocketid-client-id
AUTH_CLIENT_ID=your-pocketid-client-id
AUTH_AUTHORITY=https://auth.example.com
USE_AUTH0=false
AUTH_SUPPORTED_SCOPES=openid profile email groups offline_access
AUTH_REDIRECT_URI=/auth
AUTH_SILENT_REDIRECT_URI=/silent-auth

# Token Configuration
NETBIRD_TOKEN_SOURCE=idToken

# SSL
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
```

#### `relay.env`

```bash
NB_LOG_LEVEL=info
NB_LISTEN_ADDRESS=:80
NB_EXPOSED_ADDRESS=rels://netbird.example.com:443/relay
NB_AUTH_SECRET=your-relay-secret-here
```

#### `turnserver.conf`

Update the credentials and realm:

```conf
# Update the password (must match TURN_PASSWORD in .env)
user=netbird:your-turn-password-here

# Update the realm to your domain
realm=netbird.example.com
```

#### `management.json`

Update the following values (search and replace `example.com` with your domain):

| Field | Update to |
|-------|-----------|
| `Stuns[0].URI` | `stun:YOUR_NETBIRD_DOMAIN:3478` |
| `Relay.Addresses` | `rels://YOUR_NETBIRD_DOMAIN:443/relay` |
| `Relay.Secret` | Your relay auth secret (same as `.env`) |
| `Signal.URI` | `YOUR_NETBIRD_DOMAIN:443` |
| `HttpConfig.AuthIssuer` | Your PocketID URL |
| `HttpConfig.AuthAudience` | PocketID Client ID (after Step 5) |
| `HttpConfig.OIDCConfigEndpoint` | `YOUR_POCKETID_URL/.well-known/openid-configuration` |
| `IdpManagerConfig.Extra.ManagementEndpoint` | Your PocketID URL |
| `IdpManagerConfig.Extra.ApiToken` | PocketID API Key (after Step 5) |
| `PKCEAuthorizationFlow.ProviderConfig.Audience` | PocketID Client ID |
| `PKCEAuthorizationFlow.ProviderConfig.ClientID` | PocketID Client ID |

### Step 4: Start the Stack

```bash
# Start all services
docker compose up -d
```

### Step 5: Configure NGINX Proxy Manager

1. Access NGINX Proxy Manager at `http://your-server-ip:81`
2. Default login: `admin@example.com` / `changeme`
3. Change the default password immediately

Create the following proxy hosts:

#### PocketID Proxy Host

| Setting | Value |
|---------|-------|
| Domain | `auth.example.com` |
| Scheme | `http` |
| Forward Hostname | `pocketid` |
| Forward Port | `80` |
| SSL | Request new certificate, Force SSL |
| Websockets | Enabled |

#### NetBird Proxy Host

| Setting | Value |
|---------|-------|
| Domain | `netbird.example.com` |
| Scheme | `http` |
| Forward Hostname | `dashboard` |
| Forward Port | `80` |
| SSL | Request new certificate, Force SSL |
| Websockets | Enabled |

Add custom locations for NetBird services (Advanced tab):

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

### Step 6: Configure PocketID

1. Access PocketID at `https://auth.example.com`
2. Complete the initial setup wizard
3. Create an admin account

#### Create OIDC Client for NetBird

1. Go to **Admin** > **OIDC Clients**
2. Click **Create Client**
3. Configure:
   - **Name**: NetBird
   - **Client Launch URL**: `https://netbird.example.com`
   - **Callback URLs**:
     - `http://localhost:53000`
     - `https://netbird.example.com/auth`
     - `https://netbird.example.com/silent-auth`
   - **Logout Callback URL**: `https://netbird.example.com/`
   - **Public Client**: On
   - **PKCE**: On
4. Click **Save** and copy the **Client ID**

#### Create API Key for NetBird Management

1. Go to **Admin** > **API Keys**
2. Click **Add API Key**
3. Configure:
   - **Name**: NetBird Management
   - **Expires At**: Pick a date in the future
4. Click **Save** and copy the **API Key**

### Step 7: Update Configuration with PocketID Client ID and API Key

Update `dashboard.env`:
```bash
AUTH_AUDIENCE=your-client-id-from-pocketid
AUTH_CLIENT_ID=your-client-id-from-pocketid
```

Update `management.json`:
- Replace all `your-pocketid-client-id` with the Client ID from PocketID
- Replace `your-pocketid-api-token-here` with the API Key from PocketID
- Update the `ManagementEndpoint` in `IdpManagerConfig.Extra` to your PocketID URL

### Step 8: Restart Services

```bash
docker compose restart dashboard management
```

## Verification

1. Access `https://netbird.example.com`
2. Click **Login** - you should be redirected to PocketID
3. Login with your PocketID credentials
4. You should be redirected back to the NetBird dashboard

## Connecting Clients

### Using the CLI

```bash
# Install NetBird client
curl -fsSL https://pkgs.netbird.io/install.sh | sh

# Connect with SSO
netbird up --management-url https://netbird.example.com
```

### Using Setup Keys

1. In the NetBird dashboard, go to **Setup Keys**
2. Create a new setup key
3. Use it to connect clients:

```bash
netbird up --management-url https://netbird.example.com --setup-key YOUR_SETUP_KEY
```

## Firewall Requirements

Ensure the following ports are open:

| Port | Protocol | Purpose |
|------|----------|---------|
| 80 | TCP | HTTP (redirects to HTTPS) |
| 443 | TCP | HTTPS, WebSocket, gRPC |
| 3478 | UDP | STUN |
| 5349 | TCP | TURN over TLS |
| 49152-65535 | UDP | TURN relay ports |

For UFW (Ubuntu), run:
```bash
sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw allow 3478/udp && \
sudo ufw allow 5349/tcp && sudo ufw allow 49152:65535/udp && sudo ufw reload
```

## Data Persistence

Docker volumes store persistent data:

| Volume | Purpose | Backup Priority |
|--------|---------|-----------------|
| `npm_data` | NGINX Proxy Manager config | Medium |
| `npm_letsencrypt` | SSL certificates | Medium |
| `pocketid_data` | PocketID users, OIDC clients | High |
| `netbird_management` | NetBird peers, networks, ACLs | High |

### Backup

```bash
# Stop services
docker compose stop

# Backup volumes
docker run --rm -v pocketid_pocketid_data:/data -v $(pwd):/backup alpine \
    tar czf /backup/pocketid-backup.tar.gz -C /data .
docker run --rm -v pocketid_netbird_management:/data -v $(pwd):/backup alpine \
    tar czf /backup/netbird-backup.tar.gz -C /data .

# Restart services
docker compose start
```

## Troubleshooting

### Check service logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f management
docker compose logs -f pocketid
```

### Common Issues

**OIDC Configuration Error**
- Verify PocketID is accessible at the configured URL
- Check that client IDs match in all configuration files
- Ensure callback URLs exactly match (including trailing slashes)

**Connection Timeouts**
- Verify firewall rules allow required ports
- Check that DNS records resolve correctly
- Ensure NGINX Proxy Manager SSL certificates are valid

**Management API Errors**
- Check `management.json` syntax with `jq . management.json`
- Verify the OIDC configuration endpoint is accessible

## Architecture Diagram

```
                                    ┌─────────────────────────────────────────┐
                                    │              Internet                    │
                                    └─────────────────┬───────────────────────┘
                                                      │
                              ┌───────────────────────┼───────────────────────┐
                              │                       │                       │
                           TCP 80               TCP 443               UDP 3478
                           TCP 81              TCP 33080              UDP 49152-65535
                              │                       │                       │
                              ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              NGINX Proxy Manager (:80, :443, :81)                       │
│                                                                                          │
│   Routes:                                                                                │
│   • auth.example.com     → pocketid:80                                                  │
│   • netbird.example.com/ → dashboard:80                                                 │
│   • /api                 → management:80                                                │
│   • /relay               → relay:80                                                     │
│   • /signalexchange.*    → signal:80 (gRPC)                                            │
│   • /management.*        → management:80 (gRPC)                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┬──────────────────────┐
         │                    │                    │                      │
         ▼                    ▼                    ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│    PocketID     │  │    Dashboard    │  │   Management    │  │     Signal      │
│    (IDP)        │  │    (Web UI)     │  │    (API)        │  │   (Signaling)   │
│    :80          │  │    :80          │  │    :80          │  │    :80          │
└─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────────┘
                                                   │
                                                   ▼
                                          ┌─────────────────┐
                                          │     Relay       │
                                          │  (Fallback)     │
                                          │     :80         │
                                          └─────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 Coturn (host network)                                   │
│                                                                                          │
│   UDP 3478 (STUN)  •  TCP 5349 (TURN TLS)  •  UDP 49152-65535 (relay ports)            │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Configuration Relationships

Understanding how the configuration files relate to each other:

```
.env
 ├── NETBIRD_DOMAIN ──────────────► Used in: dashboard.env, relay.env, management.json, turnserver.conf
 ├── POCKETID_URL ────────────────► Used in: dashboard.env, management.json
 ├── TURN_PASSWORD ───────────────► Must match: turnserver.conf (user=netbird:PASSWORD)
 └── RELAY_AUTH_SECRET ───────────► Must match: relay.env (NB_AUTH_SECRET)
                                              management.json (Relay.Secret)
```

**Important:** Ensure these values are synchronized across files:
- `TURN_PASSWORD` in `.env` must match the password in `turnserver.conf`
- `RELAY_AUTH_SECRET` in `.env` must match `NB_AUTH_SECRET` in `relay.env` AND `Relay.Secret` in `management.json`
- PocketID Client ID must be the same in `dashboard.env` (AUTH_CLIENT_ID, AUTH_AUDIENCE) and `management.json` (HttpConfig.AuthAudience, PKCEAuthorizationFlow.ProviderConfig)

## References

- [NetBird Documentation](https://docs.netbird.io/)
- [PocketID Documentation](https://github.com/stonith404/pocket-id)
- [NGINX Proxy Manager](https://nginxproxymanager.com/)
