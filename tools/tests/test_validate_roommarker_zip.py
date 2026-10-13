import copy
import hashlib
import importlib.util
import json
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "validate_roommarker_zip.py"
SPEC = importlib.util.spec_from_file_location("receiver", SCRIPT)
receiver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(receiver)
FIXTURES = SCRIPT.parents[1] / "RoomMarkerTests" / "Fixtures"
PHOTO_ID = "44444444-4444-4444-8444-444444444444"
SEGMENT_ID = "55555555-5555-4555-8555-555555555555"
BATCH_ID = "66666666-6666-4666-8666-666666666666"


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="roommarker-receiver-test-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "synthetic.zip"
        self.manifest = json.loads((FIXTURES / "stage5_legacy_manifest_v3.json").read_text())
        self.track = json.loads((FIXTURES / "stage5_legacy_track_v3.json").read_text())
        self.extras = {}

    def write(self, duplicate=None):
        with zipfile.ZipFile(self.path, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("manifest.json", json.dumps(self.manifest))
            archive.writestr(self.manifest["tracks"][0]["file"], json.dumps(self.track))
            for name, data in self.extras.items():
                archive.writestr(name, data)
            if duplicate:
                archive.writestr(duplicate, b"unexpected")

    def check(self):
        self.write()
        return receiver.validate(self.path)

    def reject(self):
        with self.assertRaises((receiver.Invalid, ValueError, KeyError, TypeError, zipfile.BadZipFile)):
            self.check()

    def sync(self):
        for key in ("name", "startedAt", "endedAt", "counts"):
            self.manifest["tracks"][0][key] = copy.deepcopy(self.track.get(key))

    def add_photo(self, node=False):
        # Marker-only fixture deliberately tests the stated NON-pixel-decoder boundary.
        # A real ImageIO-encoded JPEG is separately checked via the Swift integration artifact.
        jpeg = bytes.fromhex("ffd8 ffc0 000b 08 0002 0003 01 01 11 00 ffda 0008 01 01 00 00 3f 00 00 ffd9")
        name = "photos/" + self.track["id"] + "/synthetic.jpg"
        self.track["photos"] = [{"id": PHOTO_ID, "timeMs": 3000, "file": name, "note": "Synthetic", "createdAt": 3100,
                                 "kind": "node" if node else "scenery", "byteCount": len(jpeg), "sha256": hashlib.sha256(jpeg).hexdigest()}]
        self.track["counts"]["photoCount"] = 1
        if node:
            self.track["photos"][0]["tagId"] = self.track["tags"][0]["id"]
            self.track["tags"][0].update(recordKind="node", photoId=PHOTO_ID)
            self.track["counts"]["nodeCount"] = 1
        self.extras[name] = jpeg
        self.sync()
        return name

    def add_imu(self):
        self.track["isSegmentedRecording"] = True
        self.track["segments"] = [{"id": SEGMENT_ID, "ordinal": 0, "startedAt": 1000, "endedAt": 5000, "environment": "indoor"}]
        self.track["points"][0]["segmentId"] = SEGMENT_ID
        samples = [{"kind": "accelerometer", "sensorTimeSeconds": t, "timeMs": ms, "receivedAtMs": ms + 100,
                    "segmentId": SEGMENT_ID, "x": 0, "y": 0, "z": -1} for t, ms in [(11, 2000), (13, 4000)]]
        self.track["imu"].update(requested=True, requestedIntervalSeconds=0.02, accelerometerState="stopped", gyroscopeState="stopped",
                                 sampleCount=2, accelerationCount=2, gyroscopeCount=0,
                                 batches=[{"id": BATCH_ID, "sampleCount": 2, "accelerationCount": 2, "gyroscopeCount": 0,
                                           "firstTimeMs": 2000, "lastTimeMs": 4000, "lastAccelerationTime": 13, "samples": samples}])
        self.track["counts"].update(segmentCount=1, imuSampleCount=2)
        self.sync()

    def test_legacy_v3_without_index_catalog_or_quality(self):
        self.assertEqual(self.check()["trackCount"], 1)

    def test_selected_ids(self):
        self.manifest["scope"] = {"kind": "selected", "name": "Synthetic", "trackIds": [self.track["id"]]}
        self.assertEqual(self.check()["status"], "passed")
        self.manifest["scope"]["trackIds"] = []
        self.reject()

    def test_count_mismatch(self):
        self.manifest["trackCount"] += 1
        self.reject()

    def test_track_count_mismatch(self):
        self.track["counts"]["pointCount"] = 5
        self.sync()
        self.reject()

    def test_unsafe_entries(self):
        for name in ["../evil", "/private/evil", "C:/evil", "photos/../evil", "a\\evil", "a//b", "a\nb"]:
            with self.subTest(name=name):
                self.extras = {name: b"bad"}
                self.reject()

    def test_duplicate_alias_path(self):
        self.write("MANIFEST.JSON")
        with self.assertRaises(receiver.Invalid):
            receiver.validate(self.path)

    def test_staging_directory_leak(self):
        self.extras["staging/session/readme"] = b"bad"
        self.reject()

    def test_symlink_entry(self):
        self.write()
        with zipfile.ZipFile(self.path, "a") as archive:
            info = zipfile.ZipInfo("link")
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, "../../outside")
        with self.assertRaises(receiver.Invalid):
            receiver.validate(self.path)

    def test_crc_corruption(self):
        self.write()
        raw = bytearray(self.path.read_bytes())
        raw[30 + len("manifest.json") + 5] ^= 1
        self.path.write_bytes(raw)
        with self.assertRaises((receiver.Invalid, zipfile.BadZipFile, ValueError)):
            receiver.validate(self.path)

    def test_truncation_and_trailing_data(self):
        self.write()
        original = self.path.read_bytes()
        for data in [original[:-5], original + b"hidden"]:
            self.path.write_bytes(data)
            with self.assertRaises((receiver.Invalid, zipfile.BadZipFile)):
                receiver.validate(self.path)

    def test_local_header_name_mismatch(self):
        self.write()
        data = bytearray(self.path.read_bytes())
        data[30] = ord("X")
        self.path.write_bytes(data)
        with self.assertRaises(receiver.Invalid):
            receiver.validate(self.path)

    def test_zip_size_limit(self):
        self.write()
        old = receiver.MAX_FILE
        try:
            receiver.MAX_FILE = 1
            with self.assertRaises(receiver.Invalid):
                receiver.validate(self.path)
        finally:
            receiver.MAX_FILE = old

    def test_duplicate_json_key(self):
        with zipfile.ZipFile(self.path, "w") as archive:
            archive.writestr("manifest.json", '{"version":3,"version":3}')
        with self.assertRaises(receiver.Invalid):
            receiver.validate(self.path)

    def test_forbidden_wifi_or_platform(self):
        for key in ["BSSID", "rssi", "wifiCount", "wifiTop", "SSID"]:
            with self.subTest(key=key):
                self.track["points"][0][key] = 0
                self.reject()
                del self.track["points"][0][key]
        self.track["sourcePlatform"] = "harmony"
        self.reject()

    def test_nonfinite_sensor(self):
        self.track["points"][0]["latitude"] = float("inf")
        self.reject()

    def test_photo_hash_dimensions_and_readonly(self):
        self.add_photo()
        self.write()
        before = self.path.read_bytes()
        result = receiver.validate(self.path)
        self.assertEqual((result["photos"][0]["width"], result["photos"][0]["height"]), (3, 2))
        self.assertEqual(result["photos"][0]["pixelDecode"], "notPerformed")
        self.assertEqual(before, self.path.read_bytes())
        self.assertEqual(list(Path(self.temp.name).iterdir()), [self.path])

    def test_photo_hash_mismatch(self):
        self.add_photo()
        self.track["photos"][0]["sha256"] = "0" * 64
        self.reject()

    def test_photo_marker_failure(self):
        name = self.add_photo()
        data = b"not jpeg"
        self.extras[name] = data
        self.track["photos"][0].update(byteCount=len(data), sha256=hashlib.sha256(data).hexdigest())
        self.reject()

    def test_photo_missing_or_outside_track(self):
        name = self.add_photo()
        del self.extras[name]
        self.reject()
        self.track["photos"][0]["file"] = "photos/" + self.track["id"] + "-evil/a.jpg"
        self.reject()

    def test_node_photo_bidirectional_and_sensor_quality(self):
        self.add_photo(node=True)
        self.assertEqual(self.check()["status"], "passed")
        self.track["tags"][0]["accuracy"] = 3
        self.reject()
        self.track["photos"][0]["accuracy"] = 3
        self.assertEqual(self.check()["status"], "passed")
        self.track["photos"][0]["tagId"] = PHOTO_ID
        self.reject()

    def test_imu_gaps_and_no_resampling(self):
        self.add_imu()
        result = self.check()
        self.assertEqual(result["tracks"][0]["imu"]["maxChannelGapSeconds"]["accelerometer"], 2)
        self.assertEqual(result["tracks"][0]["imu"]["maxReceiveDelayMs"], 100)
        self.assertEqual(result["tracks"][0]["counts"]["imuSampleCount"], 2)

    def test_imu_duplicate_time(self):
        self.add_imu()
        self.track["imu"]["batches"][0]["samples"][1]["sensorTimeSeconds"] = 11
        self.reject()

    def test_segment_boundary_and_membership(self):
        self.add_imu()
        self.track["points"][0]["timeMs"] = 6000
        self.reject()

    def test_unknown_environment_not_inferred(self):
        self.add_imu()
        self.track["segments"][0]["environment"] = "unknown"
        self.assertEqual(self.check()["status"], "passed")

    def test_html_static_inventory_and_escaping(self):
        name = self.add_photo()
        self.manifest["photoIndex"] = "index.html"
        csp = "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
        html = '<html><head><meta http-equiv="Content-Security-Policy" content="' + csp + '"></head><body>'
        html += '<p>&lt;script&gt; harmless</p><a href="' + name + '"><img src="' + name + '"></a></body></html>'
        self.extras["index.html"] = html
        self.assertEqual(self.check()["status"], "passed")
        for bad in ['<script>alert(1)</script>', '<img src="https://example.invalid/a.jpg">',
                    '<meta http-equiv="refresh" content="0;https://example.invalid">', '<style>@import "https://example.invalid";</style>']:
            self.extras["index.html"] = html.replace("</body>", bad + "</body>")
            self.reject()

    def test_cli_failure_no_traceback_or_path_leak(self):
        result = subprocess.run([sys.executable, str(SCRIPT), str(self.path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["status"], "failed")
        self.assertNotIn(self.temp.name, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
