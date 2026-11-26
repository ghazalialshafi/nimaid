/*
 * nimaid.h - C API for nimaid: Mermaid diagrams -> PNG / GIF / SVG / RGBA pixels.
 *
 * Pure Nim core, no runtime dependencies. Link against libnimaid (static or shared).
 * Full documentation: docs/reference/c-api.md and docs/tutorials/07-c-library.md
 *
 * Conventions
 *   - Every function that can fail returns a nimaid_status (NIMAID_OK == 0).
 *     The message of the last failure on a context: nimaid_context_error(ctx).
 *   - Memory returned through out-parameters is allocated by the library; release it with
 *     nimaid_free() (never with free() directly: the library and your program may use different C runtimes).
 *   - Input strings are NUL-terminated UTF-8. Font/pixel buffers passed in are copied.
 *   - Calls are serialised by an internal lock, so they are safe from several threads, but they do not
 *     run in parallel. For parallel throughput use one process per worker.
 *   - A nimaid_context must not be freed while another thread is using it.
 */
#ifndef NIMAID_H
#define NIMAID_H

#include <stddef.h>
#include <stdint.h>

#define NIMAID_VERSION_MAJOR 0
#define NIMAID_VERSION_MINOR 6
#define NIMAID_VERSION_PATCH 1
#define NIMAID_VERSION_STRING "0.6.1"
/* Bumped only when the binary interface changes incompatibly. Compare with nimaid_abi_version(). */
#define NIMAID_ABI_VERSION 1

#if defined(_WIN32) && defined(NIMAID_SHARED)
#  define NIMAID_API __declspec(dllimport)
#else
#  define NIMAID_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef enum nimaid_status {
  NIMAID_OK = 0,
  NIMAID_ERR_INVALID_ARGUMENT = 1, /* NULL pointer, bad scale/colors, ...               */
  NIMAID_ERR_FONT = 2,             /* font missing, unreadable or not a TrueType (glyf) */
  NIMAID_ERR_PARSE = 3,            /* Mermaid syntax error                              */
  NIMAID_ERR_UNSUPPORTED = 4,      /* diagram type not supported                        */
  NIMAID_ERR_IO = 5,               /* cannot write the output file                      */
  NIMAID_ERR_OOM = 6,              /* out of memory                                     */
  NIMAID_ERR_INTERNAL = 7          /* bug in the library; please report                 */
} nimaid_status;

/* Opaque rendering context: owns the fonts. Create one, render many times. */
typedef struct nimaid_context nimaid_context;

/*
 * Rendering options. Always initialise with nimaid_options_init() (or NIMAID_OPTIONS_DEFAULT); the
 * struct_size field lets newer libraries accept structs compiled against older headers.
 * Passing NULL instead of a pointer means "all defaults".
 */
typedef struct nimaid_options {
  size_t struct_size;   /* set by nimaid_options_init */
  double scale;         /* PNG/GIF pixel scale, 2.0 = retina. Ignored for SVG. Must be > 0. Default 2.0 */
  const char *theme;    /* "default" "dark" "forest" "neutral" "base"; NULL/"" = from the diagram       */
  int colors;           /* 0 = truecolour PNG / 256-colour GIF; 2..256 = palette size. Default 0        */
  int svg_text;         /* SVG only: 1 = live <text>, 0 = outlined glyphs (identical everywhere). Def 0 */
  int legacy_dagre;     /* 1 = Mermaid-compatible node ordering (default), 0 = dagre_nim defaults       */
} nimaid_options;

#define NIMAID_OPTIONS_DEFAULT { sizeof(nimaid_options), 2.0, NULL, 0, 0, 1 }

static inline void nimaid_options_init(nimaid_options *o) {
  nimaid_options d = NIMAID_OPTIONS_DEFAULT;
  *o = d;
}

/* Straight-alpha RGBA8 pixels, row-major, width*height*4 bytes. Free `pixels` with nimaid_free(). */
typedef struct nimaid_image {
  int width;
  int height;
  uint8_t *pixels;
} nimaid_image;

