#!/usr/bin/env python3
"""Read-only RoomMarker iOS JSON v3/ZIP32 receiver check; Python 3.9+, stdlib only.

No extraction, network, source edits or pixel-decoder dependency. JPEG checks are
CRC/SHA-256, marker structure and dimensions, NOT a full entropy/pixel decode.
"""
import argparse
import hashlib
import html.parser
import json
import math
import re
import stat
import struct
import sys
import unicodedata
import urllib.parse
import uuid
import zipfile
from pathlib import Path

MAX_FILE = 512 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024
MAX_ENTRIES = 10000
TYPES = {"厕所", "楼梯", "门", "门禁", "电梯", "教室", "大门", "扶梯", "食堂", "商店", "其他室内"}
CHANNELS = ("accelerometer", "gyroscope")
STATES = {"notRequested", "waiting", "receiving", "unsupported", "denied", "unavailable", "paused", "stopped"}


class Invalid(ValueError):
    pass


def require(condition, category):
    if not condition:
        raise Invalid(category)


def safe_path(name):
    return (isinstance(name, str) and bool(name) and not name.startswith("/")
            and not any(ord(c) < 32 or ord(c) == 127 or c in "\\:" for c in name)
            and all(p not in ("", ".", "..") for p in name.split("/")))


def integer(value, category):
    require(type(value) is int, category)
    return value


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def identity(value):
    try:
        require(isinstance(value, str) and str(uuid.UUID(value)) == value, "noncanonical UUID")
    except (ValueError, TypeError, AttributeError) as error:
        raise Invalid("invalid UUID") from error
    return value


def records(values, category, global_ids=None):
    require(isinstance(values, list), category + " array")
    result = {}
    for row in values:
        key = identity(row["id"])
        require(key not in result, category + " duplicate ID")
        if global_ids is not None:
            require(key not in global_ids, category + " cross-track duplicate ID")
            global_ids.add(key)
        result[key] = row
    return result


def no_duplicate_keys(pairs):
    obj = {}
    for key, value in pairs:
        require(key not in obj, "duplicate JSON key")
        obj[key] = value
    return obj


def scan_json(value):
    if isinstance(value, dict):
        for key, child in value.items():
            require(key.casefold() not in {"wificount", "wifitop", "bssid", "rssi", "ssid"}, "unsupported Wi-Fi observation")
            scan_json(child)
    elif isinstance(value, list):
        for child in value:
            scan_json(child)
    elif isinstance(value, float):
        require(math.isfinite(value), "nonfinite JSON number")


def read_json(archive, name):
    value = json.loads(archive.read(name), object_pairs_hook=no_duplicate_keys,
                       parse_constant=lambda _: (_ for _ in ()).throw(Invalid("nonfinite JSON number")))
    scan_json(value)
    return value


