# Keycloak Custom Providers

This directory is mounted to `/opt/keycloak/providers` in the Keycloak container.

## Adding Custom Identity Providers

Place `.jar` files in this directory to add custom identity providers to Keycloak.

### Example: Apple Identity Provider

1. Download the Apple identity provider JAR from:
   - https://github.com/klausbetz/apple-identity-provider-keycloak
   - Or build from source

2. Place the JAR file in this directory

3. Restart Keycloak:
   ```bash
   make auth-stop
   make auth-start
   ```

4. The provider will be available in Keycloak admin console under Identity Providers

## Notes

- Files in this directory are automatically loaded by Keycloak on startup
- No additional configuration needed in docker-compose.yml
- Keycloak will scan this directory for provider JARs during initialization