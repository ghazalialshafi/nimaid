"""Run:  python -m unittest discover -s tests -v     (against the installed wheel)"""
import os
import subprocess
import sys
import tempfile
import threading
import unittest

import nimaid

FLOW = "flowchart LR\n  A[Hello] --> B{Ok?}\n  B -->|yes| C[World]\n  B -->|no| A\n"


class Basics(unittest.TestCase):
    def test_info(self):
        self.assertEqual(nimaid.native_version(), nimaid.__version__)
        self.assertEqual(nimaid.themes(), ["default", "dark", "forest", "neutral", "base"])
        self.assertEqual(nimaid.detect_type("sequenceDiagram\nA->>B: x"), "sequence")
        self.assertEqual(nimaid.detect_type("???"), "unknown")

    def test_formats(self):
        self.assertTrue(nimaid.png(FLOW).startswith(b"\x89PNG\r\n\x1a\n"))
        self.assertTrue(nimaid.gif(FLOW).startswith(b"GIF8"))
        s = nimaid.svg(FLOW)
        self.assertTrue(s.startswith("<svg")) and self.assertNotIn("<text", s)
        self.assertIn("<text", nimaid.svg(FLOW, live_text=True, theme="dark"))
        self.assertLess(len(nimaid.png(FLOW, colors=16)), len(nimaid.png(FLOW)))

    def test_rgba_and_encoders(self):
        a, b = nimaid.rgba(FLOW, scale=1), nimaid.rgba(FLOW, scale=2)
        self.assertEqual(len(a.data), a.width * a.height * 4)
        self.assertLessEqual(abs(b.width - 2 * a.width), 1)
        self.assertTrue(nimaid.encode_png(a.data, a.width, a.height).startswith(b"\x89PNG"))
        self.assertTrue(nimaid.encode_gif(a.data, a.width, a.height, 32).startswith(b"GIF"))
        with self.assertRaises(nimaid.InvalidArgumentError):
            nimaid.encode_png(b"123", 10, 10)

    def test_errors(self):
        with self.assertRaises(nimaid.UnsupportedDiagramError):
            nimaid.png("banana")
        with self.assertRaises(nimaid.ParseError) as cm:
            nimaid.png("flowchart LR\n A --> ")
        self.assertIsInstance(cm.exception, ValueError)
        self.assertEqual(cm.exception.status, 3)
        with self.assertRaises(nimaid.InvalidArgumentError):
            nimaid.png(FLOW, scale=-1)
        with self.assertRaises(nimaid.InvalidArgumentError):
            nimaid.png(FLOW, colors=1)
        with self.assertRaises(nimaid.InvalidArgumentError):
            nimaid.png("a\0b")
        with self.assertRaises(nimaid.RenderIOError):
            nimaid.render_file(FLOW, os.path.join(tempfile.gettempdir(), "no_such_dir_xyz", "a.png"))
        with self.assertRaises(TypeError):
            nimaid.png(b"bytes")

    def test_unicode_text(self):
        self.assertTrue(nimaid.png("flowchart LR\n  A[Grüße — 日本] --> B").startswith(b"\x89PNG"))


