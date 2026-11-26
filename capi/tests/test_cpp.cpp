#include "nimaid.hpp"
#include <cassert>
#include <cstdio>
int main() {
  nimaid::Context ctx;
  nimaid::Options o; o.theme = "dark";
  auto png = ctx.png("flowchart LR\n A[C++] --> B[nimaid]", o);
  assert(png.size() > 8 && png[1] == 'P' && png[2] == 'N' && png[3] == 'G');
  assert(ctx.svg("flowchart LR\n A --> B").compare(0, 4, "<svg") == 0);
  auto im = ctx.rgba("flowchart LR\n A --> B"); assert(im.width > 0 && im.pixels.size() == (size_t)im.width * im.height * 4);
  nimaid::Context moved(std::move(ctx));
  try { moved.png("flowchart LR\n A --> "); assert(false); } catch (const nimaid::Error &e) { assert(e.status == NIMAID_ERR_PARSE); }
  std::puts("C++ wrapper ok");
}
