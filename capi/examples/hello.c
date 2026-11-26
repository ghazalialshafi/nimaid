/* Smallest possible program: Mermaid text in, PNG file out. */
#include "nimaid.h"
#include <stdio.h>

int main(void) {
  nimaid_context *ctx = nimaid_context_new();      /* embedded font, no emoji */
  nimaid_status st = nimaid_render_file(ctx, "flowchart LR\n  A[Hello] --> B[World]", "hello.png", NULL);
  if (st != NIMAID_OK) fprintf(stderr, "nimaid: %s (%s)\n", nimaid_context_error(ctx), nimaid_status_string(st));
  else puts("wrote hello.png");
  nimaid_context_free(ctx);
  return st != NIMAID_OK;
}
