# Keycloak with NetBird Self-Hosted

This guide explains how to configure Keycloak as the identity provider for your self-hosted NetBird installation.

## About Keycloak

[Keycloak](https://www.keycloak.org) is an open-source Identity and Access Management solution aimed at modern applications and services. It provides:

- Single sign-on (SSO) and social login
- User federation (LDAP, Active Directory)
- Fine-grained authorization
- OpenID Connect, OAuth 2.0, and SAML 2.0 support
- Extensive documentation and community support
- Customizable themes and extensions

## Prerequisites

- Docker and Docker Compose installed
- A domain name with DNS configured for Keycloak (e.g., `keycloak.yourdomain.com`)
- Ports 80 and 443 available (via reverse proxy)

## DNS Configuration

Create an A record pointing to your server:

| Subdomain | Purpose |
|-----------|---------|
| `keycloak.yourdomain.com` | Keycloak identity provider |

## Option 1: Deploy Keycloak with NetBird

If you're deploying Keycloak as part of the NetBird stack:

### Step 1: Access Keycloak

After starting the stack, navigate to `https://keycloak.yourdomain.com`

Login with:
- **Username:** admin (or value from KEYCLOAK_ADMIN_USER in .env)
- **Password:** (from KEYCLOAK_ADMIN_PASSWORD in .env)

### Step 2: Create Realm

1. Hover over the dropdown in the top-left corner (shows "Master")
2. Click **Create Realm**
3. Set:
   - **Realm name:** netbird
4. Click **Create**

### Step 3: Create User

1. In the netbird realm, go to **Users**
2. Click **Create new user**
3. Set:
   - **Username:** your-username
   - **Email:** your-email
4. Click **Create**
5. Go to **Credentials** tab
6. Click **Set password**
7. Enter password and set **Temporary** to Off
8. Click **Save**

### Step 4: Create Frontend Client

1. Go to **Clients** > **Create client**
2. Configure General Settings:
   - **Client type:** OpenID Connect
   - **Client ID:** netbird-client
3. Click **Next**
4. Configure Capability config:
   - **Client authentication:** Off (public client)
   - **Authorization:** Off
   - **Standard flow:** On
   - **Device authorization grant:** On (optional, for CLI)
5. Click **Next**
6. Configure Login settings:
   - **Root URL:** `https://netbird.yourdomain.com/`
   - **Valid redirect URIs:**
     - `https://netbird.yourdomain.com/*`
     - `http://localhost:53000`
   - **Valid post logout redirect URIs:** `https://netbird.yourdomain.com/*`
   - **Web origins:** `+`
7. Click **Save**

### Step 5: Create Client Scope

1. Go to **Client scopes** > **Create client scope**
2. Configure:
   - **Name:** api
   - **Type:** Default
   - **Protocol:** OpenID Connect
3. Click **Save**
4. Go to **Mappers** tab > **Configure a new mapper**
5. Select **Audience**
6. Configure:
   - **Name:** Audience for NetBird Management API
   - **Included Client Audience:** netbird-client
   - **Add to access token:** On
7. Click **Save**

### Step 6: Add Client Scope to Frontend Client

1. Go to **Clients** > **netbird-client** > **Client scopes**
2. Click **Add client scope**
3. Select **api**
4. Click **Add** choosing **Default**

### Step 7: Create Backend Client

1. Go to **Clients** > **Create client**
2. Configure General Settings:
   - **Client type:** OpenID Connect
   - **Client ID:** netbird-backend
3. Click **Next**
4. Configure Capability config:
   - **Client authentication:** On (confidential client)
   - **Service accounts roles:** On
5. Click **Next** and **Save**
6. Go to **Credentials** tab
7. **Copy the Client secret** - you'll need this for NetBird configuration

### Step 8: Grant Backend Permissions

1. Go to **Clients** > **netbird-backend** > **Service accounts roles**
2. Click **Assign role**
3. Select **Filter by clients**
4. Search for **view-users**
5. Check the role and click **Assign**

> **Optional:** To enable user deletion from NetBird, also assign the **manage-users** role.

### Step 9: Update NetBird Configuration

Run the setup script with the update flag:

```bash
./setup.sh --update-credentials
```

Enter:
- **Frontend Client ID:** netbird-client
- **Backend Client ID:** netbird-backend
- **Backend Client Secret:** (from Step 7)

## Option 2: Use Existing Keycloak Instance

If you have an existing Keycloak instance:

### Required Configuration

1. **Realm** (default: netbird)

2. **Frontend Client** (netbird-client) with:
   - Public client (no authentication)
   - Standard flow enabled
   - Redirect URIs configured
   - Web origins set to `+`

3. **Backend Client** (netbird-backend) with:
   - Confidential client (client authentication)
   - Service accounts enabled
   - view-users role assigned

4. **Client Scope** (api) with:
   - Audience mapper for netbird-client

### OIDC Endpoint

Your OIDC configuration endpoint will be:
```
https://your-keycloak-domain/realms/netbird/.well-known/openid-configuration
```

### Admin Endpoint

The admin API endpoint for user management:
```
https://your-keycloak-domain/admin/realms/netbird
```

### Configuration Variables

When running the setup script, you'll need:

| Variable | Description |
|----------|-------------|
| Keycloak URL | Base URL of your Keycloak instance |
| Realm name | Usually `netbird` |
| Frontend Client ID | Usually `netbird-client` |
| Backend Client ID | Usually `netbird-backend` |
| Backend Client Secret | Secret from backend client credentials |

## User Deletion from IDP

NetBird can automatically delete users from Keycloak when they're removed from NetBird. To enable:

1. Assign **manage-users** role to netbird-backend service account
2. Add `--user-delete-from-idp` flag to management service command

## Verification

After configuration, verify:

1. **OIDC Endpoint:** Visit `https://your-keycloak-domain/realms/netbird/.well-known/openid-configuration` - should return JSON
2. **NetBird Dashboard:** Login at `https://netbird.yourdomain.com` - should redirect to Keycloak
3. **Backend Access:** Management service should be able to list users

## Troubleshooting

### "Invalid redirect URI" error
- Ensure redirect URIs exactly match (including protocol and trailing slashes)
- Check that both `https://netbird.yourdomain.com/*` and `http://localhost:53000` are added

### "Invalid audience" error
- Verify the api client scope is added to netbird-client
- Check that the audience mapper is configured correctly

### Backend authentication fails
- Verify the backend client secret matches
- Check that service accounts roles is enabled
- Ensure view-users role is assigned

### "HTTPS required" error
- Keycloak requires HTTPS in production mode
- Ensure your reverse proxy is configured for SSL
- Check that `--proxy-headers=xforwarded` is in the Keycloak command

### Users not syncing
- Verify the backend client has view-users role
- Check management service logs for API errors

## References

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [NetBird Keycloak Guide](https://docs.netbird.io/selfhosted/identity-providers/keycloak)
