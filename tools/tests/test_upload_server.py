import http.client
import importlib.util
import json
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "upload_server.py"
SPEC = importlib.util.spec_from_file_location("upload_server", SCRIPT)
upload_server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(upload_server)


class UploadServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roommarker-upload-test-")
        self.addCleanup(self.temp.cleanup)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), upload_server.Handler)
        self.server.upload_dir = self.temp.name
        self.server.token = "synthetic-secret"
        self.server.max_bytes = 2 * 1024 * 1024
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop)

    def stop(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, token="synthetic-secret", filename="RoomMarker-test.zip", data=None, bearer=True):
        boundary = "RoomMarker-SyntheticBoundary"
        archive = data if data is not None else b"PK\x03\x04" + bytes(range(256)) * 8 + b"\r\nfinal"
        body = bytearray()
        body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name=\"token\"\r\n\r\n{token}\r\n".encode())
        body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\nContent-Type: application/zip\r\n\r\n".encode())
        body.extend(archive)
        body.extend(f"\r\n--{boundary}--\r\n".encode())
        headers = {"Content-Type": f"multipart/form-data; boundary={boundary}"}
        if bearer:
            headers["Authorization"] = f"Bearer {token}"
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        connection.request("POST", "/upload", body=bytes(body), headers=headers)
        response = connection.getresponse()
        payload = json.loads(response.read())
        connection.close()
        return response.status, payload, archive

    def files(self):
        return [path for path in Path(self.temp.name).iterdir() if path.is_file()]

    def test_streamed_upload_preserves_every_archive_byte(self):
        status, payload, archive = self.request(bearer=False)
        self.assertEqual(status, 200)
        self.assertEqual(payload["size"], len(archive))
        files = self.files()
        self.assertEqual(len(files), 1)
        self.assertEqual(files[0].read_bytes(), archive)
        self.assertEqual(payload["sha256"], __import__("hashlib").sha256(archive).hexdigest())
        self.assertFalse(any(path.name.startswith(".incoming-") for path in files))

    def test_bearer_authentication_and_safe_filename(self):
        status, payload, archive = self.request(filename="../../unsafe.zip", token="synthetic-secret")
        self.assertEqual(status, 200)
        self.assertNotIn("/", payload["file"])
        self.assertNotIn("..", payload["file"])
        self.assertEqual(self.files()[0].read_bytes(), archive)

    def test_bad_token_and_invalid_archive_leave_no_partial_file(self):
        status, _, _ = self.request(token="wrong", bearer=False)
        self.assertEqual(status, 403)
        self.assertEqual(self.files(), [])
        status, _, _ = self.request(data=b"not-a-zip")
        self.assertEqual(status, 400)
        self.assertEqual(self.files(), [])

    def test_health_does_not_disclose_local_storage_path(self):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        connection.request("GET", "/health")
        response = connection.getresponse()
        body = response.read().decode()
        connection.close()
        self.assertEqual(response.status, 200)
        self.assertNotIn(self.temp.name, body)

    def test_file_list_and_download_require_token_when_enabled(self):
        status, payload, archive = self.request()
        self.assertEqual(status, 200)
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        connection.request("GET", "/")
        response = connection.getresponse()
        response.read()
        self.assertEqual(response.status, 403)
        connection.close()

        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        connection.request("GET", "/?k=synthetic-secret")
        response = connection.getresponse()
        listing = response.read().decode()
        self.assertEqual(response.status, 200)
        self.assertIn("?k=synthetic-secret", listing)
        connection.close()

        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        connection.request("GET", "/files/" + payload["file"] + "?k=synthetic-secret")
        response = connection.getresponse()
        downloaded = response.read()
        self.assertEqual(response.status, 200)
        self.assertEqual(downloaded, archive)
        connection.close()

    def test_request_limit_rejects_before_writing(self):
        self.server.max_bytes = 100
        status, _, _ = self.request()
        self.assertEqual(status, 413)
        self.assertEqual(self.files(), [])


if __name__ == "__main__":
    unittest.main()
