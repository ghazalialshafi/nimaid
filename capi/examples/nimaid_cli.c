/* nimaid CLI, written against the C API. Same options as the Nim CLI (docs/cli.md), so every
 * command in the tutorials works with this binary:  nimaid [options] input.mmd output.(png|gif|svg) */
#include "nimaid.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *HELP =
  "nimaid - Mermaid diagrams to PNG / GIF / SVG (C API build)\n\n"
  "usage: nimaid [options] input.mmd output.(png|gif|svg)\n\n"
  "options:\n"
  "  --theme=NAME      default | dark | forest | neutral | base   (default: from diagram)\n"
  "  --scale=N         pixel scale for PNG/GIF, 2 = retina         (default: 2)\n"
  "  --colors=N        2..256: palette PNG / smaller GIF           (default: truecolour)\n"
  "  --svg-text=MODE   paths | text                               (default: paths)\n"
  "  --font=FILE.ttf   text font (default: embedded DejaVu Sans)\n"
  "  --emoji=FILE.ttf  colour emoji font (Noto Color Emoji)       (default: none)\n"
  "  --dagre=MODE      legacy | modern                            (default: legacy)\n"
  "  -h, --help  -v, --version\n";

static char *read_all(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *s = malloc((size_t)n + 1);
  if (!s) { fclose(f); return NULL; }
  size_t r = fread(s, 1, (size_t)n, f); s[r] = 0; fclose(f);
  return s;
}

static int ends_with_ci(const char *s, const char *suf) {
  size_t a = strlen(s), b = strlen(suf);
  if (a < b) return 0;
  for (size_t i = 0; i < b; i++) {
    char c = s[a - b + i]; if (c >= 'A' && c <= 'Z') c += 32;
    if (c != suf[i]) return 0;
  }
  return 1;
}

int main(int argc, char **argv) {
  nimaid_options opt; nimaid_options_init(&opt);
  const char *font = NULL, *emoji = NULL, *pos[2]; int np = 0;
  for (int i = 1; i < argc; i++) {
    const char *a = argv[i];
    if (!strcmp(a, "-h") || !strcmp(a, "--help")) { fputs(HELP, stdout); return 0; }
    if (!strcmp(a, "-v") || !strcmp(a, "--version")) { printf("nimaid %s\n", nimaid_version()); return 0; }
    if (!strncmp(a, "--theme=", 8)) opt.theme = a + 8;
    else if (!strncmp(a, "--scale=", 8)) opt.scale = atof(a + 8);
    else if (!strncmp(a, "--colors=", 9)) opt.colors = atoi(a + 9);
    else if (!strncmp(a, "--svg-text=", 11)) opt.svg_text = !strcmp(a + 11, "text") || !strcmp(a + 11, "live");
    else if (!strncmp(a, "--font=", 7)) font = a + 7;
    else if (!strncmp(a, "--emoji=", 8)) emoji = a + 8;
    else if (!strncmp(a, "--dagre=", 8)) opt.legacy_dagre = strcmp(a + 8, "modern") != 0;
    else if (a[0] == '-' && a[1]) { fputs(HELP, stderr); return 1; }
    else if (np < 2) pos[np++] = a;
    else { fputs(HELP, stderr); return 1; }
  }
  if (np != 2) { fputs("usage: nimaid [options] input.mmd output.(png|gif|svg)\n", stderr); return 1; }
  if (!ends_with_ci(pos[1], ".png") && !ends_with_ci(pos[1], ".gif") && !ends_with_ci(pos[1], ".svg")) {
    fprintf(stderr, "nimaid: output file must end in .png, .gif or .svg (got '%s')\n", pos[1]); return 1;
  }
  char *text = read_all(pos[0]);
  if (!text) { fprintf(stderr, "nimaid: cannot read '%s'\n", pos[0]); return 1; }

  nimaid_context *ctx = nimaid_context_new();
  nimaid_status st = NIMAID_OK;
  if (font) st = nimaid_context_set_font_file(ctx, font);
  if (st == NIMAID_OK && emoji) st = nimaid_context_set_emoji_font_file(ctx, emoji);
  if (st == NIMAID_OK) st = nimaid_render_file(ctx, text, pos[1], &opt);
  if (st != NIMAID_OK) fprintf(stderr, "nimaid: %s: %s (%s)\n", pos[0], nimaid_context_error(ctx), nimaid_status_string(st));
  else printf("wrote %s\n", pos[1]);
  nimaid_context_free(ctx); free(text);
  return st != NIMAID_OK;
}
