# Zitadel with NetBird Self-Hosted

This guide explains how to configure Zitadel as the identity provider for your self-hosted NetBird installation.

## About Zitadel

[Zitadel](https://zitadel.com) is an open-source identity infrastructure platform designed for cloud-native environments. It provides:

- Multi-tenancy and customizable branding
- Passwordless authentication (FIDO2/passkeys)
- OpenID Connect, OAuth2, SAML2, and LDAP support
- Device authorization flow for CLI login
- SCIM 2.0 for user provisioning
- Unlimited audit trails

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured for Zitadel (e.g., `zitadel.yourdomain.com`)
- Ports 80 and 443 available (via reverse proxy)

## DNS Configuration

Create an A record pointing to your server:

| Subdomain | Purpose |
|-----------|---------|
| `zitadel.yourdomain.com` | Zitadel identity provider |

## Option 1: Deploy Zitadel with NetBird

If you're deploying Zitadel as part of the NetBird stack, the setup script handles most configuration. After deployment:

### Step 1: Access Zitadel

Navigate to `https://zitadel.yourdomain.com` and log in with:
- **Username:** admin
- **Password:** (the password you set during setup, default: `Admin123!`)

### Step 2: Create NetBird Project

1. Click **Projects** in the top menu
2. Click **Create New Project**
3. Name: `NETBIRD`
4. Click **Continue**

### Step 3: Create NetBird Application

1. In the NETBIRD project, click **New** in the Applications section
2. Fill in:
   - **Name:** netbird
   - **Type:** User Agent
3. Click **Continue**
4. Select **PKCE** as the authentication method
5. Click **Continue**
6. Add Redirect URIs:
   - `https://netbird.yourdomain.com/auth`
   - `https://netbird.yourdomain.com/silent-auth`
   - `http://localhost:53000`
7. Add Post Logout URI:
   - `https://netbird.yourdomain.com/`
8. Click **Create**

### Step 4: Configure Token Settings

1. Select the `netbird` application
2. Click **Token Settings**
3. Set:
   - **Auth Token Type:** JWT
   - **Add user roles to the access token:** Enabled
4. Click **Save**

**Copy the Client ID** - you'll need this for NetBird configuration.

### Step 5: Enable Grant Types

1. In the application overview
2. Under **Grant Types**, enable:
   - Authorization Code
   - Device Code
   - Refresh Token
3. Click **Save**

### Step 6: Create Service User

1. Click **Users** in the top menu
2. Select **Service Users** tab
3. Click **New**
4. Fill in:
   - **Username:** netbird
   - **Name:** netbird
   - **Access Token Type:** JWT
5. Click **Create**

### Step 7: Generate Client Secret

1. Click **Actions** in the top right
2. Click **Generate Client Secret**
3. **Copy the Client Secret** - you'll need this for NetBird configuration

### Step 8: Grant Permissions

1. Click **Organization** in the top menu
2. Click **+** in the top right
3. Search for the `netbird` service user
4. Check **Org User Manager**
5. Click **Add**

### Step 9: Update NetBird Configuration

Run the setup script with the update flag:

```bash
./setup.sh --update-credentials
```

Enter:
- **OIDC Client ID:** (from Step 4)
- **Service User Client ID:** netbird
- **Service User Client Secret:** (from Step 7)

## Option 2: Use Existing Zitadel Instance

If you have an existing Zitadel instance:

### Required Configuration

1. **OIDC Client** with:
   - Type: User Agent
   - Authentication: PKCE
   - Redirect URIs as listed above
   - Grant Types: Authorization Code, Device Code, Refresh Token
   - Token Type: JWT with roles

2. **Service User** with:
   - Org User Manager role
   - Client credentials (ID and Secret)

### OIDC Endpoint

Your OIDC configuration endpoint will be:
```
https://your-zitadel-domain/.well-known/openid-configuration
```

### Configuration Variables

When running the setup script, you'll need:

| Variable | Description |
|----------|-------------|
| Zitadel URL | Base URL of your Zitadel instance |
| OIDC Client ID | Client ID from the netbird application |
| Service User Client ID | Usually `netbird` |
| Service User Client Secret | Generated secret for the service user |

## Verification

After configuration, verify:

1. **OIDC Endpoint:** Visit `https://your-zitadel-domain/.well-known/openid-configuration` - should return JSON
2. **NetBird Dashboard:** Login at `https://netbird.yourdomain.com` - should redirect to Zitadel
3. **Device Auth:** Run `netbird up --management-url https://netbird.yourdomain.com` - should show device code flow

## Troubleshooting

### "Invalid redirect URI" error
- Ensure all redirect URIs in Zitadel exactly match those in the error message
- Check for trailing slashes

### "Invalid audience" error
- Verify the Client ID matches in both Zitadel and NetBird configuration
- Check that the `api` scope is configured

### Service user authentication fails
- Verify the service user has the correct role
- Regenerate the client secret and update configuration

### Device authorization not working
- Ensure Device Code grant type is enabled
- Check that `DeviceAuthorizationFlow.Provider` is set to `hosted`

## References

- [Zitadel Documentation](https://zitadel.com/docs)
- [NetBird Zitadel Guide](https://docs.netbird.io/selfhosted/identity-providers/zitadel)
