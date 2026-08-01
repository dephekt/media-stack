# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Daniel Snider

FROM python:3.12-alpine

WORKDIR /app
COPY kanban_ref.py /app/kanban_ref.py
COPY projects.yaml /app/projects.yaml

CMD ["python", "/app/kanban_ref.py"]
