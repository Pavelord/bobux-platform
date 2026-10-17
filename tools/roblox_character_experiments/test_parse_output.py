import hashlib
import json
import unittest
import parse_output as p
import build_place


class EvidenceParserTests(unittest.TestCase):
    def raw(self):
        rows = [dict(kind="run_manifest", seq=1, run_id="test", mode="phase_a"),
                dict(kind="a2_native_getters", seq=2, run_id="test", rig="R6", profile="default", properties={"UseJumpPower":False}),
                dict(kind="run_result", seq=3, run_id="test", status="OBSERVED")]
        return "\n".join(p.PREFIX + json.dumps(r) for r in rows) + "\n"

    def export(self, raw):
        lines = []
        for i in range(0, len(raw), 40):
            lines.append("[FLog::CreatorOutput] " + p.EXPORT + json.dumps(dict(run_id="test",n="000001",i=i+1,s=raw[i:i+40])))
        lines.append(p.EXPORT_DONE + json.dumps(dict(run_id="test", bytes=len(raw.encode()), records=3)))
        return "\n".join(lines)

    def test_reconstruction_hash_and_false_preserved(self):
        raw = self.raw()
        decoded, manifest, issues = p.reconstruct(self.export(raw))
        self.assertEqual(decoded, raw)
        self.assertEqual(issues, [])
        rows, problems = p.parse_raw(decoded)
        self.assertEqual(problems, [])
        self.assertIs(rows[1]["properties"]["UseJumpPower"], False)
        data = p.report(rows, raw, [])
        self.assertEqual(data["raw_sha256"], hashlib.sha256(raw.encode()).hexdigest())
        self.assertEqual(data["parity_status"], "NOT_IMPLEMENTED_NOT_CALIBRATED")

    def test_missing_segment_is_detected(self):
        lines = self.export(self.raw()).splitlines()
        del lines[1]
        raw, manifest, issues = p.reconstruct("\n".join(lines))
        self.assertTrue(any("missing" in issue for issue in issues))
        self.assertTrue(any("mismatch" in issue for issue in issues))

    def test_truncated_native_log_is_not_accepted_as_complete(self):
        text = self.export(self.raw()).splitlines()[0]
        raw, manifest, issues = p.reconstruct(text)
        self.assertTrue(any("completion" in issue for issue in issues))

    def test_commandbar_echo_with_literal_marker_is_ignored(self):
        echo = '2026-10-14T16:10:00Z,1,thread,6 [FLog::CreatorOutput] > local h=game:GetService("HttpService"); print("CHARACTER_EXPORT_SMALL "..h:JSONEncode({n=v.Name,i=i,s=v.Value}))'
        done_echo = '2026-10-14T16:10:00Z,1,thread,6 [FLog::CreatorOutput] > print("CHARACTER_EXPORT_SMALL_DONE "..h:JSONEncode({run_id="test",bytes=1}))'
        raw, manifest, issues = p.reconstruct(echo + "\n" + done_echo + "\n" + self.export(self.raw()))
        self.assertEqual(raw,self.raw())
        self.assertEqual(issues,[])

    def test_real_anchored_malformed_packet_is_still_an_error(self):
        malformed = '[FLog::CreatorOutput] CHARACTER_EXPORT_SMALL {"n":"000001", "i":1, BROKEN_JSON}'
        raw, manifest, issues = p.reconstruct(self.export(self.raw()) + "\n" + malformed)
        self.assertTrue(any("malformed export" in issue for issue in issues))

    def test_sequence_gap_is_detected(self):
        rows, problems = p.parse_raw(self.raw().replace('"seq": 2', '"seq": 9'))
        self.assertTrue(any("gap" in issue for issue in problems))

    def test_utf8_offsets_are_bytes_not_characters(self):
        raw = self.raw().replace('"R6"', '"Персонаж R6"')
        packets = []
        offset = 1
        for i in range(0, len(raw), 40):
            segment = raw[i:i+40]
            packets.append(p.EXPORT + json.dumps(dict(run_id="test",n="000001",i=offset,s=segment)))
            offset += len(segment.encode("utf-8"))
        packets.append(p.EXPORT_DONE + json.dumps(dict(run_id="test",bytes=len(raw.encode("utf-8")),records=3)))
        reconstructed, manifest, issues = p.reconstruct("\n".join(packets))
        self.assertEqual(reconstructed,raw)
        self.assertEqual(issues,[])

    def test_multiple_runs_require_selection(self):
        text = self.export(self.raw()) + "\n" + self.export(self.raw()).replace('"run_id": "test"', '"run_id": "other"')
        raw, manifest, issues = p.reconstruct(text)
        self.assertTrue(any("multiple" in issue for issue in issues))

    def test_preregistered_45_disjoint_cases(self):
        matrix = build_place.matrix()
        cases = matrix["cases"]
        self.assertEqual(len(cases), 45)
        self.assertEqual(len({c["id"] for c in cases}), 45)
        train = {c["id"] for c in cases if c["split"] == "train"}
        holdout = {c["id"] for c in cases if c["split"] == "holdout"}
        self.assertEqual(len(train), 27)
        self.assertEqual(len(holdout), 18)
        self.assertFalse(train & holdout)

    def test_native_non_utf8_noise_does_not_change_raw_sha(self):
        native = b"unrelated \xd3\xf0\xe0\n" + self.export(self.raw()).encode("utf-8")
        text, encoding_issues = p.read_input_bytes(native)
        raw, manifest, issues = p.reconstruct(text)
        self.assertEqual(encoding_issues + issues, [])
        self.assertEqual(raw, self.raw())
        self.assertEqual(hashlib.sha256(raw.encode()).hexdigest(), hashlib.sha256(self.raw().encode()).hexdigest())

    def test_own_non_utf8_marker_blocks_even_with_other_complete_export(self):
        native = self.export(self.raw()).encode("utf-8") + b'\n[FLog::CreatorOutput] CHARACTER_EXPORT_SMALL {"s":"\xd3"}'
        text, encoding_issues = p.read_input_bytes(native)
        raw, manifest, issues = p.reconstruct(text)
        rows, problems = p.parse_raw(raw)
        data = p.report(rows, raw, encoding_issues + issues + problems)
        self.assertEqual(data["status"], "BLOCKED")
        self.assertTrue(any("invalid UTF-8" in issue for issue in data["parser_issues"]))

    def test_own_non_utf8_metadata_packet_blocks(self):
        text, encoding_issues = p.read_input_bytes(b'[FLog::CreatorOutput] CHARACTER_METADATA_EXPORT {"s":"\xd3"}', True)
        self.assertEqual(text, "")
        self.assertTrue(encoding_issues)


if __name__ == "__main__":
    unittest.main()