def preflight(archive, raw):
    """Require this writer's single-disk, stored ZIP32 with contiguous records."""
    infos = archive.infolist()
    require(0 < len(infos) <= MAX_ENTRIES, "ZIP entry limit")
    require(sum(i.file_size for i in infos) <= MAX_TOTAL, "ZIP total size limit")
    names, cursor = set(), 0
    for info in infos:
        require(safe_path(info.filename) and info.orig_filename == info.filename, "unsafe ZIP path")
        normalized = unicodedata.normalize("NFC", info.filename).casefold()
        require(normalized not in names, "duplicate/case-alias ZIP path")
        names.add(normalized)
        mode = info.external_attr >> 16
        require(not stat.S_ISLNK(mode) and stat.S_IFMT(mode) in (0, stat.S_IFREG), "non-regular ZIP entry")
        require(info.compress_type == zipfile.ZIP_STORED and info.flag_bits & ~0x800 == 0,
                "unsupported ZIP compression/encryption/descriptor")
        require(0 <= info.file_size <= MAX_FILE and info.compress_size == info.file_size, "ZIP file size limit")
        require(info.header_offset == cursor, "ZIP prefix/overlap/gap")
        raw.seek(cursor)
        header = raw.read(30)
        require(len(header) == 30, "truncated ZIP header")
        fields = struct.unpack("<IHHHHHIIIHH", header)
        require(fields[0] == 0x04034B50 and fields[2] == info.flag_bits and fields[3] == 0,
                "ZIP local header")
        require(fields[6:9] == (info.CRC, info.compress_size, info.file_size), "ZIP local/central mismatch")
        name = raw.read(fields[9]).decode("utf-8" if info.flag_bits & 0x800 else "cp437")
        require(name == info.filename, "ZIP local/central path mismatch")
        require(fields[10] == 0, "unsupported ZIP local extra fields")
        cursor += 30 + fields[9] + fields[10] + info.file_size
    central_start = cursor
    for info in infos:
        raw.seek(cursor)
        header = raw.read(46)
        require(len(header) == 46, "truncated ZIP central directory")
        fields = struct.unpack("<IHHHHHHIIIHHHHHII", header)
        require(fields[0] == 0x02014B50 and fields[3] == info.flag_bits and fields[4] == 0,
                "ZIP central header")
        require(fields[7:10] == (info.CRC, info.compress_size, info.file_size) and fields[16] == info.header_offset,
                "ZIP central identity")
        require(fields[11:14] == (0, 0, 0), "unsupported ZIP central extras/comment/disk")
        name = raw.read(fields[10]).decode("utf-8" if info.flag_bits & 0x800 else "cp437")
        require(name == info.filename, "ZIP central path")
        cursor += 46 + fields[10]
    raw.seek(cursor)
    tail = raw.read(23)
    require(len(tail) == 22, "ZIP trailing data/comment or truncated EOCD")
    end = struct.unpack("<IHHHHIIH", tail)
    require(end == (0x06054B50, 0, 0, len(infos), len(infos), cursor - central_start, central_start, 0), "ZIP EOCD")
    return {i.filename: i for i in infos}


def platform(obj):
    require(type(obj["version"]) is int and obj["version"] == 3 and obj["sourcePlatform"] == "ios", "requires iOS JSON v3")
    require(obj["capabilities"]["nearbyWifiFingerprint"] == "unsupported", "Wi-Fi capability")


def sensor(row, quality=False):
    for key in ("latitude", "longitude", "altitude", "accuracy", "pressureHpa", "headingDeg", "magneticX", "magneticY", "magneticZ"):
        if row.get(key) is not None:
            require(finite(row[key]), "sensor number")
    if quality:
        require(row.get("accuracy") is None or row["accuracy"] >= 0, "negative accuracy")
        require(row.get("pressureHpa") is None or row["pressureHpa"] > 0, "invalid pressure")


def ordered(rows):
    times = [integer(r["timeMs"], "record timestamp") for r in rows]
    require(times == sorted(times), "record timestamp ordering")
    return max((b - a for a, b in zip(times, times[1:])), default=0)


def membership(row, track, segments):
    if not track["isSegmentedRecording"]:
        require(row.get("segmentId") is None, "legacy segment reference")
        return
    segment = segments.get(row.get("segmentId"))
    require(segment is not None, "missing segment reference")
    time = integer(row["timeMs"], "sample time")
    end = segment.get("endedAt")
    require(time >= segment["startedAt"] and (end is None or time < end or
            (time == end and segment["ordinal"] == len(segments) - 1)), "sample outside segment")


