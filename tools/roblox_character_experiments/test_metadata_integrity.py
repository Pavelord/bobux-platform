import json
import unittest

import parse_output as p


class MetadataIntegrityTests(unittest.TestCase):
    def fixture(self):
        data = {"kind": "a4_standard_script_metadata", "schema": 2, "run_id": "own-test", "rig": "R6",
                "scripts": [{"path": "Own." + "x" * 600, "status": "OBSERVED"}]}
        raw = json.dumps(data)
        packets = [{"n": f"{offset + 1:06d}", "s": raw[offset:offset + 400]} for offset in range(0, len(raw), 400)]
        done = {"run_id": "own-test", "rig": "R6", "rows": 1, "bytes": len(raw.encode("utf-8"))}
        return data, packets, done

    def text(self, packets, done=None):
        text = "\n".join(p.METADATA + json.dumps(packet) for packet in packets)
        return text + ("\n" + p.METADATA_DONE + json.dumps(done) if done is not None else "")

    def test_complete_byte_exact_capture(self):
        data, packets, done = self.fixture()
        self.assertEqual(p.parse_metadata(self.text(packets, done)), data)

    def test_done_required(self):
        data, packets, done = self.fixture()
        with self.assertRaisesRegex(ValueError, "DONE"):
            p.parse_metadata(self.text(packets))

    def test_offset_gap_and_overlap_rejected(self):
        data, packets, done = self.fixture()
        for offset in (400, 402):
            changed = [dict(x) for x in packets]
            changed[1]["n"] = f"{offset:06d}"
            with self.assertRaisesRegex(ValueError, "gap/overlap"):
                p.parse_metadata(self.text(changed, done))

    def test_size_rows_and_run_binding_rejected(self):
        data, packets, done = self.fixture()
        for changed in (dict(done, bytes=done["bytes"] + 1), dict(done, rows=2), dict(done, run_id="other"), dict(done, rig="R15")):
            with self.assertRaises(ValueError):
                p.parse_metadata(self.text(packets, changed))

    def test_conflicting_duplicate_or_multiple_captures_rejected(self):
        data, packets, done = self.fixture()
        with self.assertRaisesRegex(ValueError, "conflicting"):
            p.parse_metadata(self.text(packets + [dict(packets[0], s="broken")], done))
        with self.assertRaisesRegex(ValueError, "one metadata"):
            p.parse_metadata(self.text(packets, done) + "\n" + p.METADATA_DONE + json.dumps(dict(done, run_id="other")))

    def test_command_echo_ignored(self):
        data, packets, done = self.fixture()
        echo = '[FLog::CreatorOutput] > print("CHARACTER_METADATA_DONE "..json)'
        self.assertEqual(p.parse_metadata(echo + "\n" + self.text(packets, done)), data)


if __name__ == "__main__":
    unittest.main()
