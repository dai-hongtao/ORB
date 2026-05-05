# Locales

These JSON files are the source of truth for translatable user-facing text.

- Keys are stable identifiers used by clients.
- Values are translated strings.
- Every locale file should contain the same key set.

Run this from the repository root to refresh macOS resources:

```sh
python3 tools/localization/export_macos_strings.py
```
