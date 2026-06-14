FROM kanboard/kanboard:v1.2.51

ARG OAUTH2_PLUGIN_VERSION=v1.0.2

ADD https://github.com/kanboard/plugin-oauth2/archive/refs/tags/${OAUTH2_PLUGIN_VERSION}.tar.gz /tmp/oauth2.tar.gz
COPY configure-oauth.php /opt/kanboard/configure-oauth.php

RUN set -eu; \
    version="${OAUTH2_PLUGIN_VERSION#v}"; \
    mkdir -p /var/www/app/plugins; \
    tar -xzf /tmp/oauth2.tar.gz -C /tmp; \
    mv "/tmp/plugin-oauth2-${version}" /var/www/app/plugins/OAuth2; \
    rm -f /tmp/oauth2.tar.gz; \
    chown -R nginx:nginx /var/www/app/plugins/OAuth2; \
    chmod 0444 /opt/kanboard/configure-oauth.php
