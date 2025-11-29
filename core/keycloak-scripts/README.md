# Keycloak script providers

Keycloak has the ability to execute scripts during runtime in order to allow administrators to customize specific functionalities:

- Authenticator
- JavaScript Policy
- OpenID Connect Protocol Mapper
- SAML Protocol Mapper

## OIDC Protocol Mappers

### Assigning claims based on group

In Keycloak, I add users to groups like:

- streaming
- photos
- family
- ai
- admin

I want users in the family or photos groups able to login to Immich. For this, I need a way to map a user's Keycloak group to their `immich_role` claim type. I made `immich-role-mapper.js` using Keycloak's support for making OIDC Protocol Mapper scripts.

#### Immich

Immich uses OIDC and the concept of claim mappings to map users to a role like `user` or `admin` when they sign in. It can handle 3 types of claim mappings:

- immich_role: should return `admin` or `user`
- immich_quota: Claim mapping for the user's storage quota
- preferred_username: Claim mapping for the user's storage label

Claims are only used **_on user creation_** to set initial values and are **_not synchronized_** from Keycloak.

Docs: [Immich OAuth Authentication](https://docs.immich.app/administration/oauth/#enable-oauth)



