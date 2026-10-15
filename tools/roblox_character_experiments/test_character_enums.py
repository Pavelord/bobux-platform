import base64
import hashlib
import json
from pathlib import Path
import unittest

import parse_character_enums as parser
from parse_humanoid_edges import decode

RAW = Path(__file__).resolve().parents[2] / "tests/roblox_humanoid/phase_a/2026-10-15-studio-character-enums-run01.raw.json"


def transport(raw):
    data = json.loads(raw)
    encoded = base64.b64encode(raw).decode("ascii")
    lines = []
    for seq, start in enumerate(range(0, len(encoded), 400), 1):
        lines.append(parser.EXPORT + json.dumps({"schema": 1, "run_id": data["run_id"],
                                                "seq": seq, "i": start + 1, "s": encoded[start:start + 400]}, separators=(",", ":")))
    done = {key: data[key] for key in ("run_id", "date_utc", "studio_version", "status", "domain_count", "canonical_item_count", "alias_count", "blocked_domains")}
    done.update(schema=1, encoding="base64", packet_bytes=400, packets=len(lines), raw_bytes=len(raw),
                encoded_bytes=len(encoded), raw_sha256=hashlib.sha256(raw).hexdigest(),
                max_export_line_bytes=max(len(line.encode()) for line in lines))
    lines.append(parser.DONE + json.dumps(done, separators=(",", ":")))
    return lines, done


class CharacterEnums(unittest.TestCase):
    def setUp(self):
        self.raw = RAW.read_bytes()

    def test_actual_capture_byte_roundtrip_and_semantics(self):
        lines, _ = transport(self.raw)
        rebuilt, done, issues, _ = decode("\n".join(lines).encode(), export_marker=parser.EXPORT, done_marker=parser.DONE)
        self.assertEqual(rebuilt, self.raw)
        report = parser.report(rebuilt, done, issues)
        self.assertEqual(report["status"], "OBSERVED")
        self.assertEqual((report["domain_count"], report["canonical_item_count"]), (10, 99))

    def test_missing_packet_and_wrong_sha_rejected(self):
        lines, _ = transport(self.raw)
        del lines[2]
        _, _, issues, _ = decode("\n".join(lines).encode(), export_marker=parser.EXPORT, done_marker=parser.DONE)
        self.assertTrue(any("gap/overlap" in issue for issue in issues))
        self.assertTrue(any("SHA256" in issue for issue in issues))

    def test_missing_domain_cannot_be_observed(self):
        data = json.loads(self.raw)
        data["families"].pop()
        result = parser.report(json.dumps(data).encode(), None, [])
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("ten requested domains are incomplete/extra", result["parser_issues"])

    def test_duplicate_value_and_wrong_shape_rejected(self):
        data = json.loads(self.raw)
        data["families"][0]["items"][1]["Value"] = data["families"][0]["items"][0]["Value"]
        data["families"][1]["name"] = []
        data["aliases"] = [{"domain": [], "alias": []}]
        result = parser.report(json.dumps(data).encode(), None, [])
        self.assertEqual(result["status"], "BLOCKED")
        self.assertGreaterEqual(len(result["parser_issues"]), 3)

    def test_done_mismatch_and_corrupt_utf8_rejected(self):
        _, done = transport(self.raw)
        done["canonical_item_count"] += 1
        self.assertEqual(parser.report(self.raw, done, [])["status"], "BLOCKED")
        self.assertEqual(parser.report(b"\xff", None, [])["status"], "BLOCKED")


if __name__ == "__main__":
    unittest.main()