def validate_imu(track, segments, global_ids):
    imu = track["imu"]
    expected = {"accelerometerUnit": "g", "gyroscopeUnit": "rad/s", "accelerometerIncludesGravity": True,
                "coordinateFrame": "device-right-top-out", "sensorTimeBase": "secondsSinceBoot",
                "measurementTimeMapping": "utcMillisecondsFixedSessionAnchor", "backgroundPolicy": "foregroundOnlyNoCatchUp"}
    require(all(imu[k] == v and type(imu[k]) is type(v) for k, v in expected.items()), "IMU units/semantics")
    require(type(imu["requested"]) is bool and imu["accelerometerState"] in STATES and imu["gyroscopeState"] in STATES,
            "IMU state")
    require(integer(imu["rejectedCount"], "IMU rejectedCount") >= 0, "IMU rejectedCount")
    batches = records(imu["batches"], "IMU batch", global_ids)
    if imu["requested"]:
        require(track["isSegmentedRecording"] and finite(imu.get("requestedIntervalSeconds")) and imu["requestedIntervalSeconds"] > 0,
                "IMU request")
    else:
        require(not batches and imu.get("requestedIntervalSeconds") is None and imu["rejectedCount"] == 0 and
                imu["accelerometerState"] == imu["gyroscopeState"] == "notRequested", "legacy IMU")
    times = {k: set() for k in CHANNELS}
    counts = {k: 0 for k in CHANNELS}
    latency = None
    for batch in batches.values():
        samples = batch["samples"]
        require(0 < len(samples) <= 100 and integer(batch["sampleCount"], "batch count") == len(samples), "IMU batch size")
        require(batch["firstTimeMs"] == min(s["timeMs"] for s in samples) and batch["lastTimeMs"] == max(s["timeMs"] for s in samples),
                "IMU batch time range")
        for kind, count_key, last_key in [("accelerometer", "accelerationCount", "lastAccelerationTime"),
                                         ("gyroscope", "gyroscopeCount", "lastGyroscopeTime")]:
            channel = [s["sensorTimeSeconds"] for s in samples if s["kind"] == kind]
            require(integer(batch[count_key], "channel count") == len(channel) and
                    batch.get(last_key) == (max(channel) if channel else None) and
                    all(a < b for a, b in zip(channel, channel[1:])), "IMU channel count/order")
        for sample in samples:
            kind, seconds = sample["kind"], sample["sensorTimeSeconds"]
            require(kind in CHANNELS and finite(seconds) and seconds >= 0 and seconds not in times[kind], "IMU channel/time duplicate")
            require(all(finite(sample[k]) for k in ("x", "y", "z")), "IMU values")
            times[kind].add(seconds)
            counts[kind] += 1
            membership(sample, track, segments)
            delay = integer(sample["receivedAtMs"], "receive time") - sample["timeMs"]
            latency = delay if latency is None else max(latency, delay)
    require(integer(imu["sampleCount"], "IMU total") == sum(counts.values()) and
            integer(imu["accelerationCount"], "IMU acceleration total") == counts["accelerometer"] and
            integer(imu["gyroscopeCount"], "IMU gyroscope total") == counts["gyroscope"], "IMU totals")
    gaps = {}
    for kind in CHANNELS:
        sequence = sorted(times[kind])
        gaps[kind] = max((b - a for a, b in zip(sequence, sequence[1:])), default=0)
    return {"sampleCount": sum(counts.values()), "maxChannelGapSeconds": gaps, "maxReceiveDelayMs": latency}


