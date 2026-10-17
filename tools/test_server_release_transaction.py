#!/usr/bin/env python3
"""Exercise rollback with account/env files and new release modules present."""

import argparse
import io
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from server_release_transaction import snapshot, restore, safe_target, copy_api_entry, retire_legacy


class ServerReleaseTransactionTests(unittest.TestCase):
    def write(self, root: Path, relative: str, content: str) -> Path:
        file = root / relative
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")
        return file

    def test_snapshot_restore_removes_new_code_preserves_live_data_and_restores_downloads(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            server = root / "server"
            api = root / "api"
            web = root / "web"
            self.write(server, "autoload/runtime.gd", "old runtime")
            self.write(server, "autoload/supabase_client.gd", "retired shim")
            self.write(server, "supabase/.temp/project-ref", "retired local metadata")
            self.write(api, "server.js", "old API")
            self.write(api, "node_modules/example/index.js", "old dependency")
            self.write(api, ".env", "protected environment")
            self.write(api, "data/account.json", "live account")
            self.write(api, "social.sqlite", "live database")
            self.write(web, "launcher/latest.json", "old manifest")
            self.write(web, "downloads/Bobux-Windows.zip", "old package")
            nginx = self.write(root, "nginx.conf", "old nginx")
            archive = root / "release.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                for name in ["./autoload/runtime.gd", "./autoload/new.gd"]:
                    info = tarfile.TarInfo(name)
                    info.size = 3
                    tar.addfile(info, io.BytesIO(b"new"))
            backup = root / "rollback"
            args = argparse.Namespace(archive=archive, backup=backup, server_root=server, api_root=api, web_root=web,
                                      versioned_windows="new.zip", versioned_mobile="new.apk")
            with patch("server_release_transaction.NGINX_SITE", nginx):
                snapshot(args)
                retire_legacy(argparse.Namespace(backup=backup))
                self.assertFalse((server / "supabase").exists())
                self.assertFalse((server / "autoload/supabase_client.gd").exists())
                self.write(server, "autoload/runtime.gd", "new runtime")
                self.write(server, "autoload/new.gd", "new module")
                self.write(api, "server.js", "new API")
                self.write(api, "new_query.mjs", "new module")
                self.write(api, "node_modules/example/index.js", "new dependency")
                self.write(api, "data/account.json", "account changed while upgrading")
                self.write(api, "social.sqlite-wal", "current WAL")
                self.write(web, "launcher/latest.json", "new manifest")
                self.write(web, "downloads/Bobux-Windows.zip", "new package")
                self.write(web, "downloads/new.zip", "new versioned package")
                nginx.write_text("new nginx", encoding="utf-8")
                restore(argparse.Namespace(backup=backup))
            self.assertEqual((server / "autoload/runtime.gd").read_text(), "old runtime")
            self.assertFalse((server / "autoload/new.gd").exists())
            self.assertEqual((server / "autoload/supabase_client.gd").read_text(), "retired shim")
            self.assertEqual((server / "supabase/.temp/project-ref").read_text(), "retired local metadata")
            self.assertEqual((api / "server.js").read_text(), "old API")
            self.assertEqual((api / "node_modules/example/index.js").read_text(), "old dependency")
            self.assertFalse((api / "new_query.mjs").exists())
            self.assertEqual((api / ".env").read_text(), "protected environment")
            self.assertEqual((api / "data/account.json").read_text(), "account changed while upgrading")
            self.assertEqual((api / "social.sqlite-wal").read_text(), "current WAL")
            self.assertEqual((web / "launcher/latest.json").read_text(), "old manifest")
            self.assertEqual((web / "downloads/Bobux-Windows.zip").read_text(), "old package")
            self.assertFalse((web / "downloads/new.zip").exists())
            self.assertEqual(nginx.read_text(), "old nginx")

    def test_path_traversal_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(ValueError):
                safe_target(Path(temporary), "../../protected")

    def test_dependency_links_keep_relative_targets_inside_the_api(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "api"
            self.write(source, "node_modules/mime/cli.js", "old dependency")
            link = source / "node_modules/.bin/mime"
            link.parent.mkdir(parents=True)
            try:
                link.symlink_to("../mime/cli.js")
            except OSError:
                self.skipTest("Creating symbolic links requires host permission")
            destination = root / "backup/node_modules/.bin/mime"
            copy_api_entry(link, destination, source)
            self.assertTrue(destination.is_symlink())
            self.assertEqual(destination.readlink(), Path("../mime/cli.js"))


if __name__ == "__main__":
    unittest.main()
