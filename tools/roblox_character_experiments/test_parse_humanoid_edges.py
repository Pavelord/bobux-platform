import base64
import hashlib
import json
import unittest

from parse_humanoid_edges import ARITY_IDS, DONE, ENABLED_IDS, EXPORT, METHODS, RECEIVER_IDS, decode, report


def fixture():
    rows = [{"kind": "manifest"}]
    rows += [{"kind": "enabled_string", "id": case,
              "operations": [{"enabled": flag, "call": {"ok": True}, "heartbeat_dt": [0.01, 0.01]} for flag in (False, True)]}
             for case in sorted(ENABLED_IDS)]
    rows += [{"kind": "method_call", "method": method, "category": category, "id": case,
              "call": {"ok": True}, "heartbeat_dt": [0.01, 0.01]}
             for method in sorted(METHODS) for category, cases in (("receiver", RECEIVER_IDS), ("arity", ARITY_IDS)) for case in sorted(cases)]
    for seq, row in enumerate(rows, 1):
        row.update(seq=seq, run_id="test-own-probe", status="OBSERVED")
    payload = dict(schema=1, kind="humanoid_edge_results", run_id="test-own-probe", rows=rows,
                   no_expected_outcomes=True, status="OBSERVED", date_utc="2026-10-15T00:00:00Z",
                   studio_version="synthetic-parser-test", enabled_cases=6, receiver_cases=36, arity_cases=48)
    raw = json.dumps(payload, separators=(",", ":")).encode()
    encoded = base64.b64encode(raw).decode()
    lines = []
    for seq, offset in enumerate(range(0, len(encoded), 400), 1):
        packet = dict(schema=1, run_id=payload["run_id"], seq=seq, i=offset + 1, s=encoded[offset:offset + 400])
        lines.append(EXPORT + json.dumps(packet, separators=(",", ":")))
    done = dict(schema=1, run_id=payload["run_id"], records=len(rows), packets=len(lines), raw_bytes=len(raw),
                encoded_bytes=len(encoded), raw_sha256=hashlib.sha256(raw).hexdigest(), encoding="base64", packet_bytes=400,
                max_export_line_bytes=max(map(len, lines)), status="OBSERVED", enabled_cases=6, receiver_cases=36,
                arity_cases=48, date_utc=payload["date_utc"], studio_version=payload["studio_version"])
    return raw, lines, DONE + json.dumps(done, separators=(",", ":"))


class EdgesParserTest(unittest.TestCase):
    def test_complete(self):
        expected, lines, done = fixture()
        raw, completion, issues, _ = decode(("\n".join(lines + [done])).encode())
        self.assertEqual(raw, expected)
        result = report(raw, completion, issues)
        self.assertEqual(result["status"], "OBSERVED")
        self.assertEqual(result["raw_rows"], 91)
        self.assertEqual(result["physical_ChangeState_status"], "NOT_OBSERVABLE_UNPARENTED_FIXTURE")

    def test_missing_packet(self):
        _, lines, done = fixture()
        raw, completion, issues, _ = decode(("\n".join(lines[:2] + lines[3:] + [done])).encode())
        self.assertEqual(report(raw, completion, issues)["status"], "BLOCKED")

    def test_conflicting_duplicate(self):
        _, lines, done = fixture()
        packet = json.loads(lines[0][len(EXPORT):])
        packet["s"] = "A" + packet["s"][1:]
        raw, completion, issues, _ = decode(("\n".join(lines + [EXPORT + json.dumps(packet), done])).encode())
        self.assertTrue(any("conflicting duplicate" in issue for issue in issues))
        self.assertEqual(report(raw, completion, issues)["status"], "BLOCKED")

    def test_hash_mismatch(self):
        _, lines, done = fixture()
        marker = json.loads(done[len(DONE):])
        marker["raw_sha256"] = "0" * 64
        raw, completion, issues, _ = decode(("\n".join(lines + [DONE + json.dumps(marker)])).encode())
        self.assertIn("raw SHA256 mismatch", issues)

    def test_echo_ignored_and_native_noise_not_decoded(self):
        expected, lines, done = fixture()
        text = b"native noise \xff\n" + b"[FLog::CreatorOutput] > print('HUMANOID_EDGE_DONE fake')\n"
        text += b"\n".join(b"[FLog::CreatorOutput] " + line.encode() for line in lines + [done])
        raw, completion, issues, _ = decode(text)
        self.assertEqual(raw, expected)
        self.assertEqual(report(raw, completion, issues)["status"], "OBSERVED")

    def test_malformed_own_utf8_blocks(self):
        _, lines, done = fixture()
        text = ("\n".join(lines + [done])).encode() + b"\nHUMANOID_EDGE_EXPORT \xff"
        raw, completion, issues, _ = decode(text)
        self.assertTrue(any("invalid UTF-8" in issue for issue in issues))
        self.assertEqual(report(raw, completion, issues)["status"], "BLOCKED")

    def test_line_limit(self):
        _, lines, done = fixture()
        packet = json.loads(lines[0][len(EXPORT):])
        packet["padding"] = "x" * 701
        raw, completion, issues, _ = decode(("\n".join(lines + [EXPORT + json.dumps(packet), done])).encode())
        self.assertTrue(any("exceeds 700" in issue for issue in issues))

    def test_incomplete_case_coverage_blocks(self):
        raw, lines, done = fixture()
        payload = json.loads(raw)
        payload["rows"].pop()
        result = report(json.dumps(payload).encode(), json.loads(done[len(DONE):]), [])
        self.assertEqual(result["status"], "BLOCKED")
        self.assertIn("case identity coverage incomplete/extra", result["parser_issues"])


if __name__ == "__main__":
    unittest.main()
