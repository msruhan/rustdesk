#!/usr/bin/env python3
"""Patch Flutter/Windows/macOS branding files for IndoDesk User vs Teknisi builds."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BRANDING = {
    "user": {
        "app_name": "IndoDesk User",
        "bundle_id": "com.indoteknisi.indodesk.user",
        "binary_name": "indodesk-user",
        "file_description": "IndoDesk User Remote Assistance",
    },
    "teknisi": {
        "app_name": "IndoDesk Teknisi",
        "bundle_id": "com.indoteknisi.indodesk.teknisi",
        "binary_name": "indodesk-teknisi",
        "file_description": "IndoDesk Teknisi Remote Assistance",
    },
}


def patch_file(path: Path, replacers: list[tuple[str, str]]) -> None:
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in replacers:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"patched {path.relative_to(ROOT)}")


def main() -> int:
    role = os.environ.get("INODESK_ROLE", "").strip().lower()
    if role not in BRANDING:
        print(f"INODESK_ROLE must be user or teknisi, got: {role!r}", file=sys.stderr)
        return 1

    b = BRANDING[role]
    os.environ["INODESK_APP_NAME"] = b["app_name"]

    patch_file(
        ROOT / "flutter/macos/Runner/Configs/AppInfo.xcconfig",
        [
            ("PRODUCT_NAME = IndoDesk", f"PRODUCT_NAME = {b['app_name']}"),
            (
                "PRODUCT_BUNDLE_IDENTIFIER = com.carriez.flutterHbb",
                f"PRODUCT_BUNDLE_IDENTIFIER = {b['bundle_id']}",
            ),
        ],
    )

    patch_file(
        ROOT / "flutter/windows/CMakeLists.txt",
        [
            ('set(BINARY_NAME "indodesk")', f'set(BINARY_NAME "{b["binary_name"]}")'),
        ],
    )

    patch_file(
        ROOT / "flutter/windows/runner/Runner.rc",
        [
            (
                'VALUE "FileDescription", "IndoDesk Remote Assistance" "\\0"',
                f'VALUE "FileDescription", "{b["file_description"]}" "\\0"',
            ),
            (
                'VALUE "InternalName", "indodesk" "\\0"',
                f'VALUE "InternalName", "{b["binary_name"]}" "\\0"',
            ),
            (
                'VALUE "OriginalFilename", "indodesk.exe" "\\0"',
                f'VALUE "OriginalFilename", "{b["binary_name"]}.exe" "\\0"',
            ),
            (
                'VALUE "ProductName", "IndoDesk" "\\0"',
                f'VALUE "ProductName", "{b["app_name"]}" "\\0"',
            ),
        ],
    )

    print(f"IndoDesk branding applied: {b['app_name']} ({b['bundle_id']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
