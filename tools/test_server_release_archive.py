#!/usr/bin/env python3
"""Regression checks for upload archive safety and native runtime completeness."""

import io
import tarfile
import tempfile
import unittest
import re
import subprocess
import os
from pathlib import Path

from validate_server_release_archive import REQUIRED_FILES, validate_archive


class ServerReleaseArchiveTests(unittest.TestCase):
    def write_archive(self, path: Path, extra: str | None = None, omit: str | None = None, link: bool = False) -> None:
        with tarfile.open(path, "w:gz") as archive:
            for name in sorted(REQUIRED_FILES - ({omit} if omit else set())):
                payload = bytes(256 * 1024) if name.endswith(".so") else b"runtime"
                member = tarfile.TarInfo("./" + name)
                member.size = len(payload)
                archive.addfile(member, io.BytesIO(payload))
            if extra:
                member = tarfile.TarInfo(extra)
                if link:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "/etc/passwd"
                    archive.addfile(member)
                else:
                    member.size = 5
                    archive.addfile(member, io.BytesIO(b"extra"))

    def test_complete_runtime_retains_native_libraries(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "valid.tar.gz"
            self.write_archive(archive, "./services/bobux_api/.env.example")
            result = validate_archive(archive)
            self.assertEqual(result["files"], len(REQUIRED_FILES) + 1)

    def test_missing_server_native_library_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "missing.tar.gz"
            self.write_archive(archive, omit="addons/luaAPI/bin/libbobuxluau.linux.template_debug.x86_64.so")
            with self.assertRaisesRegex(ValueError, "missing required"):
                validate_archive(archive)

    def test_caches_secrets_databases_intermediates_and_path_traversal_are_rejected(self) -> None:
        prohibited = [
            "./.dist/performance/test.apk", "./.codex-tmp/cache.json",
            "./services/bobux_api/.env", "./services/bobux_api/.env.production",
            "./tools/mobile/signing.keystore", "./services/bobux_api/data/maps.json",
            "./services/bobux_api/social.sqlite-wal", "./native/luau_bridge/build-linux/runtime.so",
            "./addons/luaAPI/bin/runtime.lib", "../../etc/passwd",
            "./supabase/.temp/project-ref", "./autoload/supabase_client.gd",
            "./tools/rbxl_compare/rbxdom_oracle/target/release/oracle.exe",
        ]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "unsafe.tar.gz"
            for extra in prohibited:
                with self.subTest(path=extra):
                    self.write_archive(archive, extra)
                    with self.assertRaises(ValueError):
                        validate_archive(archive)

    def test_links_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "link.tar.gz"
            self.write_archive(archive, "./ops/vps/link", link=True)
            with self.assertRaisesRegex(ValueError, "contains a link"):
                validate_archive(archive)

    def test_actual_powershell_tar_filters_keep_runtime_and_drop_test_builds(self) -> None:
        script = Path(__file__).with_name("deploy_bobux_release.ps1").read_text(encoding="utf-8-sig")
        filters = ["--exclude=" + match.replace("$inactivePracticeFolder", "практика") for match in re.findall(r'--exclude="([^"]+)"', script)]
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory) / "project"
            project.mkdir()
            for name in REQUIRED_FILES | {".dist/performance/test.apk", ".codex-tmp/cache.json", "native/luau_bridge/build-linux/VM/lstate.o",
                                          "native/luau_bridge/src/runtime.obj", "tools/mobile/signing.keystore", "services/bobux_api/.env",
                                          "practice_report_qa/report.png", "практика/report.docx", "export_templates/template.exe",
                                          "supabase/.temp/project-ref", "autoload/supabase_client.gd", "autoload/supabase_client.gd.uid",
                                          "services/bobux_api/data/accounts.json", "native/vendor/project/.git/config"}:
                file = project / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(bytes(256 * 1024) if name.endswith(".so") else b"fixture")
            archive = Path(directory) / "release.tar.gz"
            rust_target = project / "tools/rbxl_compare/rbxdom_oracle/target/release"
            rust_target.mkdir(parents=True)
            (rust_target / "oracle.exe").write_bytes(b"diagnostic build")
            os.link(rust_target / "oracle.exe", rust_target / "oracle-hardlink.exe")
            subprocess.run(["tar", "-czf", str(archive), *filters, "."], cwd=project, capture_output=True, check=True)
            self.assertEqual(validate_archive(archive)["files"], len(REQUIRED_FILES))


if __name__ == "__main__":
    unittest.main()
