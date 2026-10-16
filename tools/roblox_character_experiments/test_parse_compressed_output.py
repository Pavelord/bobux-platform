import base64
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys
import tempfile
import unittest

import zstandard as zstd

import parse_compressed_output as p


class CompressedExportTests(unittest.TestCase):
    def fixture(self, raw_bytes=None):
        if raw_bytes is None:
            own_noise = "".join(random.Random(1729).choices("abcdef0123456789", k=5000))
            rows = [{"kind": "run_manifest", "schema": 1, "seq": 1, "run_id": "own-test", "mode": "phase_a"},
                    {"kind": "own_test_data", "seq": 2, "run_id": "own-test", "data": own_noise},
                    {"kind": "run_result", "seq": 3, "run_id": "own-test", "status": "OBSERVED"}]
            raw_bytes = ("\n".join("CHARACTER_EXPERIMENT_JSON " + json.dumps(row) for row in rows) + "\n").encode("utf-8")
        compressed = zstd.ZstdCompressor(level=3).compress(raw_bytes)
        encoded = base64.b64encode(compressed).decode("ascii")
        packets = [{"schema": 1, "run_id": "own-test", "seq": seq + 1, "i": start + 1, "s": encoded[start:start + 400]}
                   for seq, start in enumerate(range(0, len(encoded), 400))]
        done = {"schema": 1, "run_id": "own-test", "encoding": "base64", "compression": "zstd", "compression_level": 3,
                "encoded_bytes": len(encoded), "compressed_bytes": len(compressed), "raw_bytes": len(raw_bytes), "raw_records": 3,
                "packets": len(packets), "packet_bytes": 400, "raw_sha256": hashlib.sha256(raw_bytes).hexdigest(),
                "compressed_sha256": hashlib.sha256(compressed).hexdigest(), "codec_policy": "Own regression fixture only"}
        return raw_bytes, packets, done

    def text(self, packets, done):
        return "\n".join(p.EXPORT + json.dumps(packet) for packet in packets) + "\n" + p.DONE + json.dumps(done)

    def test_raw_byte_sha_and_records_exact(self):
        expected, packets, done = self.fixture()
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, done))
        self.assertEqual(raw, expected)
        self.assertEqual(issues, [])
        text, data = p.report(raw, manifest, issues)
        self.assertEqual(data["compressed_transport"]["status"], "VERIFIED")
        self.assertEqual(data["status"], "OBSERVED")
        self.assertEqual(data["raw_sha256"], hashlib.sha256(expected).hexdigest())

    def test_packet_gap_rejected(self):
        expected, packets, done = self.fixture()
        del packets[1]
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, done))
        self.assertTrue(any("missing/overlapping" in issue for issue in issues))
        self.assertEqual(raw, b"")

    def test_conflicting_duplicate_rejected(self):
        expected, packets, done = self.fixture()
        duplicate = dict(packets[0], s="broken")
        raw, manifest, issues, retained = p.reconstruct(self.text(packets + [duplicate], done))
        self.assertTrue(any("conflicting" in issue for issue in issues))

    def test_missing_completion_rejected(self):
        expected, packets, done = self.fixture()
        raw, manifest, issues, retained = p.reconstruct("\n".join(p.EXPORT + json.dumps(x) for x in packets))
        self.assertTrue(any("completion" in issue for issue in issues))

    def test_base64_invalid_character_rejected(self):
        expected, packets, done = self.fixture()
        packets[0]["s"] = "!" + packets[0]["s"][1:]
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, done))
        self.assertEqual(raw, b"")
        self.assertTrue(any("integrity failure" in issue for issue in issues))

    def test_hash_or_size_mismatch_rejected(self):
        expected, packets, done = self.fixture()
        for changed in (dict(done, raw_sha256="0" * 64), dict(done, compressed_sha256="0" * 64), dict(done, raw_bytes=done["raw_bytes"] + 1)):
            raw, manifest, issues, retained = p.reconstruct(self.text(packets, changed))
            self.assertEqual(raw, b"")
            self.assertTrue(issues)

    def test_fake_boolean_schema_and_caps_rejected(self):
        expected, packets, done = self.fixture()
        for changed in (dict(done, schema=True), dict(done, raw_bytes=p.RAW_LIMIT + 1), dict(done, compressed_bytes=p.RAW_LIMIT + 1), dict(done, raw_records=True)):
            raw, manifest, issues, retained = p.reconstruct(self.text(packets, changed))
            self.assertTrue(issues)
            self.assertEqual(raw, b"")

    def test_compressed_non_utf8_raw_is_not_repaired(self):
        expected, packets, done = self.fixture(b"CHARACTER_EXPERIMENT_JSON {\"own\":\"\xd3\"}\n")
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, done))
        self.assertEqual(raw, expected)
        text, data = p.report(raw, manifest, issues)
        self.assertEqual(data["compressed_transport"]["status"], "BLOCKED")
        self.assertNotIn("\ufffd", text)
        self.assertEqual(data["raw_sha256"], hashlib.sha256(expected).hexdigest())

    def test_raw_record_wrong_json_type_blocks(self):
        expected, packets, done = self.fixture(b"CHARACTER_EXPERIMENT_JSON []\n")
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, done))
        text, data = p.report(raw, manifest, issues)
        self.assertEqual(data["status"], "BLOCKED")
        self.assertTrue(any("not an object" in issue for issue in data["parser_issues"]))

    def test_raw_record_count_and_run_binding_rejected(self):
        expected, packets, done = self.fixture()
        raw, manifest, issues, retained = p.reconstruct(self.text(packets, dict(done, raw_records=4)))
        text, data = p.report(raw, manifest, issues)
        self.assertEqual(data["compressed_transport"]["status"], "BLOCKED")
        self.assertTrue(any("record count" in issue for issue in data["parser_issues"]))
        manifest["raw_records"] = 3
        manifest["run_id"] = "other"
        text, data = p.report(raw, manifest, [])
        self.assertTrue(any("run_id" in issue for issue in data["parser_issues"]))

    def test_known_and_unknown_zstd_bomb_size_caps(self):
        for known in (True, False):
            compressed = zstd.ZstdCompressor(write_content_size=known).compress(b"own" * 1000)
            with self.assertRaises(ValueError):
                p.decompress_limited(compressed, 1000, limit=1000)

    def test_trailing_extra_zstd_frame_rejected(self):
        compressed = zstd.ZstdCompressor().compress(b"own")
        with self.assertRaises(zstd.ZstdError):
            p.decompress_limited(compressed + compressed, 3)

    def test_non_utf8_own_marker_blocked_noise_ignored(self):
        expected, packets, done = self.fixture()
        valid = self.text(packets, done).encode("utf-8")
        text, issues = p.read_input_bytes(b"native \xd3 noise\n" + valid)
        self.assertEqual(issues, [])
        raw, manifest, reconstruction_issues, retained = p.reconstruct(text)
        self.assertEqual(raw, expected)
        text, issues = p.read_input_bytes(valid + b'\n[FLog::CreatorOutput] CHARACTER_ZSTD_EXPORT {"s":"\xd3"}')
        raw, manifest, reconstruction_issues, retained = p.reconstruct(text)
        _, data = p.report(raw, manifest, issues + reconstruction_issues)
        self.assertEqual(data["compressed_transport"]["status"], "BLOCKED")

    def test_no_evidence_overwrite(self):
        expected, packets, done = self.fixture()
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "input.log"
            source.write_text(self.text(packets, done))
            stem = Path(tmp) / "already_exists"
            protected = stem.with_suffix(".raw.log")
            protected.write_bytes(b"own immutable fixture")
            result = subprocess.run([sys.executable, str(Path(p.__file__)), str(source), "--output", str(stem)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"Refusing to overwrite", result.stderr)
            self.assertEqual(protected.read_bytes(), b"own immutable fixture")


if __name__ == "__main__":
    unittest.main()
