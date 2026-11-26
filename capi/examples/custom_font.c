/* Fonts from memory (e.g. loaded from a resource, a database or an archive):
 *   custom_font [text-font.ttf] [NotoColorEmoji-Regular.ttf]
 * The library copies the bytes, so you may free your buffer right after the call. */
#include "nimaid.h"
#include <stdio.h>
#include <stdlib.h>

static void *slurp(const char *path, size_t *n) {
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  fseek(f, 0, SEEK_END); *n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
  void *b = malloc(*n); if (b && fread(b, 1, *n, f) != *n) { free(b); b = NULL; }
  fclose(f); return b;
}

int main(int argc, char **argv) {
  nimaid_context *ctx = nimaid_context_new();
  size_t n; void *buf;
  if (argc > 1 && (buf = slurp(argv[1], &n))) {
    nimaid_status st = nimaid_context_set_font_data(ctx, buf, n);   /* TrueType (glyf) */
    free(buf); if (st) { fprintf(stderr, "%s\n", nimaid_context_error(ctx)); return 1; }
  }
  if (argc > 2 && (buf = slurp(argv[2], &n))) {
    nimaid_status st = nimaid_context_set_emoji_font_data(ctx, buf, n);
    free(buf); if (st) { fprintf(stderr, "%s\n", nimaid_context_error(ctx)); return 1; }
  }
  nimaid_status st = nimaid_render_file(ctx, "flowchart LR\n  A[😀 Happy] --> B{Ship it? 🚀}", "custom_font.png", NULL);
  if (st) fprintf(stderr, "%s\n", nimaid_context_error(ctx)); else puts("wrote custom_font.png");
  nimaid_context_free(ctx);
  return st != NIMAID_OK;
}
