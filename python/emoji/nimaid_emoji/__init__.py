"""Noto Color Emoji (OpenType-SVG) for nimaid. SIL Open Font License 1.1 - see the license file in this package."""
import os

__version__ = "0.6.1"


def font_path() -> str:
    """Absolute path of NotoColorEmoji-Regular.ttf."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "NotoColorEmoji-Regular.ttf")