def validate_track(track, entry, areas, rooms, global_ids):
    platform(track)
    require(entry["file"] == "tracks/" + identity(track["id"]) + ".json", "Track file identity")
    require(all(entry.get(k) == track.get(k) for k in ("id", "name", "startedAt", "endedAt", "counts")), "manifest/Track mismatch")
    start = integer(track["startedAt"], "start time")
    require(track.get("endedAt") is None or integer(track["endedAt"], "end time") >= start, "Track duration")
    require(type(track["isGlobalRecording"]) is bool and type(track["isSegmentedRecording"]) is bool, "Track flags")
    require(track.get("legacyAreaId") is None or track["legacyAreaId"] in areas, "legacy area reference")
    groups = {key: records(track[key], key, global_ids[key]) for key in ("points", "tags", "photos", "segments", "corners")}
    for key in ("points", "tags", "photos", "corners"):
        ordered(track[key])
        for row in track[key]:
            sensor(row, key in ("tags", "photos"))
    segments = groups["segments"]
    if track["isSegmentedRecording"]:
        require(bool(segments) and track["segments"][0]["startedAt"] == start, "initial segment")
        for i, segment in enumerate(track["segments"]):
            require(type(segment["ordinal"]) is int and segment["ordinal"] == i and segment["environment"] in ("unknown", "indoor", "outdoor"), "segment ordinal/environment")
            segment_start = integer(segment["startedAt"], "segment start")
            require(segment.get("endedAt") is None or integer(segment["endedAt"], "segment end") >= segment_start, "segment duration")
            if i + 1 < len(segments):
                next_start = track["segments"][i + 1]["startedAt"]
                require(segment.get("endedAt") == next_start and next_start > segment["startedAt"], "segment boundary")
            else:
                require(segment.get("endedAt") == track.get("endedAt"), "final segment end")
    else:
        require(not segments and not track["corners"], "legacy structure")
    for row in track["points"] + track["corners"]:
        membership(row, track, segments)
    for tag in track["tags"]:
        require(tag["tagType"] in TYPES and tag["recordKind"] in ("node", "legacy"), "tag type/kind")
        require((tag["areaState"] == "assigned" and tag.get("areaId") in areas) or
                (tag["areaState"] in ("unknown", "unassigned") and tag.get("areaId") is None), "tag area")
        linked = [p for p in track["photos"] if p.get("tagId") == tag["id"]]
        if tag["recordKind"] == "node":
            require(len(linked) == 1 and linked[0]["id"] == tag.get("photoId") and linked[0]["kind"] == "node", "node/photo link")
        else:
            require(not linked and tag.get("photoId") is None, "legacy tag binding")
        binding = tag.get("roomBinding")
        if binding:
            room_id = identity(binding["roomId"])
            require(tag["recordKind"] == "node" and tag["tagType"] in ("门", "门禁", "教室") and bool(binding["nameSnapshot"]), "room binding")
            require(binding.get("doorRole") is None if tag["tagType"] == "教室" else binding.get("doorRole") in ("前门", "后门"), "room door role")
            room = rooms.get(room_id)
            same = room is not None and tag["areaState"] == "assigned" and room.get("areaId") == tag.get("areaId")
            require(binding["status"] == ("missing" if room is None else "linked" if same else "relocated"), "room binding status")
    for photo in track["photos"]:
        path = photo["file"]
        require(safe_path(path) and path.startswith("photos/" + track["id"] + "/") and path.endswith(".jpg"), "photo path")
        require(photo["kind"] in ("node", "scenery", "legacyUnlinked"), "photo kind")
        if photo["kind"] == "node":
            tag = groups["tags"].get(photo.get("tagId"))
            require(tag is not None and tag["recordKind"] == "node" and tag.get("photoId") == photo["id"], "photo/node link")
            require(all(tag.get(k) == photo.get(k) for k in ("timeMs", "latitude", "longitude", "altitude", "headingDeg", "accuracy", "pressureHpa")),
                    "node/photo evidence mismatch")
        else:
            require(photo.get("tagId") is None, "independent photo binding")
    imu = validate_imu(track, segments, global_ids["batches"])
    expected = {"pointCount": len(track["points"]), "tagCount": len(track["tags"]), "nodeCount": sum(t["recordKind"] == "node" for t in track["tags"]),
                "photoCount": len(track["photos"]), "segmentCount": len(segments), "cornerCount": len(track["corners"]), "imuSampleCount": imu["sampleCount"]}
    require(track["counts"] == expected and all(type(n) is int for n in track["counts"].values()), "Track counts")
    return {"id": track["id"], "counts": expected, "maxPointGapMs": ordered(track["points"]), "imu": imu}


