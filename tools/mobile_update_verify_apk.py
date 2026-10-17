"""Verify the final Android package contains the exact bundled trailer and Luau.

Read-only verification, independent of Android account data or API credentials.
"""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--output", type=Path,
                        default=ROOT / ".codex-tmp/mobile_update_qa/fullgame/apk_contents_report.json")
    args = parser.parse_args()
    package = args.apk.resolve()
    checks = []
    files = ["assets/video/bobux_halloween_2026.ogv"]
    libraries = ["libbobuxluau.android.template_release.arm64.so",
                 "libbobuxluau.android.template_release.arm32.so"]
    with zipfile.ZipFile(package) as archive:
        for local in files:
            data = archive.read("assets/" + local)
            source = (ROOT / local).read_bytes()
            checks.append({"path": local, "bytes": len(data), "sha256": sha(data),
                           "matches_source": data == source})
        for library in libraries:
            architecture = "arm64-v8a" if "arm64" in library else "armeabi-v7a"
            data = archive.read("lib/" + architecture + "/" + library)
            source = (ROOT / "addons/luaAPI/bin" / library).read_bytes()
            checks.append({"path": library, "bytes": len(data), "sha256": sha(data),
                           "matches_source": data == source and len(data) > 100_000})
        # The compression stream itself must be intact before installation.
        corrupt = archive.testzip()
    report = {"apk": str(package), "bytes": package.stat().st_size,
              "sha256": sha(package.read_bytes()), "checks": checks,
              "archive_crc_ok": corrupt is None,
              "ok": corrupt is None and all(value["matches_source"] for value in checks)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ANDROID_APK_CONTENTS_REPORT=" + json.dumps(report))
    raise SystemExit(0 if report["ok"] else 1)


if __name__ == "__main__":
    main()
