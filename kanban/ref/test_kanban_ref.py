import http.client
import os
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from unittest import mock

import kanban_ref


class KanbanRefHandlerTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.projects_file = os.path.join(self.tempdir.name, "projects.yaml")
        with open(self.projects_file, "w", encoding="utf-8") as handle:
            handle.write("projects:\n  HGC:\n    name: Hydro Grow Control\n")

        self.project_record = {
            "id": "1",
            "name": "Hydro Grow Control",
            "is_public": "1",
            "token": "837ffef1c79917c32d6ed0f994e5ab6f4442cd25f3ca60da3acf6fceaf61",
        }
        self.task = {"id": "4", "project_id": "1"}

        self.env_patch = mock.patch.dict(
            os.environ,
            {
                "KANBOARD_PROJECTS_FILE": self.projects_file,
                "API_AUTHENTICATION_TOKEN": "test-token",
            },
        )
        self.api_patch = mock.patch("kanban_ref.api_call", side_effect=self.api_call)
        self.env_patch.start()
        self.api_patch.start()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), kanban_ref.Handler)
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
        self.api_patch.stop()
        self.env_patch.stop()
        self.tempdir.cleanup()

    def api_call(self, method, *params):
        if method == "getProjectByName":
            self.assertEqual(params, ("Hydro Grow Control",))
            return self.project_record
        if method == "getTaskByReference":
            self.assertEqual(params, (1, "HGC-004"))
            return self.task
        raise AssertionError(f"unexpected API method: {method}")

    def request(self, path, method="HEAD", headers=None):
        connection = http.client.HTTPConnection(
            self.server.server_address[0], self.server.server_address[1]
        )
        connection.request(method, path, headers=headers or {})
        response = connection.getresponse()
        body = response.read()
        connection.close()
        return response, body

    def test_public_project_redirects_to_public_task_url(self):
        response, _ = self.request(
            "/i/HGC-004",
            headers={
                "Host": "kanban.ai.dephekt.net",
                "X-Forwarded-Proto": "https",
            },
        )

        self.assertEqual(response.status, 302)
        self.assertEqual(
            response.getheader("Location"),
            "https://kanban.ai.dephekt.net/public/task/4/"
            "837ffef1c79917c32d6ed0f994e5ab6f4442cd25f3ca60da3acf6fceaf61",
        )

    def test_private_project_redirects_to_authenticated_task_url(self):
        self.project_record["is_public"] = "0"

        response, _ = self.request(
            "/i/HGC-004",
            headers={"Host": "containers.home.arpa:8097"},
        )

        self.assertEqual(response.status, 302)
        self.assertEqual(
            response.getheader("Location"),
            "http://containers.home.arpa:8097/?controller=TaskViewController&"
            "action=show&task_id=4&project_id=1",
        )

    def test_unknown_prefix_returns_not_found_without_api_lookup(self):
        with mock.patch("kanban_ref.api_call") as api_call:
            response, _ = self.request("/i/ABC-004")

        self.assertEqual(response.status, 404)
        api_call.assert_not_called()

    def test_public_project_without_token_returns_service_unavailable(self):
        self.project_record["token"] = ""

        response, body = self.request("/i/HGC-004", method="GET")

        self.assertEqual(response.status, 503)
        self.assertIn(b"public project is missing public token", body)


if __name__ == "__main__":
    unittest.main()
