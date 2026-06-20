FROM kanboard/kanboard:v1.2.51

ARG OAUTH2_PLUGIN_VERSION=v1.0.2
ARG MCP_PLUGIN_REF=a568378884a139c90d33e8b8f0deb88357091019

ADD https://github.com/kanboard/plugin-oauth2/archive/refs/tags/${OAUTH2_PLUGIN_VERSION}.tar.gz /tmp/oauth2.tar.gz
ADD https://github.com/ChristianJStarr/kanboard-mcp/archive/${MCP_PLUGIN_REF}.tar.gz /tmp/kanboard-mcp.tar.gz
COPY configure-oauth.php /opt/kanboard/configure-oauth.php
COPY entrypoint-with-plugins.sh /usr/local/bin/entrypoint-with-plugins.sh

RUN set -eu; \
    oauth2_version="${OAUTH2_PLUGIN_VERSION#v}"; \
    mkdir -p /opt/kanboard/plugins /var/www/app/plugins; \
    tar -xzf /tmp/oauth2.tar.gz -C /tmp; \
    mv "/tmp/plugin-oauth2-${oauth2_version}" /opt/kanboard/plugins/OAuth2; \
    mkdir -p /opt/kanboard/plugins/ModelContextProtocol; \
    tar -xzf /tmp/kanboard-mcp.tar.gz -C /opt/kanboard/plugins/ModelContextProtocol --strip-components=1; \
    cp -a /opt/kanboard/plugins/OAuth2 /var/www/app/plugins/OAuth2; \
    cp -a /opt/kanboard/plugins/ModelContextProtocol /var/www/app/plugins/ModelContextProtocol; \
    rm -f /tmp/oauth2.tar.gz /tmp/kanboard-mcp.tar.gz; \
    chown -R nginx:nginx /opt/kanboard/plugins /var/www/app/plugins/OAuth2 /var/www/app/plugins/ModelContextProtocol; \
    chmod 0444 /opt/kanboard/configure-oauth.php; \
    chmod 0555 /usr/local/bin/entrypoint-with-plugins.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-with-plugins.sh"]
