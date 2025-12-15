# Authentik with NetBird Self-Hosted

This guide explains how to configure Authentik as the identity provider for your self-hosted NetBird installation.

## About Authentik

[Authentik](https://goauthentik.io) is an open-source identity provider focused on flexibility and security. It provides:

- Single sign-on (SSO) and multi-factor authentication
- Self-hosted alternative to Okta/Auth0
- SAML and OIDC protocol support
- Customizable authentication flows
- Comprehensive audit logging
- Full API access for automation

## Resource Requirements

Authentik is more resource-intensive than lighter IDPs:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Storage | 10 GB | 20 GB |

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured for Authentik (e.g., `authentik.yourdomain.com`)
- Ports 80 and 443 available (via reverse proxy)

## DNS Configuration

Create an A record pointing to your server:

| Subdomain | Purpose |
|-----------|---------|
| `authentik.yourdomain.com` | Authentik identity provider |

## Option 1: Deploy Authentik with NetBird

If you're deploying Authentik as part of the NetBird stack:

### Step 1: Get Bootstrap Password

After starting the stack, get the initial admin password:

```bash
docker compose logs authentik 2>&1 | grep -i password
```

### Step 2: Access Authentik

Navigate to `https://authentik.yourdomain.com/if/flow/initial-setup/`

Complete the initial setup to create your admin account.

### Step 3: Create OAuth2/OpenID Provider

1. Go to **Applications** > **Providers**
2. Click **Create**
3. Select **OAuth2/OpenID Provider**
4. Configure:
   - **Name:** Netbird
   - **Authentication Flow:** default-authentication-flow
   - **Authorization Flow:** default-provider-authorization-explicit-consent
   - **Client type:** Public
   - **Redirect URIs:**
     - Regex: `https://netbird.yourdomain.com/.*`
     - Strict: `http://localhost:53000`
   - **Signing Key:** Select any available certificate (e.g., `authentik Self-signed Certificate`)
   - **Access code validity:** minutes=10
   - **Subject mode:** Based on the User's ID
5. Click **Finish**

**Copy the Client ID** - you'll need this for NetBird configuration.

### Step 4: Create Application

1. Go to **Applications** > **Applications**
2. Click **Create**
3. Configure:
   - **Name:** Netbird
   - **Slug:** `netbird` (important - must be exactly "netbird")
   - **Provider:** Netbird
4. Click **Create**

### Step 5: Create Service Account

1. Go to **Directory** > **Users**
2. Click **Create Service Account**
3. Configure:
   - **Username:** Netbird
   - **Create Group:** Disabled
4. Click **Create**

### Step 6: Add Service Account to Admin Group

1. Go to **Directory** > **Groups**
2. Click **authentik Admins**
3. Go to **Users** tab
4. Click **Add existing user**
5. Select **Netbird** and click **Add**

### Step 7: Create App Password

1. Go to **Directory** > **Tokens and App passwords**
2. Click **Create**
3. Configure:
   - **Identifier:** netbird-management
   - **User:** Select the Netbird service account
   - **Intent:** App password
4. Click **Create**

**Copy the App Password** - you'll need this for NetBird configuration.

### Step 8: Create Device Code Flow

1. Go to **Flows and Stages** > **Flows**
2. Click **Create**
3. Configure:
   - **Name:** default-device-code-flow
   - **Title:** Device Code Flow
   - **Designation:** Stage Configuration
   - **Authentication:** Require authentication
4. Click **Create**

### Step 9: Set Device Code Flow in Brand

1. Go to **System** > **Brands**
2. Edit **authentik-default**
3. Set **Device code flow:** default-device-code-flow
4. Click **Update**

### Step 10: Update NetBird Configuration

Run the setup script with the update flag:

```bash
./setup.sh --update-credentials
```

Enter:
- **Provider Client ID:** (from Step 3)
- **Service Account Username:** Netbird
- **Service Account App Password:** (from Step 7)

## Option 2: Use Existing Authentik Instance

If you have an existing Authentik instance:

### Required Configuration

1. **OAuth2/OpenID Provider** with:
   - Client type: Public
   - Redirect URIs as listed above
   - Signing key configured

2. **Application** with:
   - Slug: `netbird` (required for OIDC endpoint)
   - Provider linked

3. **Service Account** with:
   - Admin group membership
   - App password for API access

4. **Device Code Flow** (optional, for CLI)

### OIDC Endpoint

Your OIDC configuration endpoint will be:
```
https://your-authentik-domain/application/o/netbird/.well-known/openid-configuration
```

**Important:** The application slug must be `netbird` for this endpoint to work.

### Configuration Variables

When running the setup script, you'll need:

| Variable | Description |
|----------|-------------|
| Authentik URL | Base URL of your Authentik instance |
| Provider Client ID | Client ID from the OAuth2 provider |
| Service Account Username | Usually `Netbird` |
| Service Account App Password | App password for the service account |

## Known Issues

### PKCE Prompt Login Issue

Due to a compatibility issue between Authentik and NetBird, the setup automatically adds:

```
NETBIRD_AUTH_PKCE_DISABLE_PROMPT_LOGIN=true
```

See [GitHub Issue #3654](https://github.com/netbirdio/netbird/issues/3654) for details.

## Verification

After configuration, verify:

1. **OIDC Endpoint:** Visit `https://your-authentik-domain/application/o/netbird/.well-known/openid-configuration` - should return JSON
2. **NetBird Dashboard:** Login at `https://netbird.yourdomain.com` - should redirect to Authentik
3. **API Access:** The management service should be able to list users

## Troubleshooting

### "Application not found" error
- Ensure the application slug is exactly `netbird`
- The OIDC endpoint path includes the slug

### "Invalid redirect URI" error
- Check that redirect URIs match exactly (including protocol)
- Use regex pattern for the dashboard domain

### Service account authentication fails
- Verify the service account is in the authentik Admins group
- Ensure you're using an App Password, not the user password
- Check the password hasn't expired

### High memory usage
- Authentik can use significant memory
- Consider increasing swap if running on limited resources
- The worker process handles background tasks and can be resource-intensive

## References

- [Authentik Documentation](https://goauthentik.io/docs/)
- [NetBird Authentik Guide](https://docs.netbird.io/selfhosted/identity-providers/authentik)
