#!/usr/bin/env python3
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import yaml
except ImportError:
    yaml = None


REF_RE = re.compile(r"^/i/([A-Z][A-Z0-9]{1,9}-[0-9]{3,})/?$")


class KanboardError(RuntimeError):
    pass


def load_projects(path):
    with open(path, encoding="utf-8") as handle:
        raw = handle.read()
    data = yaml.safe_load(raw) if yaml is not None else parse_minimal_projects(raw)
    projects = data.get("projects") if isinstance(data, dict) else None
    if not isinstance(projects, dict):
        raise KanboardError("projects config must contain a projects mapping")
    return projects


def parse_minimal_projects(raw):
    projects = {}
    current = None
    for line in raw.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line.startswith("  ") and current and "name:" in line:
            _, value = line.split("name:", 1)
            projects[current]["name"] = value.strip()
        elif line.startswith("  ") and line.rstrip().endswith(":"):
            current = line.strip()[:-1]
            projects[current] = {}
    return {"projects": projects}


def api_call(method, *params):
    token = os.environ.get("API_AUTHENTICATION_TOKEN", "")
    if not token:
        raise KanboardError("API_AUTHENTICATION_TOKEN is missing")

    payload = json.dumps(
        {"jsonrpc": "2.0", "method": method, "id": 1, "params": list(params)}
    ).encode("utf-8")
    url = os.environ.get("KANBOARD_URL", "http://kanboard").rstrip("/") + "/jsonrpc.php"
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": "Basic "
            + base64.b64encode(f"jsonrpc:{token}".encode()).decode("ascii"),
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read()
    except urllib.error.HTTPError as exc:
        raise KanboardError(f"Kanboard API HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise KanboardError(f"Kanboard API unreachable: {exc.reason}") from exc

    data = json.loads(body.decode("utf-8"))
    if data.get("error"):
        raise KanboardError(data["error"].get("message", "Kanboard API error"))
    return data.get("result")


def request_origin(request_headers):
    host = request_headers.get("Host", "kanban.ai.dephekt.net")
    proto = request_headers.get("X-Forwarded-Proto")
    if proto not in {"http", "https"}:
        proto = "http" if host.startswith("containers.home.arpa") else "https"
    return f"{proto}://{host}"


def private_task_url(request_headers, task):
    query = urllib.parse.urlencode(
        {
            "controller": "TaskViewController",
            "action": "show",
            "task_id": task["id"],
            "project_id": task["project_id"],
        }
    )
    return f"{request_origin(request_headers)}/?{query}"


def public_task_url(request_headers, task, project_record):
    token = project_record.get("token")
    if not token:
        raise KanboardError("public project is missing public token")
    return f"{request_origin(request_headers)}/public/task/{task['id']}/{token}"


def is_enabled(value):
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value != 0
    if isinstance(value, str):
        return value.lower() in {"1", "true", "yes", "on"}
    return False


def task_url(request_headers, project_record, task):
    if is_enabled(project_record.get("is_public")):
        return public_task_url(request_headers, task, project_record)
    return private_task_url(request_headers, task)


class Handler(BaseHTTPRequestHandler):
    server_version = "kanban-ref/0.1"

    def do_GET(self):
        self.handle_request(send_body=True)

    def do_HEAD(self):
        self.handle_request(send_body=False)

    def handle_request(self, send_body):
        if self.path == "/healthz":
            self.send_json(200, {"status": 200}, send_body=send_body)
            return

        match = REF_RE.match(self.path)
        if match is None:
            self.send_json(404, {"error": "unknown route"}, send_body=send_body)
            return

        ref = match.group(1)
        prefix = ref.split("-", 1)[0]

        try:
            projects = load_projects(os.environ["KANBOARD_PROJECTS_FILE"])
            project = projects.get(prefix)
            if not project:
                self.send_json(
                    404,
                    {"error": "unknown task prefix", "reference": ref},
                    send_body=send_body,
                )
                return
            project_record = api_call("getProjectByName", project["name"])
            if not project_record:
                self.send_json(
                    404,
                    {"error": "unknown project", "reference": ref},
                    send_body=send_body,
                )
                return
            task = api_call("getTaskByReference", int(project_record["id"]), ref)
            if not task:
                self.send_json(
                    404,
                    {"error": "unknown task", "reference": ref},
                    send_body=send_body,
                )
                return
            location = task_url(self.headers, project_record, task)
        except (KeyError, KanboardError, OSError, ValueError) as exc:
            self.send_json(503, {"error": str(exc)}, send_body=send_body)
            return

        self.send_response(302)
        self.send_header("Location", location)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def log_message(self, fmt, *args):
        message = fmt % args
        sys.stderr.write(
            f"{self.address_string()} - - [{self.log_date_time_string()}] {message}\n"
        )

    def send_json(self, status, payload, send_body=True):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body:
            self.wfile.write(body)


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8080"))
    ThreadingHTTPServer((host, port), Handler).serve_forever()
