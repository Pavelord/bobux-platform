"""Fixture checks for banner-tolerant PM2 parsing and secret-free summaries."""
import json
import unittest
from verify_release_artifacts import parse_pm2_json, process_summary, remote_audit_code


class VerificationSafetyTests(unittest.TestCase):
    def test_pm2_banner_and_missing_optional_keys(self):
        processes = [{"name": "bobux", "pid": 10, "pm2_env": {"status": "online", "restart_time": 1}},
                     {"name": "bobux-api", "pid": 11, "pm2_env": {"status": "online"}}]
        output = "[PM2] Spawning PM2 daemon\n[notice] ignored banner\n" + json.dumps(processes) + "\n[PM2] done"
        self.assertEqual(parse_pm2_json(output), processes)
        self.assertEqual(len(process_summary(parse_pm2_json(output))), 2)

    def test_empty_and_invalid_pm2(self):
        self.assertEqual(parse_pm2_json("[PM2] banner\n[]\n"), [])
        with self.assertRaises(ValueError): parse_pm2_json("[PM2] banner only")
        with self.assertRaises(ValueError): parse_pm2_json('[{"not_a_process": true}]')

    def test_summary_never_emits_environment_or_logs(self):
        processes = [{"name": "bobux", "pid": 1, "pm2_env": {"status": "online", "env": {"PASSWORD": "fixture-secret"}, "pm_err_log_path": "secret-path", "pm_exec_path": "private-path"}},
                     {"name": "other", "pm2_env": {"status": "fixture-secret"}}]
        summary = process_summary(processes)
        encoded = json.dumps(summary)
        self.assertNotIn("secret", encoded)
        self.assertNotIn("private", encoded)
        self.assertNotIn("env", encoded)
        self.assertEqual(summary, [{"name": "bobux", "status": "online", "pid": 1, "restart_count": None}])

    def test_remote_code_is_compilable_and_read_only(self):
        source = remote_audit_code(["/downloads/example.zip"])
        compile(source, "<remote audit>", "exec")
        for mutation in ["write_text(", "write_bytes(", "pm2', 'restart", "pm2', 'stop", "unlink(", "mkdir(", "rmtree(", "chmod("]:
            self.assertNotIn(mutation, source)


if __name__ == "__main__": unittest.main()
