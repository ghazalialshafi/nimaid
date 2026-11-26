/* Self-contained test of the C API (no arguments). Run from any directory. */
#include "nimaid.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static const char *FLOW = "flowchart LR\n  A[Hello] --> B{Ok?}\n  B -->|yes| C[World]\n  B -->|no| A\n";

int main(void) {
  CHECK(nimaid_abi_version() == NIMAID_ABI_VERSION);
  CHECK(strcmp(nimaid_version(), NIMAID_VERSION_STRING) == 0);
  CHECK(strcmp(nimaid_detect_type("sequenceDiagram\nA->>B: hi"), "sequence") == 0);
  CHECK(strcmp(nimaid_detect_type(NULL), "unknown") == 0);
  CHECK(nimaid_theme_count() == 5 && strcmp(nimaid_theme_name(1), "dark") == 0 && nimaid_theme_name(9) == NULL);

  nimaid_context *ctx = nimaid_context_new();
  CHECK(ctx != NULL);
  uint8_t *buf = NULL; size_t n = 0;

  /* PNG with all defaults (NULL options) */
  CHECK(nimaid_render_png(ctx, FLOW, NULL, &buf, &n) == NIMAID_OK);
  CHECK(n > 8 && memcmp(buf, "\x89PNG\r\n\x1a\n", 8) == 0);
  size_t full = n; nimaid_free(buf);

  /* palette PNG is smaller; scale option honoured */
  nimaid_options o; nimaid_options_init(&o); o.colors = 16;
  CHECK(nimaid_render_png(ctx, FLOW, &o, &buf, &n) == NIMAID_OK && n < full); nimaid_free(buf);
  nimaid_image a, b; nimaid_options_init(&o);
  o.scale = 1.0; CHECK(nimaid_render_rgba(ctx, FLOW, &o, &a) == NIMAID_OK);
  o.scale = 2.0; CHECK(nimaid_render_rgba(ctx, FLOW, &o, &b) == NIMAID_OK);
  CHECK(a.width > 0 && abs(b.width - 2 * a.width) <= 1 && abs(b.height - 2 * a.height) <= 1);

  /* encode caller pixels */
  CHECK(nimaid_encode_png(a.pixels, a.width, a.height, 0, &buf, &n) == NIMAID_OK && n > 8); nimaid_free(buf);
  CHECK(nimaid_encode_gif(a.pixels, a.width, a.height, 0, &buf, &n) == NIMAID_OK && memcmp(buf, "GIF89a", 6) == 0); nimaid_free(buf);
  nimaid_free(a.pixels); nimaid_free(b.pixels);

  /* GIF, SVG (paths and live text), themes */
  CHECK(nimaid_render_gif(ctx, FLOW, NULL, &buf, &n) == NIMAID_OK && memcmp(buf, "GIF8", 4) == 0); nimaid_free(buf);
  char *svg = NULL; size_t sl = 0;
  CHECK(nimaid_render_svg(ctx, FLOW, NULL, &svg, &sl) == NIMAID_OK && strncmp(svg, "<svg", 4) == 0 && strlen(svg) == sl);
  CHECK(strstr(svg, "<text") == NULL); nimaid_free(svg);
  o.svg_text = 1; o.theme = "dark";
  CHECK(nimaid_render_svg(ctx, FLOW, &o, &svg, NULL) == NIMAID_OK && strstr(svg, "<text") != NULL); nimaid_free(svg);

  /* errors: message + status, outputs reset */
  buf = (uint8_t *)1; n = 5;
  CHECK(nimaid_render_png(ctx, "flowchart LR\n A --> ", NULL, &buf, &n) != NIMAID_OK && buf == NULL && n == 0);
  CHECK(nimaid_render_png(ctx, "banana", NULL, &buf, &n) == NIMAID_ERR_UNSUPPORTED);
  CHECK(strlen(nimaid_context_error(ctx)) > 0);
  CHECK(nimaid_render_png(ctx, FLOW, NULL, &buf, &n) == NIMAID_OK && nimaid_context_error(ctx)[0] == 0); nimaid_free(buf);
  CHECK(nimaid_render_png(ctx, NULL, NULL, &buf, &n) == NIMAID_ERR_INVALID_ARGUMENT);
  o.scale = -1; CHECK(nimaid_render_png(ctx, FLOW, &o, &buf, &n) == NIMAID_ERR_INVALID_ARGUMENT);
  nimaid_options_init(&o); o.colors = 1; CHECK(nimaid_render_png(ctx, FLOW, &o, &buf, &n) == NIMAID_ERR_INVALID_ARGUMENT);
  CHECK(nimaid_render_png(ctx, FLOW, NULL, NULL, NULL) == NIMAID_ERR_INVALID_ARGUMENT);
  CHECK(nimaid_context_set_font_file(ctx, "/nonexistent.ttf") == NIMAID_ERR_FONT);
  CHECK(nimaid_context_set_font_data(ctx, "not a font", 10) == NIMAID_OK);   /* validated on first use */
  CHECK(nimaid_render_png(ctx, FLOW, NULL, &buf, &n) == NIMAID_ERR_FONT);
  CHECK(nimaid_context_set_font_data(ctx, NULL, 0) == NIMAID_OK && nimaid_render_png(ctx, FLOW, NULL, &buf, &n) == NIMAID_OK);
  nimaid_free(buf);
  CHECK(nimaid_render_file(ctx, FLOW, "/nonexistent_dir/x.png", NULL) == NIMAID_ERR_IO);

  /* file output + two contexts with different settings interleaved */
  CHECK(nimaid_render_file(ctx, FLOW, "capi_test_out.svg", NULL) == NIMAID_OK);
  nimaid_context *c2 = nimaid_context_new();
  const char *types[] = {"sequenceDiagram\n A->>B: hi\n B-->>A: yo", "stateDiagram-v2\n [*] --> S1\n S1 --> [*]",
    "erDiagram\n CUSTOMER ||--o{ ORDER : places", "classDiagram\n class A\n A <|-- B", "gantt\n title T\n dateFormat YYYY-MM-DD\n section S\n Task :a1, 2024-01-01, 3d",
    "gitGraph\n commit\n branch dev\n commit\n checkout main\n merge dev", "mindmap\n root((Root))\n  A\n  B",
    "pie showData\n \"A\" : 3\n \"B\" : 5",
    "xychart-beta\n x-axis [a, b, c]\n bar [1, 2, 3]\n line [2, 1, 3]",
    "timeline\n 2020 : Start\n 2021 : Grow",
    "quadrantChart\n x-axis Low --> High\n y-axis Low --> High\n P: [0.3, 0.6]",
    "journey\n title T\n section S\n Task: 5: Me",
    "packet\n 0-15: \"Source\"\n 16-31: \"Dest\"",
    "kanban\n Todo\n  t1[Task one]",
    "radar-beta\n axis a, b, c\n curve x{1, 2, 3}",
    "treemap-beta\n \"Root\"\n  \"A\": 10\n  \"B\": 20",
    "sankey-beta\n\nA,B,10\nB,C,5"};
  for (size_t i = 0; i < sizeof types / sizeof *types; i++) {
    nimaid_context *c = (i & 1) ? c2 : ctx;
    CHECK(nimaid_render_png(c, types[i], NULL, &buf, &n) == NIMAID_OK && n > 100); nimaid_free(buf);
  }
  nimaid_context_free(c2);

  /* every chart type is detected and renders to SVG as well */
  const char *charts[][2] = {{"pie", "pie\n \"A\" : 1"}, {"xychart", "xychart-beta\n bar [1, 2]"}, {"timeline", "timeline\n 2020 : x"},
    {"quadrant", "quadrantChart\n P: [0.3, 0.6]"}, {"journey", "journey\n section S\n T: 3: Me"}, {"packet", "packet\n 0-7: \"a\""},
    {"kanban", "kanban\n Todo\n  t[Task]"}, {"radar", "radar-beta\n axis a, b, c\n curve x{1, 2, 3}"},
    {"treemap", "treemap-beta\n \"R\"\n  \"A\": 1"}, {"sankey", "sankey-beta\n\nA,B,1"}};
  for (size_t i = 0; i < sizeof charts / sizeof *charts; i++) {
    CHECK(strcmp(nimaid_detect_type(charts[i][1]), charts[i][0]) == 0);
    char *svg = NULL;
    CHECK(nimaid_render_svg(ctx, charts[i][1], NULL, &svg, &n) == NIMAID_OK && n > 100 && strstr(svg, "<svg")); nimaid_free(svg);
  }

  nimaid_context_free(ctx);
  nimaid_context_free(NULL);
  printf(failures ? "%d FAILURE(S)\n" : "all C API tests passed\n", failures);
  return failures != 0;
}
