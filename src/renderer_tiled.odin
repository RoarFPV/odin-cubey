package cubey

import rl "vendor:raylib"

import "core:math"
import "core:math/linalg"
import "core:slice"

RENDER_TILED :: #config(RENDER_TILED, false)

TILE :: 8

// HotTri is the hot raster record: only what the rasterizer reads per pixel.
HotTri :: struct {
	screen:   [3]vec4, // screen-space, post-viewport
	edges:    [3]vec4, // edge line-equation coeffs {A, B, C}; inside >= 0
	inv_area: f32,
	colors:   [3]vec4,
	uvs:      [3]vec4,
	normal:   vec4, // camera-space normal for lighting
	mat:      u32,  // material index (not a by-value Material)
	bbox:     [4]i32, // minx, miny, maxx, maxy (inclusive pixels, clamped)
	z_avg:    f32,  // average screen z, for front-to-back tile sorting
}

TileRenderer :: struct {
	width, height: i32,
	screenTexture: rl.Texture2D,
	depthTexture:  rl.Texture2D,
	screenBuffer:  [dynamic]vec4,
	depthBuffer:   [dynamic]f32,
	depthTest:     bool,
	depthFlipped:  bool,
	backfaceCull:  bool,
	tris:          #soa[dynamic]HotTri,
	materials:     [dynamic]Material,
	nTilesX:       int,
	nTilesY:       int,
	tileTris:      [dynamic]u32, // flattened per-tile triangle ids
	tileOffsets:   [dynamic]u32, // prefix-sum; len nTiles+1
	tileCounts:    [dynamic]u32, // scratch: per-tile counts
	tileCursor:    [dynamic]u32, // scratch: fill cursor
}

tile_renderer: TileRenderer

tile_renderer_init :: proc(width, height: i32) {
	tile_renderer.width = width
	tile_renderer.height = height
	tile_renderer.depthTest = true
	tile_renderer.depthFlipped = true
	tile_renderer.backfaceCull = true
	tile_renderer.depthBuffer = make_dynamic_array_len([dynamic]f32, width * height)
	tile_renderer.screenBuffer = make_dynamic_array_len([dynamic]vec4, width * height)
	tile_renderer.nTilesX = (int(width) + TILE - 1) / TILE
	tile_renderer.nTilesY = (int(height) + TILE - 1) / TILE
}

tile_render_begin :: proc() {
	tracy.Zone()
	clear(&tile_renderer.tris)
	clear(&tile_renderer.materials)
	slice.fill(tile_renderer.screenBuffer[:], vec4{15, 17, 26, 255} / 255)
	slice.fill(tile_renderer.depthBuffer[:], far)

	nTiles := tile_renderer.nTilesX * tile_renderer.nTilesY
	resize(&tile_renderer.tileCounts, nTiles)
	resize(&tile_renderer.tileCursor, nTiles)
	slice.fill(tile_renderer.tileCounts[:], 0)
}

tile_register_material :: proc(mat: Material) -> u32 {
	for m, i in tile_renderer.materials {
		if m.name == mat.name {
			return auto_cast i
		}
	}
	append(&tile_renderer.materials, mat)
	return auto_cast len(tile_renderer.materials) - 1
}

tile_model_render :: proc(model: ^Model, material: Material, mmat: ^mat44, view: ^mat44, proj: ^mat44) {
	tracy.Zone()
	for m in 0 ..< model.meshCount {
		mesh := &model.meshes[m]
		tile_mesh_render(mesh, material, mmat, view, proj)
	}
}

