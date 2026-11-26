/* Render to memory: RGBA pixels, PNG bytes, palette PNG, GIF, SVG string. No files involved. */
#include "nimaid.h"
#include <stdio.h>
#include <string.h>

#define CHECK(call) do { nimaid_status s_ = (call); if (s_ != NIMAID_OK) { \
  fprintf(stderr, "%s failed: %s\n", #call, nimaid_context_error(ctx)); return 1; } } while (0)

int main(void) {
  const char *chart = "flowchart TD\n A[Request] --> B{Cached?}\n B -->|yes| C[Serve]\n B -->|no| D[Compute] --> C";
  nimaid_context *ctx = nimaid_context_new();
  nimaid_options opt; nimaid_options_init(&opt);       /* scale 2.0, truecolour */

  nimaid_image img;
  CHECK(nimaid_render_rgba(ctx, chart, &opt, &img));   /* straight-alpha RGBA8, row-major */
  printf("pixels: %dx%d (%d bytes)\n", img.width, img.height, img.width * img.height * 4);

  uint8_t *png; size_t png_len;                         /* encode the pixels you already have ... */
  CHECK(nimaid_encode_png(img.pixels, img.width, img.height, 0, &png, &png_len));
  printf("png: %zu bytes\n", png_len);
  nimaid_free(png);
  nimaid_free(img.pixels);

  opt.colors = 64;                                      /* ... or render straight to bytes */
  CHECK(nimaid_render_png(ctx, chart, &opt, &png, &png_len));
  printf("palette png: %zu bytes\n", png_len);
  nimaid_free(png);

  opt.colors = 0; opt.theme = "forest";
  char *svg; size_t svg_len;
  CHECK(nimaid_render_svg(ctx, chart, &opt, &svg, &svg_len));
  printf("svg: %zu chars, starts with: %.40s\n", svg_len, svg);
  nimaid_free(svg);

  nimaid_context_free(ctx);
  return 0;
}
