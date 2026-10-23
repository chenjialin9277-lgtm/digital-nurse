#!/usr/bin/env python3
"""Check a Git checkout's handoff files without third-party Python packages."""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    failures = []
    manifest = json.loads((ROOT / "docs/asset-manifest.json").read_text())
    declared = {item["path"] for item in manifest["files"]}
    actual = {
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "assets").rglob("*")
        if path.is_file() and path.name != ".DS_Store" and "downloads" not in path.parts
    }
    for path in sorted(actual ^ declared):
        failures.append(f"Asset manifest mismatch: {path}")
    for item in manifest["files"]:
        path = ROOT / item["path"]
        if not path.is_file():
            continue  # Reported by the set comparison above.
        data = path.read_bytes()
        if len(data) != item["size"] or hashlib.sha256(data).hexdigest() != item["sha256"]:
            failures.append(f"Asset missing, modified or still an LFS pointer: {item['path']}")

    tracked = subprocess.check_output(
        ["git", "ls-files", "-z"], cwd=ROOT
    ).decode().split("\0")
    for name in sorted(declared - set(tracked)):
        failures.append(f"Asset exists locally but is not tracked: {name}")
    secret_patterns = {
        "private key": rb"-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----",
        "GitHub token": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})\b",
        "AWS access key": rb"\bAKIA[A-Z0-9]{16}\b",
        "credential URL": rb"https?://[^\s/@:]+:[^\s/@]+@",
    }
    forbidden_name = re.compile(
        r"(^|/)(key\.properties|\.env(?!\.example$)[^/]*|id_rsa|id_ed25519|"
        r"[^/]+\.(jks|keystore|pem|p12|pfx|apk|aab|ipa))$"
    )
    for name in filter(None, tracked):
        path = ROOT / name
        if forbidden_name.search(name) or any(
            part in name for part in ("/node_modules/", "/.vitepress/cache/", "test/failures/")
        ) or name.startswith(("build/", "android/build/", "ios/build/", "macos/build/")):
            failures.append(f"Private or generated file is tracked: {name}")
        if not path.is_file():
            failures.append(f"Tracked file is missing: {name}")
            continue
        if path.stat().st_size > 5 * 1024 * 1024:
            continue
        data = path.read_bytes()
        for label, pattern in secret_patterns.items():
            if re.search(pattern, data):
                failures.append(f"Possible {label}: {name}")

    if failures:
        print("\n".join(failures), file=sys.stderr)
        print("For LFS pointer errors, run: git lfs install && git lfs pull", file=sys.stderr)
        return 1
    print(f"Repository checks passed: {len(list(filter(None, tracked)))} tracked files; "
          f"{len(manifest['files'])} verified assets.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