tile_mesh_render :: proc(
	mesh: ^Mesh,
	material: Material,
	model: ^mat44,
	view: ^mat44,
	proj: ^mat44,
) {
	tracy.Zone()
	triCount := cast(int)mesh.triangleCount
	mv := view^ * model^
	mvp := proj^ * mv
	vp := vec4{auto_cast tile_renderer.width, auto_cast tile_renderer.height, 2, 2} / 2.0

	matIdx := tile_register_material(material)

	screen: [3]vec4
	world:  [3]vec4
	cam:    [3]vec4
	colors: [3]vec4
	uvs:    [3]vec4

	width := int(tile_renderer.width)
	height := int(tile_renderer.height)

	index := 0
	for t in 0 ..< triCount {
		for i in 0 ..< 3 {
			ind := mesh.indices[index]
			index += 1
			indElem := ind * 3
			v := vec4 {
				mesh.vertices[indElem + 0],
				mesh.vertices[indElem + 1],
				mesh.vertices[indElem + 2],
				1,
			}

			if mesh.colors != nil {
				colors[i] =
						vec4 {
							auto_cast mesh.colors[ind * 4 + 0],
							auto_cast mesh.colors[ind * 4 + 1],
							auto_cast mesh.colors[ind * 4 + 2],
							1.0,
						} / 255.0
			} else {
				colors[i] = vec4{0, 0, 0, 1}
			}

			clip := mvp * v
			w := 1 / clip.w
			screen[i] = viewport_scale(vp, clip * w)

			if mesh.texcoords != nil {
				uvs[i] = vec4 {
					abs(math.mod(mesh.texcoords[ind * 2 + 0], 2)),
					abs(math.mod(mesh.texcoords[ind * 2 + 1], 2)),
					1,
					1,
				}
			} else {
				uvs[i] = vec4{0, 0, 0, 0}
			}

			world[i] = model^ * v
			cam[i] = mv * v
		}

		area := math_tri_edge(screen[0], screen[1], screen[2])
		if area <= 0 {
			continue
		}

		normal := math_tri_normal(cam)
		if tile_renderer.backfaceCull && linalg.dot(cam[0], normal) <= 0 {
			continue
		}

		minB := vec2 {
			min(min(screen[0].x, screen[1].x), screen[2].x),
			min(min(screen[0].y, screen[1].y), screen[2].y),
		}
		maxB := vec2 {
			max(max(screen[0].x, screen[1].x), screen[2].x),
			max(max(screen[0].y, screen[1].y), screen[2].y),
		}

		tri := HotTri {
			screen   = screen,
			edges    = tile_edges(screen),
			inv_area = 1 / area,
			colors   = colors,
			uvs      = uvs,
			normal   = math_tri_normal(world),
			mat      = matIdx,
			bbox     = {
				i32(clamp(int(math.floor(minB.x)), 0, width - 1)),
				i32(clamp(int(math.floor(minB.y)), 0, height - 1)),
				i32(clamp(int(math.ceil(maxB.x)) - 1, 0, width - 1)),
				i32(clamp(int(math.ceil(maxB.y)) - 1, 0, height - 1)),
			},
			z_avg    = (screen[0].z + screen[1].z + screen[2].z) / 3,
		}
		append(&tile_renderer.tris, tri)
	}
}

// tile_edges precomputes the edge line equations so the rasterizer can step
// incrementally. For edge from a to b: f(p) = A*x + B*y + C, inside iff f >= 0.
tile_edges :: proc "contextless" (sv: [3]vec4) -> [3]vec4 {
	pairs := [3][2]int{{1, 2}, {2, 0}, {0, 1}}
	e: [3]vec4
	for p, i in pairs {
		a := sv[p[0]]
		b := sv[p[1]]
		e[i] = vec4{b.y - a.y, a.x - b.x, a.y * b.x - a.x * b.y, 0}
	}
	return e
}

