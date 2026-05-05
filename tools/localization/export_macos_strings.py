#!/usr/bin/env python3
"""Export ORB locale JSON files to macOS Localizable.strings resources."""

from __future__ import annotations

import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
LOCALES_DIR = REPO_ROOT / "locales"
MACOS_RESOURCES_DIR = REPO_ROOT / "client" / "macos" / "ORB" / "ORB"


def escape_strings_value(value: str) -> str:
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


def main() -> None:
    for locale_path in sorted(LOCALES_DIR.glob("*.json")):
        locale = locale_path.stem
        data = json.loads(locale_path.read_text(encoding="utf-8"))
        output_dir = MACOS_RESOURCES_DIR / f"{locale}.lproj"
        output_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / "Localizable.strings"

        lines = [
            "/* Generated from locales/*.json. Do not edit directly. */",
            "",
        ]
        for key in sorted(data):
            value = escape_strings_value(str(data[key]))
            lines.append(f'"{key}" = "{value}";')

        output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
