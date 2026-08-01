# Contributing

Issues and pull requests are welcome.

## Licensing of contributions

media-stack is licensed under the **GNU Affero General Public License, version 3
or later** (see [LICENSE](LICENSE)).

The project is maintained under single-copyright ownership so that alternative
licensing terms remain available to the copyright holder. To keep that
possible, contributions require an explicit grant beyond the AGPL — a sign-off
alone is not sufficient, because code received under the AGPL cannot later be
offered to anyone under different terms.

**By submitting a pull request, patch, or any other contribution to this
repository, you agree to the following:**

1. You are the author of the contribution, or you have the right to submit it
   under these terms.
2. You grant Daniel Snider a perpetual, worldwide, non-exclusive, royalty-free,
   irrevocable license to reproduce, modify, distribute, sublicense, and
   otherwise exploit your contribution, **under the AGPL-3.0-or-later and under
   any other license terms**, including proprietary terms.
3. You retain copyright in your contribution. This is a license grant, not an
   assignment — you may continue to use your own work however you like.
4. Your contribution is provided as-is, without warranty of any kind.

Please add a `Signed-off-by:` line to your commits (`git commit -s`) to record
your agreement, per the
[Developer Certificate of Origin](https://developercertificate.org/).

If you would rather not grant those terms, open an issue describing the change
instead of a pull request.

## What this license does and does not cover

This repository licenses the **orchestration** — Compose files, entrypoints,
health checks, Keycloak client configuration, routing, and documentation. The
container images it pulls are third-party software under their own licenses;
nothing here relicenses them.

When you copy a config file from an upstream project's documentation or
repository (Immich's hwaccel files, Pangolin's Traefik defaults, and similar),
do **not** add an SPDX header claiming it. Leave it verbatim and add a row to
the third-party table in the [README](README.md#third-party-configuration).

## New files

Files we own carry a two-line SPDX header:

```sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Daniel Snider
```

Shell scripts keep the shebang on line 1 with the header below it. Use your own
name in the copyright line for files you author outright.

## Checks

```sh
ruff check .
shellcheck $(git ls-files '*.sh')
yamllint .
```

Secrets never land in this repository — `render-config.sh` and friends pull them
from 1Password at deploy time. Do not commit a rendered config.
