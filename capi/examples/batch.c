/* Convert many .mmd files, reporting errors per file:   batch OUTDIR a.mmd b.mmd ...
 * (your shell can expand a glob such as  *.mmd ). Portable: no dirent. */
#include "nimaid.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *read_all(const char *path) {
  FILE *f = fopen(path, "rb"); if (!f) return NULL;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  char *s = malloc((size_t)n + 1); size_t r = s ? fread(s, 1, (size_t)n, f) : 0;
  if (s) s[r] = 0; fclose(f); return s;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: batch OUTDIR file.mmd...\n"); return 2; }
  nimaid_context *ctx = nimaid_context_new();          /* one context for the whole batch */
  nimaid_options opt; nimaid_options_init(&opt); opt.theme = "neutral";
  int failed = 0;
  for (int i = 2; i < argc; i++) {
    const char *base = argv[i], *p;
    for (p = argv[i]; *p; p++) if (*p == '/' || *p == '\\') base = p + 1;
    char name[256]; snprintf(name, sizeof name, "%s", base);
    char *dot = strrchr(name, '.'); if (dot) *dot = 0;
    char out[1024]; snprintf(out, sizeof out, "%s/%s.svg", argv[1], name);

    char *text = read_all(argv[i]);
    nimaid_status st = text ? nimaid_render_file(ctx, text, out, &opt) : NIMAID_ERR_IO;
    if (st == NIMAID_OK) printf("ok    %s\n", name);
    else { printf("FAIL  %s: %s\n", name, text ? nimaid_context_error(ctx) : "cannot read file"); failed++; }
    free(text);
  }
  nimaid_context_free(ctx);
  return failed != 0;
}
