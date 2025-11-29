FROM quay.io/keycloak/keycloak:26.3 as builder

# Enable health and metrics support during build, and enable scripts feature
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true
ENV KC_FEATURES=scripts:v1
ENV KC_DB=mariadb

# Add custom providers before the build so they are compiled into the optimized server
COPY keycloak-providers/*.jar /opt/keycloak/providers/

# Build optimized server with providers baked in
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.3

# Set defaults for health and metrics in the final image
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

# Copy the optimized server from the builder stage
COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Copy secrets2env helper script with execute permissions
COPY --chmod=755 secrets2env.sh /usr/local/bin/secrets2env.sh
