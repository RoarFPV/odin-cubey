# Cache-Friendly Triangle Rasterization Plan

Status: **implemented** (as a separate compile-time-switchable renderer backend)

## Summary

A second, tile-based renderer was added in `src/renderer_tiled.odin`, selected at
compile time with:

```
odin build src/ -define:RENDER_TILED=true
```

The original scanline renderer (`src/renderer.odin`) is untouched and still the
default. The switch lives in `game.odin` via `when RENDER_TILED { ... } else { ... }`
blocks for init, render, projection, and the UI render-target texture.

## Layout

- Framebuffer (320x200 x vec4 = 1MB) + depth (256KB) exceed L1/L2, so per-triangle
  whole-screen rasterization thrashed cache. Tiling shrinks the working set to
  an 8x8 tile slice (~1.25KB, fits L1).
- `HotTri` (SoA via `#soa[dynamic]`) holds only hot raster data: screen verts,
  precomputed edge line-equations `{A,B,C}`, `inv_area`, colors, uvs, camera-space
  normal, material index (not a by-value `Material`), integer pixel bbox, `z_avg`.
- Cold build data (transforms, clip/world verts, materials) is not retained.

## Pipeline

1. **Build** (`tile_mesh_render`): mirrors `mesh_render` transform loop, but emits
   `HotTri` after backface culling; materials deduped by name into an index.
2. **Bin** (`tile_render_end`): two-pass over each tri's tile-aligned bbox
   (counts -> prefix-sum `tileOffsets` -> fill `tileTris`).
3. **Sort**: each tile's tri-id run sorted by `z_avg` ascending (front-to-back).
4. **Raster** (`tile_raster_tri`): edge-function walking clipped to the tile, with
   incremental stepping (`f += d/dx` per column, `f += d/dy` per row), early-out
   when any edge < 0. Per-pixel: depth test **before** shading (early-z skips
   shading + depth write on occluded pixels), then bary-interp color/uv, texture
   sample, ambient + `dot(normal, light_dir)`.

`math.odin` helpers (`math_bary_interp`, `math_tri_edge`, `math_tri_normal`) are
reused as-is.

## Decisions

- **Compile-time switch** (not runtime) so the old renderer stays for A/B profiling.
- **8x8 tiles** (1000 tiles at 320x200; ~1.25KB color+depth slice per tile).
- **Edge-function rasterizer** replaces flat-top/bottom scanline.

## Files

- `src/renderer_tiled.odin` — new tiled backend (`RENDER_TILED` config, `TileRenderer`,
  `HotTri`, binning + raster + shading).
- `src/game.odin` — `when RENDER_TILED` wiring; shared `make_render_textures`
  helper (also fixes a pre-existing bug where `depth` image was formatted with the
  `screen` image handle); `active_width/height/screen_texture` helpers.
- `src/renderer.odin` — unchanged.
- `src/math.odin` — unchanged.

## Notes / follow-ups

- Removed a duplicate `vec4` declaration in `game.odin` (`vec4 :: linalg.Vector4f32`
  kept; the `#simd[4]f32` redefinition was a redeclaration error and is incompatible
  with `linalg.dot`/`linalg.cross` which only accept array types).
- `proj` was previously computed once at package init, so it used the renderer's
  default dimensions (`0x0` for the tiled backend -> NaN aspect -> nothing rendered).
  It is now built in `game_init` after the active renderer is initialized. This also
  fixes the old backend, which had been rendering with a stale 170/100 aspect.
- `-o:speed` builds crash in the Odin checker on the pre-existing `ui.Color{...}`
  alias literals (compiler assertion, present on pristine HEAD too). Debug builds
  (`task debug`) work for both backends.
- Optional later: exact per-scanline entry/exit tracking to skip outside pixels
  more cheaply; `#simd` bump if `linalg` simd variants are adopted.

## Progress

- [x] Split `TriRenderCmd` into cold + hot records (`HotTri`)
- [x] Material by index instead of by value
- [x] Tile binning (`TILE` 8, `tileTris`, `tileOffsets`)
- [x] Per-tile raster pass
- [x] Front-to-back sort within tiles + early-z
- [x] Edge-function rasterizer
- [x] Compile-time `RENDER_TILED` switch