def jpeg_metadata(prefix, tail):
    require(prefix.startswith(b"\xff\xd8") and tail == b"\xff\xd9", "JPEG SOI/EOI")
    pos, dimensions, orientation = 2, None, None
    while pos + 4 <= len(prefix):
        require(prefix[pos] == 0xFF, "JPEG marker")
        while pos < len(prefix) and prefix[pos] == 0xFF:
            pos += 1
        require(pos < len(prefix), "JPEG marker truncated")
        marker = prefix[pos]
        pos += 1
        if marker in (0xDA, 0xD9):
            break
        length = int.from_bytes(prefix[pos:pos + 2], "big")
        require(length >= 2 and pos + length <= len(prefix), "JPEG header exceeds 1 MiB check limit/truncated")
        body = prefix[pos + 2:pos + length]
        if marker in (0xC0, 0xC1, 0xC2):
            require(len(body) >= 6, "JPEG SOF")
            dimensions = (int.from_bytes(body[3:5], "big"), int.from_bytes(body[1:3], "big"))
        if marker == 0xE1 and body.startswith(b"Exif\x00\x00"):
            tiff = body[6:]
            require(tiff[:2] in (b"II", b"MM") and len(tiff) >= 8, "EXIF header")
            endian = "<" if tiff[:2] == b"II" else ">"
            require(struct.unpack_from(endian + "H", tiff, 2)[0] == 42, "EXIF magic")
            offset = struct.unpack_from(endian + "I", tiff, 4)[0]
            require(offset + 2 <= len(tiff), "EXIF offset")
            count = struct.unpack_from(endian + "H", tiff, offset)[0]
            require(offset + 2 + count * 12 <= len(tiff), "EXIF directory")
            for i in range(count):
                at = offset + 2 + i * 12
                tag, typ, n = struct.unpack_from(endian + "HHI", tiff, at)
                if tag == 0x112:
                    require(typ == 3 and n == 1, "EXIF orientation type")
                    orientation = struct.unpack_from(endian + "H", tiff, at + 8)[0]
                    require(1 <= orientation <= 8, "EXIF orientation value")
        pos += length
    require(dimensions is not None and min(dimensions) > 0, "JPEG dimensions missing")
    return {"width": dimensions[0], "height": dimensions[1], "exifOrientation": orientation, "pixelDecode": "notPerformed"}


def check_photo(archive, photo, info):
    require(integer(photo["byteCount"], "photo bytes") == info.file_size and
            re.fullmatch(r"[0-9a-f]{64}", photo["sha256"]), "photo integrity metadata")
    digest, prefix, tail = hashlib.sha256(), bytearray(), b""
    with archive.open(info) as source:
        while True:
            chunk = source.read(65536)  # ZipFile also verifies CRC on complete reads.
            if not chunk:
                break
            digest.update(chunk)
            prefix.extend(chunk[:max(0, 1024 * 1024 - len(prefix))])
            tail = (tail + chunk)[-2:]
    require(digest.hexdigest() == photo["sha256"], "photo SHA-256 mismatch")
    return {"id": photo["id"], "byteCount": info.file_size, "sha256": digest.hexdigest(), **jpeg_metadata(prefix, tail)}


class IndexCheck(html.parser.HTMLParser):
    ALLOWED = {"html", "head", "meta", "title", "style", "body", "h1", "h2", "h3", "p", "section", "article", "small", "a", "img"}
    VOID = {"meta", "img"}

    def __init__(self, photos):
        super().__init__(convert_charrefs=True)
        self.photos, self.images, self.links, self.stack, self.csp = set(photos), [], [], [], False

    def handle_starttag(self, tag, attrs):
        require(tag in self.ALLOWED, "unsafe HTML tag")
        require(len(dict(attrs)) == len(attrs), "duplicate HTML attribute")
        allowed = {"html": {"lang"}, "meta": {"charset", "name", "content", "http-equiv"},
                   "a": {"href"}, "img": {"src", "alt", "loading"}}.get(tag, set())
        require(all(k in allowed for k, _ in attrs), "unsafe HTML attribute")
        values = dict(attrs)
        for key in ("src", "href"):
            if key in values:
                url = urllib.parse.urlsplit(values[key])
                path = urllib.parse.unquote(url.path)
                require(not url.scheme and not url.netloc and not url.query and not url.fragment and
                        safe_path(path) and path in self.photos, "HTML external/unsafe link")
                (self.images if key == "src" else self.links).append(path)
        if tag == "meta" and "http-equiv" in values:
            require(values["http-equiv"] == "Content-Security-Policy", "unsafe HTML meta")
            require(values.get("content") == "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'", "HTML CSP")
            self.csp = True
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        require(bool(self.stack) and self.stack.pop() == tag, "unbalanced HTML")

    def handle_data(self, data):
        if self.stack and self.stack[-1] == "style":
            require(not re.search(r"url\s*\(|@import|expression\s*\(|\\", data, re.I), "external/active CSS")

    def finish(self):
        self.close()
        require(self.csp and not self.stack and sorted(self.images) == sorted(self.photos) and
                sorted(self.links) == sorted(self.photos), "HTML photo inventory/structure")


