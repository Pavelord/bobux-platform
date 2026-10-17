"""Safety and completeness contracts for actual release benchmarks."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from run_pc_performance import (
    MAPS, ROOT, assert_guest_userdata, client_log_source, guest_environment,
    isolated_path, public_server_url, validate_report,
)
from run_android_release_performance import device_serial, reverse_preexists, validate_android_report


def clean_report():
    return {"tag": "contract", "platform": "Windows", "failures": [],
            "results": [{"map": key, "run": 0, "frame": {"frames": 10},
                         "runtime": {"failed": 0}, "touch_start": key in {"park", "valley"}}
                        for key in MAPS]}


class ReleaseRunnerContracts(unittest.TestCase):
    def test_public_url_has_no_account_data(self):
        self.assertEqual(public_server_url("ws://109.71.245.162/ws"), "ws://109.71.245.162/ws")
        for url in ["http://example.test", "ws://guest@host/ws", "ws://host/ws?token=test", "ws://host/ws#fragment", "ws://"]:
            with self.assertRaises(ValueError): public_server_url(url)

    def test_paths_cannot_escape_diagnostic_workspace(self):
        with self.assertRaises(ValueError): isolated_path(ROOT / "tools")
        self.assertTrue(isolated_path(ROOT / ".codex-tmp/runner-contract").is_relative_to(ROOT / ".codex-tmp"))

    def test_guest_environment_drops_inherited_credentials(self):
        with patch.dict("os.environ", {"BOBUX_SERVICE_TOKEN": "private", "CODEX_TEST_USER_ID": "account", "GODOT_SERVER_MAP": "private"}):
            env = guest_environment(ROOT / ".codex-tmp/runner-contract", 17861)
        self.assertNotIn("BOBUX_SERVICE_TOKEN", env)
        self.assertNotIn("CODEX_TEST_USER_ID", env)
        self.assertNotIn("GODOT_SERVER_MAP", env)

    def test_saved_account_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".codex-tmp") as name:
            folder = Path(name)
            profile = folder / "Godot/app_userdata/Bobux/session/current_profile.json"
            profile.parent.mkdir(parents=True)
            profile.write_text(json.dumps({"user_id": "fixture-account"}), encoding="utf-8")
            with self.assertRaises(ValueError): assert_guest_userdata(folder)

    def test_empty_filelogger_uses_captured_console(self):
        with tempfile.TemporaryDirectory(dir=ROOT / ".codex-tmp") as name:
            file, console = Path(name) / "client.log", Path(name) / "console.log"
            file.write_text("", encoding="utf-8")
            console.write_text("captured output", encoding="utf-8")
            self.assertEqual(client_log_source(file, console), console)
            file.write_text("file output", encoding="utf-8")
            self.assertEqual(client_log_source(file, console), file)

    def test_all_maps_must_complete_once(self):
        report = clean_report()
        validate_report(report, list(MAPS), 1, "contract", 0)
        report["results"].pop()
        with self.assertRaises(RuntimeError): validate_report(report, list(MAPS), 1, "contract", 0)
        report = clean_report()
        report["results"].append(report["results"][0])
        with self.assertRaises(RuntimeError): validate_report(report, list(MAPS), 1, "contract", 0)

    def test_failed_start_and_luau_do_not_pass(self):
        report = clean_report()
        report["results"][0]["touch_start"] = False
        with self.assertRaises(RuntimeError): validate_report(report, list(MAPS), 1, "contract", 0)
        report = clean_report()
        report["results"][0]["runtime"]["failed"] = 1
        with self.assertRaises(RuntimeError): validate_report(report, list(MAPS), 1, "contract", 0)

    def test_android_requires_pinned_authorized_device(self):
        with patch("run_android_release_performance.adb_run", return_value="List of devices attached\nold\tdevice\nnew\tunauthorized\n"):
            self.assertEqual(device_serial(Path("adb"), "old"), "old")
            with self.assertRaises(RuntimeError): device_serial(Path("adb"), "new")

    def test_android_existing_reverse_is_preserved_or_rejected(self):
        with patch("run_android_release_performance.adb_run", return_value="UsbFfs tcp:17860 tcp:17860"):
            self.assertTrue(reverse_preexists(Path("adb"), "old", 17860))
        with patch("run_android_release_performance.adb_run", return_value="UsbFfs tcp:17860 tcp:9999"):
            with self.assertRaises(RuntimeError): reverse_preexists(Path("adb"), "old", 17860)

    def test_android_partial_report_is_rejected(self):
        report = dict(clean_report(), report_seen=True, errors=[])
        validate_android_report(report, list(MAPS), 1)
        report["results"].pop()
        with self.assertRaises(RuntimeError): validate_android_report(report, list(MAPS), 1)


if __name__ == "__main__": unittest.main()
