FROM alpine:3.20

# python3 + http/data tooling for the check scripts.
# supercronic replaces dcron: dcron's setpgid syscall is blocked by Docker's
# default seccomp profile and the container ends up in a restart loop on
# `setpgid: Operation not permitted`. supercronic is a container-native cron
# that runs jobs in the foreground without fork/setsid/setpgid.
ARG SUPERCRONIC_VERSION=v0.2.45
ARG SUPERCRONIC_SHA1=e894b193bea75a5ee644e700c59e30eedc804cf7
RUN apk add --no-cache python3 curl jq libxml2-utils ca-certificates wget \
    && wget -qO /usr/local/bin/supercronic \
       "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64" \
    && echo "${SUPERCRONIC_SHA1}  /usr/local/bin/supercronic" | sha1sum -c - \
    && chmod +x /usr/local/bin/supercronic

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
