# NetBird Self-Hosted with PocketID

This guide walks you through deploying NetBird self-hosted with [PocketID](https://github.com/stonith404/pocket-id) as the identity provider and NGINX Proxy Manager for SSL/reverse proxy.

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

### Step 1: Clone and Configure

```bash
# Navigate to the pocketid directory
cd pocketid

# Copy all example configuration files
cp .env.example .env
cp dashboard.env.example dashboard.env
cp relay.env.example relay.env
cp turnserver.conf.example turnserver.conf
cp management.json.example management.json
```

### Step 2: Update Configuration Files

Update the following configuration files with your domain and secrets:

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
AUTH_SUPPORTED_SCOPES=openid profile email offline_access
AUTH_REDIRECT_URI=/nb-auth
AUTH_SILENT_REDIRECT_URI=/nb-silent-auth

# SSL
NGINX_SSL_PORT=443
LETSENCRYPT_DOMAIN=none
```

#### `relay.env`

```bash
NB_LOG_LEVEL=info
NB_LISTEN_ADDRESS=:80
NB_EXPOSED_ADDRESS=rels://netbird.example.com:443
NB_AUTH_SECRET=your-relay-secret-here
```

#### `turnserver.conf`

```conf
listening-port=3478
tls-listening-port=5349
min-port=49152
max-port=65535
fingerprint
lt-cred-mech
user=netbird:your-turn-password-here
realm=netbird.example.com
log-file=stdout
no-software-attribute
pidfile="/var/tmp/turnserver.pid"
no-cli
```

#### `management.json`

```json
{
    "Stuns": [
        {
            "Proto": "udp",
            "URI": "stun:netbird.example.com:3478"
        }
    ],
    "Relay": {
        "Addresses": ["rels://netbird.example.com:443"],
        "CredentialsTTL": "24h",
        "Secret": "your-relay-secret-here"
    },
    "Signal": {
        "Proto": "https",
        "URI": "netbird.example.com:443"
    },
    "HttpConfig": {
        "AuthIssuer": "https://auth.example.com",
        "AuthAudience": "your-pocketid-client-id",
        "OIDCConfigEndpoint": "https://auth.example.com/.well-known/openid-configuration"
    },
    "IdpManagerConfig": {
        "ManagerType": "none"
    },
    "DeviceAuthorizationFlow": {
        "Provider": "none"
    },
    "PKCEAuthorizationFlow": {
        "ProviderConfig": {
            "Audience": "your-pocketid-client-id",
            "ClientID": "your-pocketid-client-id",
            "Scope": "openid profile email offline_access",
            "RedirectURLs": ["http://localhost:53000/", "http://localhost:54000/"]
        }
    }
}
```

### Step 3: Start the Stack

```bash
# Start all services
docker compose up -d
```

### Step 4: Configure NGINX Proxy Manager

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

# Signal WebSocket
location /signalexchange.SignalExchange/ {
    grpc_pass grpc://signal:10000;
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

### Step 5: Configure PocketID

1. Access PocketID at `https://auth.example.com`
2. Complete the initial setup wizard
3. Create an admin account

#### Create OIDC Client for NetBird Dashboard

1. Go to **Admin** > **OIDC Clients**
2. Click **Create Client**
3. Configure:
   - **Name**: NetBird Dashboard
   - **Callback URLs**:
     - `https://netbird.example.com/nb-auth`
     - `https://netbird.example.com/nb-silent-auth`
   - **Logout URL**: `https://netbird.example.com/`
4. Save and copy the **Client ID**

#### Create OIDC Client for NetBird CLI

1. Create another client
2. Configure:
   - **Name**: NetBird CLI
   - **Callback URLs**:
     - `http://localhost:53000/`
     - `http://localhost:54000/`
3. Save and copy the **Client ID**

### Step 6: Update Configuration with PocketID Client IDs

Update `dashboard.env`:
```bash
AUTH_AUDIENCE=dashboard-client-id-from-pocketid
AUTH_CLIENT_ID=dashboard-client-id-from-pocketid
```

Update `management.json`:
- Replace all `your-pocketid-client-id` with the dashboard client ID
- For CLI connections, use the CLI client ID in `PKCEAuthorizationFlow`

### Step 7: Restart Services

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

## File Structure

```
pocketid/
├── compose.yaml              # Docker Compose configuration
├── README.md                 # This file
├── .env.example              # Example environment variables
├── .env                      # Environment variables (create from example)
├── dashboard.env.example     # Example NetBird Dashboard configuration
├── dashboard.env             # NetBird Dashboard configuration (create from example)
├── relay.env.example         # Example NetBird Relay configuration
├── relay.env                 # NetBird Relay configuration (create from example)
├── turnserver.conf.example   # Example Coturn TURN server configuration
├── turnserver.conf           # Coturn TURN server configuration (create from example)
├── management.json.example   # Example NetBird Management configuration
└── management.json           # NetBird Management configuration (create from example)
```

## References

- [NetBird Documentation](https://docs.netbird.io/)
- [PocketID Documentation](https://github.com/stonith404/pocket-id)
- [NGINX Proxy Manager](https://nginxproxymanager.com/)
