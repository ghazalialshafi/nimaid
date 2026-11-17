version     = "0.2.0"
author      = "Ghazali"
description = "nimaid: Mermaid diagrams (flowchart, sequence, ...) to PNG / GIF / SVG in pure Nim"
license     = "MIT"
srcDir      = "src"
bin         = @["nimaid_cli"]
namedBin["nimaid_cli"] = "nimaid"
requires "nim >= 2.0.0"
