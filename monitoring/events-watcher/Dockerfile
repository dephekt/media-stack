# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Daniel Snider

FROM alpine:3.20

RUN apk add --no-cache docker-cli curl jq

COPY watch.sh /usr/local/bin/watch.sh
RUN chmod +x /usr/local/bin/watch.sh

ENTRYPOINT ["/usr/local/bin/watch.sh"]
