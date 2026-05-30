# Single-purpose redeploy poller. Holds the (rw) docker socket so the
# network-facing service-checks container never has to. On a cron it polls the
# codeberg registry and runs a scoped `compose pull/up` of just the agent-kb
# service when its image digest moves.
#
# docker:cli is Alpine-based; supercronic mirrors the service-checks cron model
# (foreground, in-process — no fork/setsid/setpgid, which Docker's default
# seccomp profile blocks). Keep SUPERCRONIC_* in sync with service-checks.
FROM docker:27-cli

ARG SUPERCRONIC_VERSION=v0.2.45
ARG SUPERCRONIC_SHA1=e894b193bea75a5ee644e700c59e30eedc804cf7
RUN apk add --no-cache curl ca-certificates docker-cli-compose \
    && wget -qO /usr/local/bin/supercronic \
       "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
    && echo "${SUPERCRONIC_SHA1}  /usr/local/bin/supercronic" | sha1sum -c - \
    && chmod +x /usr/local/bin/supercronic

COPY redeploy.sh /usr/local/bin/redeploy.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY crontab /etc/supercronic/crontab
RUN chmod +x /usr/local/bin/redeploy.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