def validate(path):
    with open(path, "rb") as raw, zipfile.ZipFile(raw) as archive:
        infos = preflight(archive, raw)
        require("manifest.json" in infos, "manifest missing")
        manifest = read_json(archive, "manifest.json")
        platform(manifest)
        require(manifest["app"] == "RoomMarker", "manifest app")
        areas = records(manifest["areas"], "areas")
        rooms = records(manifest.get("rooms") or [], "rooms")
        for room in rooms.values():
            require(room.get("areaId") is None or room["areaId"] in areas, "room area")
            sensor(room)
        entries = records(manifest["tracks"], "tracks")
        require(integer(manifest["trackCount"], "manifest count") == len(entries), "manifest count")
        scope = manifest["scope"]
        require(scope["kind"] in ("all", "area", "unassigned", "selected"), "scope")
        if scope["kind"] == "selected":
            selection = scope["trackIds"]
            require(bool(selection) and len(selection) == len(set(selection)) and set(selection) == set(entries), "selected Track IDs")
        else:
            require(scope.get("trackIds") is None, "unexpected selection")
        require(scope.get("areaId") in areas if scope["kind"] == "area" else scope.get("areaId") is None, "scope area")
        expected, results, photos = {"manifest.json"}, [], []
        global_ids = {key: set() for key in ("points", "tags", "photos", "segments", "corners", "batches")}
        photo_paths = []
        for entry in entries.values():
            name = entry["file"]
            require(name == "tracks/" + entry["id"] + ".json" and name in infos, "missing/unsafe Track entry")
            expected.add(name)
            track = read_json(archive, name)
            results.append(validate_track(track, entry, areas, rooms, global_ids))
            if scope["kind"] == "area":
                require((not track["isGlobalRecording"] and track.get("legacyAreaId") == scope["areaId"]) or
                        any(t["areaState"] == "assigned" and t.get("areaId") == scope["areaId"] for t in track["tags"]), "Track outside area scope")
            if scope["kind"] == "unassigned":
                require((not track["isGlobalRecording"] and track.get("legacyAreaId") is None) or
                        any(t["areaState"] == "unassigned" and t.get("areaId") is None for t in track["tags"]), "Track outside unassigned scope")
            for photo in track["photos"]:
                name = photo["file"]
                require(name in infos and name not in expected, "missing/duplicate photo entry")
                expected.add(name)
                photo_paths.append(name)
                photos.append(check_photo(archive, photo, infos[name]))
            del track  # At most one decoded Track JSON; not a streaming JSON parser.
        if manifest.get("photoIndex") is not None:
            require(manifest["photoIndex"] == "index.html" and "index.html" in infos, "HTML index reference")
            parser = IndexCheck(photo_paths)
            parser.feed(archive.read("index.html").decode("utf-8"))
            parser.finish()
            expected.add("index.html")
        require(expected == set(infos), "extra/staging/missing ZIP entries")
        return {"status": "passed", "format": "RoomMarker iOS v3", "entryCount": len(infos),
                "trackCount": len(results), "tracks": results, "photos": photos,
                "limits": {"maxFileBytes": MAX_FILE, "maxTotalBytes": MAX_TOTAL, "maxEntries": MAX_ENTRIES},
                "notes": ["Read-only; no extraction or upload.", "Gaps are reported, not filled. Archive consistency cannot prove measurement authenticity.",
                          "JPEG markers/dimensions/CRC/SHA-256 checked; full pixel decoding and human orientation review remain required."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.archive)
    except (Invalid, OSError, ValueError, KeyError, TypeError, IndexError, OverflowError, RecursionError, struct.error, zipfile.BadZipFile) as error:
        # Never dump file contents, absolute source paths or a traceback into a report.
        category = str(error) if isinstance(error, Invalid) else type(error).__name__
        print(json.dumps({"status": "failed", "category": category}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
