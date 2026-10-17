import io
import tarfile
import tempfile
import unittest
import zipfile
from pathlib import Path

from validate_native_release_artifacts import BIN, MINIMUM_NATIVE_BYTES, PLATFORMS, packaged_libraries, source_identity, validate_native_archive


class NativeReleaseArtifactTests(unittest.TestCase):
    def sources(self, root: Path) -> None:
        for suffix, platform in PLATFORMS.items():
            payload = bytearray(MINIMUM_NATIVE_BYTES)
            if platform[0] == "pe":
                payload[:2] = b"MZ"
                payload[60:64] = (64).to_bytes(4, "little")
                payload[64:68] = b"PE\0\0"
                payload[68:70] = platform[1].to_bytes(2, "little")
            else:
                payload[:4] = b"\x7fELF"
                payload[4] = platform[1]
                payload[18:20] = platform[2].to_bytes(2, "little")
            path = root / (BIN + "libbobuxluau." + suffix)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)

    def package(self, root: Path, kind: str, damaged: bool = False, stale: bool = False) -> Path:
        target = root / ("package.zip" if kind in {"windows", "apk"} else "package.tar.gz")
        payloads = {}
        for name, suffix in packaged_libraries(kind).items():
            data = (root / (BIN + "libbobuxluau." + suffix)).read_bytes()
            if damaged:
                data = b""
            if stale:
                data = data[:-1] + b"x"
            payloads[name] = data
        if target.suffix == ".zip":
            with zipfile.ZipFile(target, "w") as archive:
                for name, data in payloads.items():
                    archive.writestr(name, data)
        else:
            with tarfile.open(target, "w:gz") as archive:
                for name, data in payloads.items():
                    member = tarfile.TarInfo("./" + name)
                    member.size = len(data)
                    archive.addfile(member, io.BytesIO(data))
        return target

    def test_all_platform_packages_require_exact_native_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.sources(root)
            for kind in ("windows", "apk", "linux", "server"):
                with self.subTest(kind=kind):
                    self.assertTrue(validate_native_archive(kind, self.package(root, kind), root))
                    with self.assertRaises(ValueError):
                        validate_native_archive(kind, self.package(root, kind, damaged=True), root)
                    with self.assertRaises(ValueError):
                        validate_native_archive(kind, self.package(root, kind, stale=True), root)

    def test_truncated_source_or_wrong_architecture_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.sources(root)
            suffix = "android.template_release.arm64.so"
            source = root / (BIN + "libbobuxluau." + suffix)
            source.write_bytes(b"")
            with self.assertRaises(ValueError):
                source_identity(root, suffix)
            self.sources(root)
            payload = bytearray(source.read_bytes())
            payload[4] = 1
            source.write_bytes(payload)
            with self.assertRaises(ValueError):
                source_identity(root, suffix)

    def test_linux_godot_export_uses_flat_library_and_distinguishes_missing_entry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.sources(root)
            library = "libbobuxluau.linux.template_release.x86_64.so"
            data = (root / BIN / library).read_bytes()
            archive = root / "linux.tar.gz"
            for entry in ("Bobux/" + library, "Bobux/" + BIN + library):
                with tarfile.open(archive, "w:gz") as package:
                    member = tarfile.TarInfo(entry)
                    member.size = len(data)
                    package.addfile(member, io.BytesIO(data))
                if entry == "Bobux/" + library:
                    self.assertTrue(validate_native_archive("linux", archive, root))
                else:
                    with self.assertRaisesRegex(ValueError, "missing required entry"):
                        validate_native_archive("linux", archive, root)
if __name__ == "__main__":
    unittest.main()
