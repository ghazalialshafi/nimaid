// nimaid.hpp - header-only C++11 RAII wrapper over nimaid.h. Errors are exceptions; buffers are std::vector/std::string.
#ifndef NIMAID_HPP
#define NIMAID_HPP
#include "nimaid.h"
#include <cstdint>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace nimaid {

struct Error : std::runtime_error {
  nimaid_status status;
  Error(nimaid_status s, const std::string &msg) : std::runtime_error(msg), status(s) {}
};

struct Options {
  double scale = 2.0;        // PNG/GIF pixel scale
  std::string theme;         // "" = from the diagram
  int colors = 0;            // 0 = truecolour, 2..256 = palette
  bool svg_text = false;     // SVG: live <text> instead of outlined glyphs
  bool legacy_dagre = true;
};

struct Image { int width = 0, height = 0; std::vector<uint8_t> pixels; };   // RGBA8

class Context {
 public:
  Context() : c_(nimaid_context_new()) { if (!c_) throw Error(NIMAID_ERR_OOM, "out of memory"); }
  ~Context() { nimaid_context_free(c_); }
  Context(const Context &) = delete;
  Context &operator=(const Context &) = delete;
  Context(Context &&o) noexcept : c_(o.c_) { o.c_ = nullptr; }
  Context &operator=(Context &&o) noexcept { std::swap(c_, o.c_); return *this; }

  void set_font_file(const std::string &p) { check(nimaid_context_set_font_file(c_, p.c_str())); }
  void set_font_data(const std::vector<uint8_t> &d) { check(nimaid_context_set_font_data(c_, d.data(), d.size())); }
  void set_emoji_font_file(const std::string &p) { check(nimaid_context_set_emoji_font_file(c_, p.c_str())); }
  void set_emoji_font_data(const std::vector<uint8_t> &d) { check(nimaid_context_set_emoji_font_data(c_, d.data(), d.size())); }

  std::vector<uint8_t> png(const std::string &m, const Options &o = Options()) { return bytes(nimaid_render_png, m, o); }
  std::vector<uint8_t> gif(const std::string &m, const Options &o = Options()) { return bytes(nimaid_render_gif, m, o); }

  std::string svg(const std::string &m, const Options &o = Options()) {
    nimaid_options c = native(o); char *s = nullptr; size_t n = 0;
    check(nimaid_render_svg(c_, m.c_str(), &c, &s, &n));
    std::string r(s, n); nimaid_free(s); return r;
  }
  Image rgba(const std::string &m, const Options &o = Options()) {
    nimaid_options c = native(o); nimaid_image im;
    check(nimaid_render_rgba(c_, m.c_str(), &c, &im));
    Image r; r.width = im.width; r.height = im.height;
    r.pixels.assign(im.pixels, im.pixels + (size_t)im.width * im.height * 4); nimaid_free(im.pixels); return r;
  }
  void render_file(const std::string &m, const std::string &path, const Options &o = Options()) {
    nimaid_options c = native(o); check(nimaid_render_file(c_, m.c_str(), path.c_str(), &c));
  }
  nimaid_context *handle() { return c_; }

 private:
  typedef nimaid_status (*Fn)(nimaid_context *, const char *, const nimaid_options *, uint8_t **, size_t *);
  static nimaid_options native(const Options &o) {   // o.theme must outlive the call: it does (caller's reference)
    nimaid_options c; nimaid_options_init(&c);
    c.scale = o.scale; c.theme = o.theme.empty() ? nullptr : o.theme.c_str();
    c.colors = o.colors; c.svg_text = o.svg_text; c.legacy_dagre = o.legacy_dagre; return c;
  }
  std::vector<uint8_t> bytes(Fn f, const std::string &m, const Options &o) {
    nimaid_options c = native(o); uint8_t *b = nullptr; size_t n = 0;
    check(f(c_, m.c_str(), &c, &b, &n));
    std::vector<uint8_t> r(b, b + n); nimaid_free(b); return r;
  }
  void check(nimaid_status s) { if (s != NIMAID_OK) throw Error(s, nimaid_context_error(c_)); }
  nimaid_context *c_;
};

}  // namespace nimaid
#endif
