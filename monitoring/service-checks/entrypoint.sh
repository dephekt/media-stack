#!/bin/sh
# supercronic runs the crontab in the foreground, in-process — no fork,
# no setsid, no setpgid (which Docker's default seccomp profile blocks).
# /etc/supercronic/crontab is bind-mounted from monitoring/service-checks/crontab.
set -eu
exec supercronic /etc/supercronic/crontab
