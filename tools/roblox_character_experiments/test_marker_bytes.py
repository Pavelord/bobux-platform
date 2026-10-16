import unittest

import marker_bytes as b


class MarkerByteTests(unittest.TestCase):
    marker = "OWN_TELEMETRY "

    def test_unrelated_non_utf8_and_command_echo_are_ignored(self):
        native = (b"\xd3\xf0\xe0 unrelated application line\n"
                  b"[FLog::CreatorOutput] > print(\"OWN_TELEMETRY \"..\xd3)\n"
                  b"[OtherLog] OWN_TELEMETRY {\xd3}\n"
                  b"[FLog::CreatorOutput] unrelated \xd3\n"
                  b"[FLog::CreatorOutput] OWN_TELEMETRY {\"own\":true}\n")
        text, issues = b.read_marker_bytes(native, (self.marker,))
        self.assertEqual(text, 'OWN_TELEMETRY {"own":true}')
        self.assertEqual(issues, [])

    def test_non_utf8_native_prefix_with_valid_payload_is_safe(self):
        text, issues = b.read_marker_bytes(b"native \xd3 [FLog::CreatorOutput] OWN_TELEMETRY {}", (self.marker,))
        self.assertEqual(text, "OWN_TELEMETRY {}")
        self.assertEqual(issues, [])

    def test_bad_utf8_own_payload_must_be_integrity_issue(self):
        text, issues = b.read_marker_bytes(b"noise\n[FLog::CreatorOutput] OWN_TELEMETRY {\"own\":\"\xd3\"}\n", (self.marker,))
        self.assertEqual(text, "")
        self.assertEqual(len(issues), 1)
        self.assertIn("invalid UTF-8", issues[0])
        self.assertIn("native line 2", issues[0])
        self.assertNotIn("\ufffd", text)

    def test_standalone_bom_crlf_and_cyrillic_payload(self):
        payload = 'OWN_TELEMETRY {"own":"Персонаж"}'
        text, issues = b.read_marker_bytes(b"\xef\xbb\xbf" + payload.encode("utf-8") + b"\r\n", (self.marker,))
        self.assertEqual(text, payload)
        self.assertEqual(issues, [])

    def test_inline_marker_never_matches(self):
        text, issues = b.read_marker_bytes(b"some text OWN_TELEMETRY {}", (self.marker,))
        self.assertEqual(text, "")
        self.assertEqual(issues, [])


if __name__ == "__main__":
    unittest.main()
