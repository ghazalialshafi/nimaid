# nimaid website

* `index.html` — the home page (pitch, gallery, install snippets).
* `playground/index.html` — live editor + preview (26 examples, SVG/PNG export, shareable links, lazy-loaded colour emoji).
  Deep links: `playground/#ex=sankey`.
* `gen_gallery.mjs` — renders the home-page gallery with nimaid itself.

The `pages` workflow adds `nimaid.mjs`, `nimaid.wasm`, `gallery/` and `fonts/` at deploy time (they are git-ignored).

Run it locally:

```sh
python3 capi/build.py -t wasm32-wasi            # or download nimaid-wasm-X.Y.Z.tar.gz from a release
tar xzf capi/dist/nimaid-wasm-*.tar.gz -C /tmp
cp /tmp/nimaid-wasm-*/nimaid.{mjs,wasm} site/
mkdir -p site/fonts && cp fonts/NotoColorEmoji-Regular.ttf site/fonts/
(cd site && node gen_gallery.mjs ../examples gallery)
python3 -m http.server -d site 8000             # open http://localhost:8000
```