tile_render_end :: proc() {
	tracy.Zone()
	nX := tile_renderer.nTilesX
	nY := tile_renderer.nTilesY
	nTiles := nX * nY
	triCount := len(tile_renderer.tris)
	if triCount == 0 {
		return
	}

	// pass 1: per-tile triangle counts
	slice.fill(tile_renderer.tileCounts[:], 0)
	for ti in 0 ..< triCount {
		b := tile_renderer.tris[ti].bbox
		for ty in int(b[1]) / TILE ..= int(b[3]) / TILE {
			for tx in int(b[0]) / TILE ..= int(b[2]) / TILE {
				tile_renderer.tileCounts[ty * nX + tx] += 1
			}
		}
	}

	// prefix sum -> tileOffsets
	resize(&tile_renderer.tileOffsets, nTiles + 1)
	total: int = 0
	for i in 0 ..< nTiles {
		tile_renderer.tileOffsets[i] = auto_cast total
		total += int(tile_renderer.tileCounts[i])
	}
	tile_renderer.tileOffsets[nTiles] = auto_cast total

	// pass 2: fill per-tile triangle id runs
	resize(&tile_renderer.tileTris, total)
	slice.fill(tile_renderer.tileCursor[:nTiles], 0)
	copy(tile_renderer.tileCursor[:nTiles], tile_renderer.tileOffsets[:nTiles])
	for ti in 0 ..< triCount {
		b := tile_renderer.tris[ti].bbox
		for ty in int(b[1]) / TILE ..= int(b[3]) / TILE {
			for tx in int(b[0]) / TILE ..= int(b[2]) / TILE {
				tile := ty * nX + tx
				tile_renderer.tileTris[tile_renderer.tileCursor[tile]] = auto_cast ti
				tile_renderer.tileCursor[tile] += 1
			}
		}
	}

	// per tile: sort front-to-back, then rasterize
	for tile in 0 ..< nTiles {
		start := int(tile_renderer.tileOffsets[tile])
		end := int(tile_renderer.tileOffsets[tile + 1])
		if end - start > 1 {
			slice.sort_by(tile_renderer.tileTris[start:end], proc(a, b: u32) -> bool {
				return tile_renderer.tris[a].z_avg < tile_renderer.tris[b].z_avg
			})
		}
		for i in start ..< end {
			tile_raster_tri(tile, int(tile_renderer.tileTris[i]))
		}
	}
}

// tile_raster_tri rasterizes one triangle clipped to one tile, stepping the
// edge functions incrementally (f += d/dx per column, f += d/dy per row).
tile_raster_tri :: proc(tileIdx, triIdx: int) {
	tri := tile_renderer.tris[triIdx]
	nX := tile_renderer.nTilesX
	tx := tileIdx % nX
	ty := tileIdx / nX
	tileX0 := tx * TILE
	tileY0 := ty * TILE

	x0 := max(int(tri.bbox[0]), tileX0)
	x1 := min(int(tri.bbox[2]), tileX0 + TILE - 1)
	y0 := max(int(tri.bbox[1]), tileY0)
	y1 := min(int(tri.bbox[3]), tileY0 + TILE - 1)
	if x0 > x1 || y0 > y1 {
		return
	}

	e := tri.edges
	inv := tri.inv_area
	sv := tri.screen

	px := f32(x0) + 0.5
	py := f32(y0) + 0.5
	e0 := e[0].x * px + e[0].y * py + e[0].z
	e1 := e[1].x * px + e[1].y * py + e[1].z
	e2 := e[2].x * px + e[2].y * py + e[2].z

	width := int(tile_renderer.width)
	mat := tile_renderer.materials[tri.mat]

	for y in y0 ..= y1 {
		c0 := e0
		c1 := e1
		c2 := e2
		for x in x0 ..= x1 {
			if c0 >= 0 && c1 >= 0 && c2 >= 0 {
				b0 := c0 * inv
				b1 := c1 * inv
				b2 := c2 * inv
				bary := vec4{b0, b1, b2, 1}
				z := b0 * sv[0].z + b1 * sv[1].z + b2 * sv[2].z
				idx := y * width + x

				if !tile_renderer.depthTest {
					tile_shade_pixel(idx, tri, bary, mat)
				} else {
					d := tile_renderer.depthBuffer[idx]
					pass := (z < d) if tile_renderer.depthFlipped else (z > d)
					if pass {
						tile_renderer.depthBuffer[idx] = z
						tile_shade_pixel(idx, tri, bary, mat)
					}
				}
			}
			c0 += e[0].x
			c1 += e[1].x
			c2 += e[2].x
		}
		e0 += e[0].y
		e1 += e[1].y
		e2 += e[2].y
	}
}

tile_shade_pixel :: proc(idx: int, tri: HotTri, bary: vec4, mat: Material) {
	cBary := math_bary_interp(bary, tri.colors)
	vertColor := vec4{cBary.x, cBary.y, cBary.z, 1.0}

	uv := math_bary_interp(bary, tri.uvs)
	cTex := mat_sample_texture(mat, uv.xy) + vertColor
	cTex *= mat.ambient
	cTex += math.max(linalg.dot(tri.normal, renderer.light_dir), 0) * renderer.light_intensity

	c := linalg.saturate(cTex)
	c.a = 1
	tile_renderer.screenBuffer[idx] = c
}
