import json
import unittest

import parse_enum_coercion as p


class EnumCoercionParserTests(unittest.TestCase):
    def fixture(self):
        payload = dict(schema=1, kind="enum_coercion_results", run_id="test", studio_version="fixture",
                       no_expected_outcomes=True, status="OBSERVED", blocked_rows=0,
                       rows=[dict(id="fixture", seq=1, run_id="test", context="fresh", status="OBSERVED", ok=False,
                                  error="Русский текст")])
        raw = json.dumps(payload, ensure_ascii=False)
        lines, offset = [], 1
        for begin in range(0, len(raw), 35):
            segment = raw[begin:begin+35]
            lines.append(p.EXPORT + json.dumps(dict(run_id="test", n=f"{offset:06d}", i=offset, s=segment), ensure_ascii=False))
            offset += len(segment.encode("utf-8"))
        lines.append(p.DONE + json.dumps(dict(run_id="test", bytes=len(raw.encode("utf-8")), rows=1, status="OBSERVED", blocked_rows=0)))
        return raw, lines

    def test_native_errors_are_observations_not_failures(self):
        raw, lines = self.fixture()
        decoded, done, issues, retained = p.reconstruct("\n".join(lines))
        self.assertEqual(raw, decoded)
        self.assertEqual(issues, [])
        self.assertEqual(p.report(decoded, done, issues)["status"], "OBSERVED")
        self.assertEqual(p.report(decoded, done, issues)["native_pcall_outcomes"], {"False": 1})

    def test_missing_segment_blocked(self):
        raw, lines = self.fixture()
        del lines[1]
        decoded, done, issues, retained = p.reconstruct("\n".join(lines))
        self.assertTrue(any("missing/overlapping" in issue for issue in issues))
        self.assertEqual(p.report(decoded, done, issues)["status"], "BLOCKED")

    def test_missing_completion_blocked(self):
        raw, lines = self.fixture()
        decoded, done, issues, retained = p.reconstruct("\n".join(lines[:-1]))
        self.assertIn("completion marker missing", issues)

    def test_commandbar_echo_ignored(self):
        raw, lines = self.fixture()
        echo = '[FLog::CreatorOutput] > print("ENUM_COERCION_EXPORT "..json)'
        decoded, done, issues, retained = p.reconstruct(echo + "\n" + "\n".join(lines))
        self.assertEqual(decoded, raw)
        self.assertEqual(issues, [])
        self.assertEqual(len(retained), len(lines))

    def test_conflicting_duplicate_blocked(self):
        raw, lines = self.fixture()
        record = json.loads(lines[0][len(p.EXPORT):])
        record["s"] = "conflict"
        lines.append(p.EXPORT + json.dumps(record))
        decoded, done, issues, retained = p.reconstruct("\n".join(lines))
        self.assertTrue(any("conflicting duplicate" in issue for issue in issues))

    def test_row_count_and_sequence_blocked(self):
        raw, lines = self.fixture()
        decoded, done, issues, retained = p.reconstruct("\n".join(lines))
        done["rows"] = 2
        payload = json.loads(decoded)
        payload["rows"][0]["seq"] = 7
        report = p.report(json.dumps(payload), done, issues)
        self.assertTrue(any("row count" in issue for issue in report["parser_issues"]))
        self.assertTrue(any("sequence gap" in issue for issue in report["parser_issues"]))

    def test_multiple_runs_need_selection(self):
        raw, lines = self.fixture()
        text = "\n".join(lines + [line.replace('"test"', '"other"') for line in lines])
        decoded, done, issues, retained = p.reconstruct(text)
        self.assertTrue(any("specify --run-id" in issue for issue in issues))
        decoded, done, issues, retained = p.reconstruct(text, "test")
        self.assertEqual(decoded, raw)
        self.assertEqual(issues, [])

    def test_native_non_utf8_noise_is_ignored(self):
        raw, lines = self.fixture()
        native = b"unrelated \xd3\xf0\xe0\n" + "\n".join(lines).encode("utf-8")
        text, encoding_issues = p.read_input_bytes(native)
        decoded, done, issues, retained = p.reconstruct(text)
        self.assertEqual(decoded, raw)
        self.assertEqual(encoding_issues + issues, [])
        self.assertEqual(p.report(decoded, done, encoding_issues + issues)["status"], "OBSERVED")

    def test_own_non_utf8_packet_blocks_even_with_complete_export(self):
        raw, lines = self.fixture()
        native = "\n".join(lines).encode("utf-8") + b'\n[FLog::CreatorOutput] ENUM_COERCION_EXPORT {"s":"\xd3"}'
        text, encoding_issues = p.read_input_bytes(native)
        decoded, done, issues, retained = p.reconstruct(text)
        data = p.report(decoded, done, encoding_issues + issues)
        self.assertEqual(data["status"], "BLOCKED")
        self.assertTrue(any("invalid UTF-8" in issue for issue in data["parser_issues"]))


if __name__ == "__main__":
    unittest.main()