/* ------------------------------------------------------------------ info */
NIMAID_API int         nimaid_abi_version(void);
NIMAID_API const char *nimaid_version(void);              /* "0.6.1" */
NIMAID_API const char *nimaid_status_string(int status);  /* static text for a nimaid_status */
NIMAID_API int         nimaid_has_embedded_font(void);    /* 1 if DejaVu Sans is compiled in (default) */
NIMAID_API int         nimaid_theme_count(void);
NIMAID_API const char *nimaid_theme_name(int index);      /* NULL if out of range */
/* "flowchart" "sequence" "state" "er" "class" "gantt" "gitgraph" "mindmap" "pie" "xychart" "timeline"
   "quadrant" "journey" "packet" "kanban" "radar" "treemap" "sankey" or "unknown". Never NULL. */
NIMAID_API const char *nimaid_detect_type(const char *text);

/* ------------------------------------------------------------------ context & fonts */
/* A new context uses the embedded DejaVu Sans and no emoji font: nimaid_context_new() is all you need. */
NIMAID_API nimaid_context *nimaid_context_new(void);               /* NULL on out-of-memory */
NIMAID_API void            nimaid_context_free(nimaid_context *ctx); /* NULL is fine */
NIMAID_API const char     *nimaid_context_error(const nimaid_context *ctx); /* "" if the last call succeeded */

/* Text font: TrueType with glyf outlines. data == NULL (size 0) restores the embedded font. Bytes are copied. */
NIMAID_API nimaid_status nimaid_context_set_font_file(nimaid_context *ctx, const char *path);
NIMAID_API nimaid_status nimaid_context_set_font_data(nimaid_context *ctx, const void *data, size_t size);
/* Colour emoji: Noto Color Emoji (OpenType-SVG). NULL / size 0 disables emoji (the default). */
NIMAID_API nimaid_status nimaid_context_set_emoji_font_file(nimaid_context *ctx, const char *path);
NIMAID_API nimaid_status nimaid_context_set_emoji_font_data(nimaid_context *ctx, const void *data, size_t size);

/* ------------------------------------------------------------------ rendering */
/* On success *out_buf holds *out_size bytes; free with nimaid_free(). On failure they are NULL / 0. */
NIMAID_API nimaid_status nimaid_render_png(nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                           uint8_t **out_buf, size_t *out_size);
NIMAID_API nimaid_status nimaid_render_gif(nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                           uint8_t **out_buf, size_t *out_size);
/* Complete SVG document, NUL-terminated (out_size, optional, excludes the NUL). Free with nimaid_free(). */
NIMAID_API nimaid_status nimaid_render_svg(nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                           char **out_str, size_t *out_size);
NIMAID_API nimaid_status nimaid_render_rgba(nimaid_context *ctx, const char *mermaid, const nimaid_options *opts,
                                            nimaid_image *out_image);
/* Writes a file; format from the extension: .svg, .gif, anything else = PNG. */
NIMAID_API nimaid_status nimaid_render_file(nimaid_context *ctx, const char *mermaid, const char *output_path,
                                            const nimaid_options *opts);

/* ------------------------------------------------------------------ encoders for your own pixels */
/* rgba: straight-alpha RGBA8, width*height*4 bytes. colors: 0 truecolour, 2..256 palette. */
NIMAID_API nimaid_status nimaid_encode_png(const void *rgba, int width, int height, int colors,
                                           uint8_t **out_buf, size_t *out_size);
NIMAID_API nimaid_status nimaid_encode_gif(const void *rgba, int width, int height, int colors,
                                           uint8_t **out_buf, size_t *out_size);

/* Releases memory returned by this library. NULL is fine. */
NIMAID_API void nimaid_free(void *p);
/* Allocates `size` bytes that nimaid_free() can release (NULL on failure). Needed by hosts that must place
 * input in the library's memory, e.g. WebAssembly; ordinary C programs can use malloc. */
NIMAID_API void *nimaid_alloc(size_t size);

#ifdef __cplusplus
}
#endif
#endif /* NIMAID_H */
