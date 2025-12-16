# NetBird NGINX Reverse Proxy Configuration

This directory contains scripts and templates for configuring NGINX as a reverse proxy for NetBird.

## Overview

NetBird requires a reverse proxy that supports:
- **HTTP/2** for gRPC communication
- **WebSocket** for browser clients
- **SSL/TLS** termination

This setup script supports two modes:
1. **Existing NGINX** - Outputs configuration for copy/paste into your running NGINX
2. **New NGINX** - Deploys NGINX with Docker and automatic SSL via Certbot

## Quick Start

```bash
# Make the script executable
chmod +x setup.sh

# Run interactively
./setup.sh

# Or run with a specific mode
./setup.sh --existing    # For existing NGINX installations
./setup.sh --new         # For new Docker-based deployment
```

## Option 1: Existing NGINX Installation

If you already have NGINX running on your server, use this option to get a configuration file you can copy/paste.

```bash
./setup.sh --existing
```

The script will:
1. Ask for your NetBird domain
2. Ask for upstream service addresses
3. Ask for SSL certificate paths
4. Output a complete NGINX configuration

### Manual Steps After Getting Configuration

1. Save the configuration to a file:
   ```bash
   sudo nano /etc/nginx/sites-available/netbird.conf
   ```

2. Enable the site:
   ```bash
   sudo ln -s /etc/nginx/sites-available/netbird.conf /etc/nginx/sites-enabled/
   ```

3. If you don't have SSL certificates, obtain them:
   ```bash
   sudo apt install certbot python3-certbot-nginx
   sudo certbot certonly --nginx -d your-netbird-domain.com
   ```

4. Test and reload NGINX:
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

## Option 2: New NGINX with Docker

If you want to deploy a fresh NGINX with automatic SSL certificate management:

```bash
./setup.sh --new
```

The script will:
1. Create a directory structure for NGINX and Certbot
2. Generate docker-compose.yml
3. Generate NGINX configuration
4. Optionally initialize SSL certificates

### Directory Structure Created

```
nginx-netbird/
├── docker-compose.yml
├── init-letsencrypt.sh
├── renew-certificates.sh
├── nginx/
│   └── conf.d/
│       ├── default.conf (temporary)
│       └── netbird.conf
└── certbot/
    ├── conf/  (certificates)
    └── www/   (ACME challenges)
```

### Commands

```bash
# Navigate to setup directory
cd nginx-netbird

# Initialize SSL certificates
./init-letsencrypt.sh

# Test with staging certificates first
STAGING=1 ./init-letsencrypt.sh

# Start/stop services
docker compose up -d
docker compose down

# View logs
docker compose logs -f nginx

# Manual certificate renewal
./renew-certificates.sh
```

## Endpoint Reference

The NGINX configuration proxies the following endpoints:

| Endpoint | Protocol | Target Service | Description |
|----------|----------|----------------|-------------|
| `/` | HTTP | dashboard:80 | Web dashboard |
| `/api` | HTTP | management:80 | Management REST API |
| `/management.ManagementService/` | gRPC | management:80 | Management gRPC API |
| `/ws-proxy/management` | WebSocket | management:80 | Browser client management |
| `/signalexchange.SignalExchange/` | gRPC | signal:80 | Signal gRPC API |
| `/ws-proxy/signal` | WebSocket | signal:80 | Browser client signaling |
| `/relay` | WebSocket | relay:33080 | Relay WebSocket |

## QUIC/UDP Relay

The QUIC relay on UDP port 33080 cannot be proxied through the standard NGINX http block. You have two options:

1. **Expose directly** - Open UDP port 33080 on your firewall
2. **Use NGINX stream module** - Requires recompiling NGINX with `--with-stream`

If using the stream module, add this to your main `nginx.conf` (outside the http block):

```nginx
stream {
    upstream relay_quic {
        server relay:33080;
    }

    server {
        listen 33080 udp;
        proxy_pass relay_quic;
        proxy_timeout 3600s;
    }
}
```

## Requirements

### For Existing NGINX
- NGINX 1.13.10+ (for gRPC support)
- NGINX compiled with `ngx_http_v2_module`
- SSL certificates (can use Certbot)

### For New Docker Deployment
- Docker and Docker Compose
- Ports 80 and 443 available
- Domain pointing to your server

## Troubleshooting

### gRPC Not Working
- Ensure NGINX has HTTP/2 enabled (`http2 on;`)
- Check that NGINX was compiled with gRPC support
- Verify the `grpc_pass` directive is available

### WebSocket Connection Fails
- Ensure `Upgrade` and `Connection` headers are set
- Check timeout values (default may be too short)

### SSL Certificate Issues
- Verify DNS is pointing to your server
- Ensure port 80 is open for ACME challenges
- Check certbot logs: `docker compose logs certbot`

### Services Not Reachable
- Verify the Docker network is correct
- Check that NetBird services are running
- Ensure container names match the upstream configuration

## See Also

- [NetBird Self-Hosted Guide](../../ref/selfhosted/selfhosted-guide.mdx)
- [PocketID Setup](../../pocketid/README.md)
