# PocketID with NetBird Self-Hosted

This guide explains how to configure PocketID as the identity provider for your self-hosted NetBird installation.

## About PocketID

[PocketID](https://pocket-id.org/) is a simplified identity management solution designed for self-hosted environments. It provides:

- Lightweight and easy to deploy
- Simple OIDC authentication
- API key management
- User-friendly admin interface
- Minimal resource requirements
- Passkey/WebAuthn support

## Resource Requirements

PocketID is lightweight:

| Resource | Minimum |
|----------|---------|
| CPU | 1 core |
| RAM | 512 MB |
| Storage | 1 GB |

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured for PocketID (e.g., `auth.yourdomain.com`)
- Ports 80 and 443 available (via reverse proxy)

## DNS Configuration

Create an A record pointing to your server:

| Subdomain | Purpose |
|-----------|---------|
| `auth.yourdomain.com` | PocketID identity provider |

## Option 1: Deploy PocketID with NetBird

If you're deploying PocketID as part of the NetBird stack:

### Step 1: Access PocketID

After starting the stack, navigate to `https://auth.yourdomain.com`

Complete the initial setup wizard to create your admin account.

### Step 2: Create OIDC Client

1. Go to **Administration** > **OIDC Clients**
2. Click **Add Client** or **Create**
3. Configure:
   - **Name:** NetBird
   - **Client Launch URL:** `https://netbird.yourdomain.com`
   - **Callback URLs:**
     - `http://localhost:53000`
     - `https://netbird.yourdomain.com/auth`
     - `https://netbird.yourdomain.com/silent-auth`
   - **Logout Callback URL:** `https://netbird.yourdomain.com/`
   - **Public Client:** On
   - **PKCE:** On
4. Click **Save**

**Copy the Client ID** - you'll need this for NetBird configuration.

### Step 3: Create API Key

1. Go to **Administration** > **API Keys**
2. Click **Add API Key**
3. Configure:
   - **Name:** NetBird Management
   - **Expires At:** Set a future date
   - **Description:** API key for NetBird user management
4. Click **Save**

**Copy the API Key** - you'll need this for NetBird configuration.

> **Note:** PocketID API tokens have full access. Keep them secure and track their usage.

### Step 4: Update NetBird Configuration

Run the setup script with the update flag:

```bash
./setup.sh --update-credentials
```

Enter:
- **OIDC Client ID:** (from Step 2)
- **API Token:** (from Step 3)

## Option 2: Use Existing PocketID Instance

If you have an existing PocketID instance:

### Required Configuration

1. **OIDC Client** with:
   - Public client enabled
   - PKCE enabled
   - Callback URLs configured

2. **API Key** for management access

### OIDC Endpoint

Your OIDC configuration endpoint will be:
```
https://your-pocketid-domain/.well-known/openid-configuration
```

### Configuration Variables

When running the setup script, you'll need:

| Variable | Description |
|----------|-------------|
| PocketID URL | Base URL of your PocketID instance |
| OIDC Client ID | Client ID from your OIDC client |
| API Token | API key for management access |

## Important Notes

### Token Source

PocketID uses `idToken` as the token source. This is configured automatically:

```
NETBIRD_TOKEN_SOURCE=idToken
```

### Device Authorization

PocketID doesn't support device authorization flow. CLI authentication uses PKCE:

```
DeviceAuthorizationFlow.Provider: "none"
```

### Scopes

PocketID uses a specific set of scopes including `groups`:

```
openid profile email groups offline_access
```

### API Token Security

PocketID API tokens have full access to all operations. There's no scope limitation:

- Keep tokens secure
- Set appropriate expiration dates
- Rotate tokens periodically
- Monitor API key usage

## Verification

After configuration, verify:

1. **OIDC Endpoint:** Visit `https://your-pocketid-domain/.well-known/openid-configuration` - should return JSON
2. **NetBird Dashboard:** Login at `https://netbird.yourdomain.com` - should redirect to PocketID
3. **User Management:** NetBird should be able to list users from PocketID

## Troubleshooting

### "Invalid redirect URI" error
- Ensure callback URLs exactly match what's configured in PocketID
- Check for trailing slashes
- Verify all three callback URLs are added

### "Invalid client" error
- Verify the Client ID matches
- Ensure Public Client is enabled
- Check that PKCE is enabled

### API authentication fails
- Verify the API token is correct
- Check the token hasn't expired
- Ensure the token was copied completely

### Login loop
- Check that AUTH_AUTHORITY matches your PocketID URL
- Verify NETBIRD_TOKEN_SOURCE is set to idToken
- Clear browser cookies and try again

### Users not showing in NetBird
- Verify API key is correct
- Check management service logs for API errors
- Ensure the API key hasn't expired

## References

- [PocketID Documentation](https://pocket-id.org/docs)
- [PocketID GitHub](https://github.com/stonith404/pocket-id)
- [NetBird PocketID Guide](https://docs.netbird.io/selfhosted/identity-providers/pocketid)
