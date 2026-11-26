"""Command line: ``nimaid input.mmd output.(png|gif|svg)``  (same options as the native nimaid tool)."""
import argparse
import sys

from . import Context, NimaidError, __version__, native_version


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="nimaid", description="Mermaid diagrams to PNG / GIF / SVG (Python build)")
    p.add_argument("input", help="Mermaid file, or - for stdin")
    p.add_argument("output", help="output file; the extension (.png .gif .svg) selects the format")
    p.add_argument("--theme", help="default | dark | forest | neutral | base (default: from the diagram)")
    p.add_argument("--scale", type=float, default=2.0, help="pixel scale for PNG/GIF, 2 = retina (default 2)")
    p.add_argument("--colors", type=int, default=0, help="2..256: palette PNG / smaller GIF")
    p.add_argument("--svg-text", choices=["paths", "text"], default="paths", help="SVG: outlined glyphs or live <text>")
    p.add_argument("--font", help="TrueType text font (default: embedded DejaVu Sans)")
    p.add_argument("--emoji", help="Noto Color Emoji font file (default: nimaid-noto-emoji package if installed)")
    p.add_argument("--dagre", choices=["legacy", "modern"], default="legacy", help="layout tie-breaking")
    p.add_argument("-v", "--version", action="version", version=f"nimaid {__version__} (native {native_version()})")
    a = p.parse_args(argv)
    if not a.output.lower().endswith((".png", ".gif", ".svg")):
        p.error(f"output file must end in .png, .gif or .svg (got {a.output!r})")
    try:
        text = sys.stdin.read() if a.input == "-" else open(a.input, encoding="utf-8").read()
        with Context(font=a.font, emoji=a.emoji if a.emoji else "auto") as ctx:
            ctx.render_file(text, a.output, scale=a.scale, theme=a.theme, colors=a.colors,
                            live_text=a.svg_text == "text", legacy_dagre=a.dagre == "legacy")
    except (NimaidError, OSError) as e:
        print(f"nimaid: {a.input}: {e}", file=sys.stderr)
        return 1
    print(f"wrote {a.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