class Contexts(unittest.TestCase):
    def test_context_manager_and_close(self):
        with nimaid.Context() as c:
            self.assertTrue(c.png(FLOW))
        with self.assertRaises(ValueError):
            c.png(FLOW)

    def test_fonts(self):
        with nimaid.Context() as c:
            with self.assertRaises(nimaid.FontError):
                c.set_font("/no/such/font.ttf")
            c.set_font(b"definitely not a font")
            with self.assertRaises(nimaid.FontError):
                c.png(FLOW)
            c.set_font(None)           # back to the embedded font
            self.assertTrue(c.png(FLOW))
        font = os.environ.get("NIMAID_TEST_FONT")
        if font and os.path.exists(font):
            with open(font, "rb") as fh:
                font_bytes = fh.read()
            with nimaid.Context(font=font) as c1, nimaid.Context(font=font_bytes) as c2:
                self.assertEqual(c1.png(FLOW), c2.png(FLOW))
                self.assertEqual(c1.png(FLOW), nimaid.png(FLOW))      # DejaVu == embedded DejaVu

    def test_emoji(self):
        try:
            import nimaid_emoji
        except ImportError:
            self.skipTest("nimaid-noto-emoji not installed")
        text = "flowchart LR\n  A[😀 Happy] --> B[🚀]"
        plain = nimaid.Context(emoji=None).png(text)
        with nimaid.Context() as c:    # emoji="auto" picks up nimaid_emoji
            self.assertNotEqual(c.png(text), plain)
        self.assertTrue(os.path.getsize(nimaid_emoji.font_path()) > 1_000_000)

    def test_chart_types(self):
        charts = {"pie": 'pie\n "A" : 1\n "B" : 2', "xychart": "xychart-beta\n bar [1, 2]",
                  "timeline": "timeline\n 2020 : x", "quadrant": "quadrantChart\n P: [0.3, 0.6]",
                  "journey": "journey\n section S\n T: 3: Me", "packet": 'packet\n 0-7: "a"',
                  "kanban": "kanban\n Todo\n  t[Task]", "radar": "radar-beta\n axis a, b, c\n curve x{1, 2, 3}",
                  "treemap": 'treemap-beta\n "R"\n  "A": 1', "sankey": "sankey-beta\n\nA,B,1"}
        with nimaid.Context(emoji=None) as c:
            for kind, text in charts.items():
                self.assertEqual(nimaid.detect_type(text), kind)
                self.assertTrue(c.png(text).startswith(b"\x89PNG"), kind)
                self.assertIn("<svg", c.svg(text), kind)

    def test_two_contexts_interleaved(self):
        a, b = nimaid.Context(), nimaid.Context()
        for t in ("flowchart LR\n A-->B", "stateDiagram-v2\n [*] --> S\n S --> [*]", "mindmap\n root((R))\n  A"):
            self.assertTrue(a.png(t)); self.assertTrue(b.svg(t))

    def test_threads(self):
        errors = []

        def work():
            try:
                for _ in range(5):
                    assert nimaid.png(FLOW).startswith(b"\x89PNG")
            except Exception as e:  # noqa
                errors.append(e)
        ts = [threading.Thread(target=work) for _ in range(6)]
        [t.start() for t in ts]; [t.join() for t in ts]
        self.assertEqual(errors, [])

    def test_deterministic(self):
        self.assertEqual(nimaid.png(FLOW), nimaid.png(FLOW))
        self.assertEqual(nimaid.svg(FLOW), nimaid.svg(FLOW))


class Extras(unittest.TestCase):
    def test_diagram(self):
        d = nimaid.Diagram(FLOW, theme="forest")
        self.assertTrue(d._repr_svg_().startswith("<svg"))
        self.assertTrue(d._repr_png_().startswith(b"\x89PNG"))
        self.assertIn("flowchart", repr(d))
        with tempfile.TemporaryDirectory() as t:
            for ext in ("png", "gif", "svg"):
                p = os.path.join(t, "o." + ext); d.save(p); self.assertGreater(os.path.getsize(p), 100)

    def test_cli(self):
        with tempfile.TemporaryDirectory() as t:
            src, out = os.path.join(t, "a.mmd"), os.path.join(t, "a.svg")
            with open(src, "w") as f: f.write(FLOW)
            r = subprocess.run([sys.executable, "-m", "nimaid", "--theme=dark", src, out], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            with open(out) as f: self.assertTrue(f.read().startswith("<svg"))
            r = subprocess.run([sys.executable, "-m", "nimaid", src, os.path.join(t, "x.txt")], capture_output=True, text=True)
            self.assertNotEqual(r.returncode, 0)
            with open(src, "w") as f: f.write("banana")
            r = subprocess.run([sys.executable, "-m", "nimaid", src, out], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1); self.assertIn("unsupported", r.stderr)


if __name__ == "__main__":
    unittest.main()
