## The smallest possible program: Mermaid text in, PNG out.
import nimaid

renderMermaidToFile(
  "flowchart LR\n  A[Hello] --> B[World]",
  "hello.png",
  "fonts/DejaVuSans.ttf",
  emojiFontPath = "fonts/NotoColorEmoji-Regular.ttf")
echo "wrote hello.png"
