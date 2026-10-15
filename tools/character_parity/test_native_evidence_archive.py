import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import zstandard as zstd

import native_evidence_archive as archive


class NativeArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.raw = self.root / "own.raw.log"
        self.packed = self.root / "own.raw.log.zstd"
        self.manifest = self.root / "own.raw.log.zstd.json"
        self.restored = self.root / "restored.raw.log"
        self.value = ('CHARACTER_EXPERIMENT_JSON {"name":"собственное измерение","seq":1}\r\n' * 7).encode()
        self.raw.write_bytes(self.value)

    def create(self):
        return archive.pack(self.raw, self.packed, self.manifest, self.root)

    def test_byte_roundtrip_and_original_unchanged(self):
        manifest = self.create()
        archive.unpack(self.packed, self.manifest, self.restored, self.root)
        self.assertEqual(self.raw.read_bytes(), self.value)
        self.assertEqual(self.restored.read_bytes(), self.value)
        self.assertEqual(manifest["raw_sha256"], hashlib.sha256(self.value).hexdigest())
        self.assertEqual(zstd.frame_content_size(self.packed.read_bytes()), len(self.value))

    def test_packed_sha_corruption(self):
        manifest = self.create()
        value = bytearray(self.packed.read_bytes())
        value[-1] ^= 1
        with self.assertRaisesRegex(ValueError, "Packed SHA256"):
            archive.decode_packed(bytes(value), manifest)

    def test_raw_sha_corruption(self):
        manifest = self.create()
        manifest["raw_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "Raw byte size/SHA256"):
            archive.decode_packed(self.packed.read_bytes(), manifest)

    def test_extra_frame_even_with_matching_packed_hash(self):
        manifest = self.create()
        value = self.packed.read_bytes() + zstd.ZstdCompressor(write_checksum=True).compress(b"extra own data")
        manifest.update(packed_bytes=len(value), packed_sha256=archive.digest(value))
        with self.assertRaises(zstd.ZstdError):
            archive.decode_packed(value, manifest)

    def test_overlimit_header_before_decompression(self):
        manifest = self.create()
        with patch.object(archive, "MAX_RAW_BYTES", len(self.value) - 1):
            with self.assertRaisesRegex(ValueError, "cap"):
                archive.decode_packed(self.packed.read_bytes(), manifest)

    def test_frame_size_mismatch(self):
        manifest = self.create()
        manifest["raw_bytes"] += 1
        with self.assertRaisesRegex(ValueError, "frame content size"):
            archive.decode_packed(self.packed.read_bytes(), manifest)

    def test_unknown_frame_size_rejected(self):
        manifest = self.create()
        value = zstd.ZstdCompressor(write_content_size=False, write_checksum=True).compress(self.value)
        manifest.update(packed_bytes=len(value), packed_sha256=archive.digest(value))
        with self.assertRaisesRegex(ValueError, "frame content size"):
            archive.decode_packed(value, manifest)

    def test_pack_and_unpack_refuse_overwrites(self):
        self.create()
        snapshot = (self.packed.read_bytes(), self.manifest.read_bytes())
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.create()
        self.restored.write_bytes(b"keep existing")
        with self.assertRaisesRegex(ValueError, "overwrite"):
            archive.unpack(self.packed, self.manifest, self.restored, self.root)
        self.assertEqual(self.restored.read_bytes(), b"keep existing")
        self.assertEqual(snapshot, (self.packed.read_bytes(), self.manifest.read_bytes()))

    def test_existing_sidecar_creates_no_archive(self):
        self.manifest.write_text("keep existing", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "overwrite"):
            self.create()
        self.assertFalse(self.packed.exists())

    def test_manifest_never_selects_output_path(self):
        self.create()
        data = json.loads(self.manifest.read_text())
        data.update(source_basename="../outside.raw.log", output="../outside.raw.log")
        self.manifest.write_text(json.dumps(data), encoding="utf-8")
        archive.unpack(self.packed, self.manifest, self.restored, self.root)
        self.assertEqual(self.restored.read_bytes(), self.value)
        self.assertFalse((self.root.parent / "outside.raw.log").exists())

    def test_output_escape_rejected(self):
        with self.assertRaisesRegex(ValueError, "workspace"):
            archive.pack(self.raw, self.root / "../escape.raw.log.zstd", self.manifest, self.root)

    def test_non_utf8_source_rejected_before_writes(self):
        self.raw.write_bytes(b"own marker\xff")
        with self.assertRaises(UnicodeDecodeError):
            self.create()
        self.assertFalse(self.packed.exists())
        self.assertFalse(self.manifest.exists())


if __name__ == "__main__":
    unittest.main()
