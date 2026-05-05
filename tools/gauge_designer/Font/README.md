# Custom Fonts

This folder is reserved for optional custom runtime fonts (`.ttf`, `.otf`, `.woff`, or `.woff2`).

The open-source package does not need any files here by default. The gauge designer already embeds `Source Han Sans CN Medium` in `../font-data.js`, and the built-in font dropdown only exposes that font.

If you add custom fonts later, serve the `tools/gauge_designer` folder with a local HTTP server so the browser can read this directory listing. The editor will discover font files and add them to the font dropdown at runtime.
