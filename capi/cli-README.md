# nimaid CLI

Mermaid diagrams to PNG / GIF / SVG. One static executable, no dependencies, no browser, no font files (DejaVu Sans is built in).

```sh
./nimaid examples/01-first.mmd first.png
./nimaid --theme=dark --scale=3 examples/07-sequence.mmd seq@3x.png
./nimaid examples/09-er.mmd er.svg
./nimaid --help
```

Options: `--theme=default|dark|forest|neutral|base`, `--scale=N` (PNG/GIF, default 2), `--colors=N` (2..256 palette), `--svg-text=paths|text`,
`--font=FILE.ttf` (TrueType), `--emoji=FILE.ttf` (Noto Color Emoji, OpenType-SVG; get it from the `nimaid-fonts-<version>` release asset), `--dagre=legacy|modern`.

Put the executable on your `PATH` (Linux/macOS: `sudo install -m755 nimaid /usr/local/bin/`; Windows: any folder on `PATH`).
On macOS, binaries downloaded with a browser may be quarantined: `xattr -d com.apple.quarantine nimaid`.

Docs and tutorials: <https://github.com/ghazalialshafi/nimaid> (the same commands work with this binary). Also available as a C library, a Python package (`pip install nimaid`) and WebAssembly (`npm install nimaid`).
MIT licensed; DejaVu Sans is embedded (see THIRD_PARTY.md).
