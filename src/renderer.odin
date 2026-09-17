package cubey

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:reflect"
import "core:simd"
import "core:slice"
import "core:strings"

Renderer :: struct {
	width:             i32,
	height:            i32,
	screenTexture:     rl.Texture2D,
	screenBuffer:      [dynamic]vec4,
	depthTexture:      rl.Texture2D,
	depthBuffer:       [dynamic]f32,
	depthFipped:       bool,
	depthTest:         bool,
	backfaceCull:      bool,
	clipping:          bool,
	debugNormals:      bool,
	onlyClipped:       bool,
	commands:          #soa[dynamic]TriRenderCmd,
	nextRenderCmdId:   u32,
	totalTriProcessed: u32,
	triRenderIdStart:  u32,
	triRenderIdCount:  u32,
	debugOffset:       f32,
	nearZ:             f32,
	light_dir:         vec4,
	light_intensity:   f32,
	meshTransforCache: [dynamic]MeshTransformData,
}

MeshTransformData :: struct {
	model:  vec4,
	world:  vec4,
	clip:   vec4,
	camera: vec4,
	screen: vec4,
	normal: vec4,
}

Transform :: struct {
	mvp:   mat44,
	// position: vec4,
	// rotation: quaternion128,
	model: ^mat44,
	view:  ^mat44,
	proj:  ^mat44,
}

Mesh :: rl.Mesh

Material :: struct {
	name:    string,
	texture: rl.Image,
	ambient: f32,
}

TriRenderState :: enum {
	Bounds,
	Bary,
	Pixel,
	NextPixel,
	Complete,
}

TriRenderStateData :: struct {
	min:               vec4,
	max:               vec4,
	pixel_final:       vec4,
	pixel_bary_norm:   vec4,
	pixel_bary_calc:   vec4,
	pixel_bary_c:      vec4,
	pixel_bary:        vec4,
	pixel_color:       rl.Color,
	pixel_outside:     bool,
	pixel_was_outside: bool,
	pixel_step:        vec4,
	step:              TriRenderState,
}

TriRenderCmd :: struct {
	id:          u32,
	mesh:        ^Mesh,
	transform:   Transform,
	verticies:   [3]vec4,
	vertClip:    [3]vec4,
	vertCamera:  [3]vec4,
	vertScreen:  [3]vec4,
	vertNormals: [3]vec4,
	vertWorld:   [3]vec4,
	indicies:    [3]u16,
	colors:      [3]vec4,
	uvs:         [3]vec4,
	area:        f32,
	inv_area:    f32,
	// st:         TriRenderStateData,
	bary:        BaryData,
	edges:       [3]vec4,
	normal:      vec4,
	material:    Material,
	clipCount:   u32,
	allOut:      [2]bool,
}

renderer := Renderer {
	width        = 170,
	height       = 100,
	clipping     = true,
	backfaceCull = true,
	debugOffset  = 1,
	nearZ        = near,
}


IntersectClipResult :: struct {
	v:     vec4,
	delta: f32,
}

render_test_depth :: proc(p: vec4, write: bool, less: bool) -> (res: bool) {
	// tracy.Zone()
	idx := i32(p.y) * renderer.width + i32(p.x)
	if idx < 0 || idx >= auto_cast len(renderer.depthBuffer) {
		return false
	}
	d := renderer.depthBuffer[idx]
	z := 1.0 - p.z
	res = (z < d) if less else (z > d)
	if res && write {
		renderer.depthBuffer[idx] = z
	}

	return res
}

renderer_init :: proc(width, height: i32) {
	renderer.width = width
	renderer.height = height
	renderer.depthTest = true
	renderer.depthFipped = false
	renderer.backfaceCull = true
	renderer.depthBuffer = make_dynamic_array_len([dynamic]f32, width * height)
	renderer.screenBuffer = make_dynamic_array_len([dynamic]vec4, width * height)
	renderer.nextRenderCmdId = 1
	renderer.triRenderIdCount = 10
	renderer.triRenderIdStart = 0
	renderer.light_dir = linalg.normalize(vec4{-0.25, -0.55, 0.0, 0.0})
	renderer.light_intensity = 0.8
}

model_render :: proc(model: ^Model, material: Material, mmat: ^mat44, view: ^mat44, proj: ^mat44) {
	tracy.Zone()
	for m in 0 ..< model.meshCount {
		mesh := &model.meshes[m]

		// material := model.materials[model.meshMaterial[m]]
		mesh_render(mesh, material, mmat, view, proj)
	}
}

mesh_render :: proc(
	mesh: ^Mesh,
	material: Material,
	model: ^mat44,
	view: ^mat44,
	proj: ^mat44,
	draw: bool = true,
) {

	if cap(renderer.meshTransforCache) < auto_cast mesh.vertexCount {
		renderer.meshTransforCache = make_dynamic_array_len(
			[dynamic]MeshTransformData,
			mesh.vertexCount,
		)
		resize_dynamic_array(&renderer.meshTransforCache, mesh.vertexCount)
	}


	triCount := cast(int)mesh.triangleCount

	// reserve(&render_commands, triCount)
	mv := view^ * model^
	mvp := proj^ * mv
	viewProj := proj^ * view^

	cmd := TriRenderCmd {
		mesh      = mesh,
		transform = {mvp, model, view, proj},
		material  = material,
		allOut    = {true, true},
	}

	vp := vec4{auto_cast renderer.width, auto_cast renderer.height, 2, 2} / 2.0


	for i in 0 ..< mesh.vertexCount {
		c := &renderer.meshTransforCache[i]
		v := vec4{mesh.vertices[i * 3 + 0], mesh.vertices[i * 3 + 1], mesh.vertices[i * 3 + 2], 1}

		n := vec4{mesh.normals[i * 3 + 0], mesh.normals[i * 3 + 1], mesh.normals[i * 3 + 2], 1}

		c.model = v
		c.world = (model^ * v)
		c.camera = (mv * v)
		c.clip = mvp * v
		c.normal = model^ * n

		w := 1 / c.clip.w


		c.screen = c.clip * w

		c.clip *= w

		c.screen = viewport_scale(vp, c.screen)
		c.screen.z = 1/c.screen.z
	}


	index: int = 0
	for t in 0 ..< triCount {
		cmd.id = u32(t)
		renderer.totalTriProcessed += 1
		#unroll for i in 0 ..< 3 {
			ind := mesh.indices[index]
			index += 1
			cmd.indicies[i] = ind
			c := &renderer.meshTransforCache[ind]

			if mesh.colors != nil {
				cmd.colors[i] =
					vec4 {
						auto_cast mesh.colors[ind * 4 + 0],
						auto_cast mesh.colors[ind * 4 + 1],
						auto_cast mesh.colors[ind * 4 + 2],
						1.0,
					} /
					255.0
			}


			cmd.verticies[i] = c.model
			cmd.vertWorld[i] = c.world
			cmd.vertCamera[i] = c.camera
			cmd.vertClip[i] = c.clip
			cmd.vertScreen[i] = c.screen
			cmd.vertNormals[i] = c.normal

			if mesh.texcoords != nil {
				cmd.uvs[i] = vec4 {
					abs(math.mod(mesh.texcoords[ind * 2 + 0], 2)),
					abs(math.mod(mesh.texcoords[ind * 2 + 1], 2)),
					1,
					1,
				}
			}


			cmd.colors[i] /= c.screen.z
			cmd.uvs[i] /= c.screen.z


			cmd.allOut[0] |= cmd.vertCamera[i].z <= renderer.nearZ

			// cmd.allOut[0] &= cmd.vertScreen[i].x < 0 || cast(i32)cmd.vertScreen[i].x > renderer.width
			// cmd.allOut[1] &= cmd.vertScreen[i].y < 0 || cast(i32)cmd.vertScreen[i].y > renderer.height
			// cmd.colors[i].r = cmd.vertScreen[i].z < 0 ? -cmd.vertScreen[i].z : 0
		}

		// out side of frustum
		if (cmd.vertClip[0].x) >= 1 && (cmd.vertClip[1].x) >= 1 && (cmd.vertClip[2].x) >= 1 {
			continue
		}

		if (cmd.vertClip[0].y) >= 1 && (cmd.vertClip[1].y) >= 1 && (cmd.vertClip[2].y) >= 1 {
			continue
		}

		if (cmd.vertClip[0].z) >= 1 && (cmd.vertClip[1].z) >= 1 && (cmd.vertClip[2].z) >= 1 {
			continue
		}

		if (cmd.vertClip[0].x) <= -1 && (cmd.vertClip[1].x) <= -1 && (cmd.vertClip[2].x) <= -1 {
			continue
		}

		if (cmd.vertClip[0].y) <= -1 && (cmd.vertClip[1].y) <= -1 && (cmd.vertClip[2].y) <= -1 {
			continue
		}

		if (cmd.vertClip[0].z) <= -1 && (cmd.vertClip[1].z) <= -1 && (cmd.vertClip[2].z) <= -1 {
			continue
		}

		cmd.area = math_tri_edge(cmd.vertScreen[0], cmd.vertScreen[1], cmd.vertScreen[2])

		if cmd.allOut[0] && !clipTri(cmd) {
			continue
		}

		if (renderer.backfaceCull && cmd.area <= 0.0) {
			continue
		}


		cmd.bary = math_bary_data(cmd.vertScreen)
		cmd.edges = {
			cmd.vertScreen[2] - cmd.vertScreen[1],
			cmd.vertScreen[0] - cmd.vertScreen[2],
			cmd.vertScreen[1] - cmd.vertScreen[0],
		}
		cmd.inv_area = 1 / cmd.area


		cmd.normal = math_tri_normal(cmd.vertWorld)

		if !clipTri(cmd) {
			continue
		}

		renderer.nextRenderCmdId += 1
		append(&renderer.commands, cmd)

	}
}

@(require_results)
viewport_scale :: proc "contextless" (halfViewport: vec4, v: vec4) -> vec4 {
	half := halfViewport
	vv := (half * (v * {1, -1, 1, 1})) + (half * {1, 1, 0, 1})
	// vr := vec4{half.x * v.x + half.x, half.y * -v.y + half.y, v.z}
	return vv
}


edgeFunction :: proc "contextless" (a:vec4, b:vec4, c:vec4) -> f32
{
    return (c.x - a.x) * (b.y - a.y) - (c.y - a.y) * (b.x - a.x);
}



tri_bbox_render :: proc(cmds: #soa[]TriRenderCmd) {
	cmd := cmds[0]
	sv := cmd.vertScreen

	min := sv[0]
	max := sv[0]
	for v in 1 ..< 3 {
		max = linalg.max(max, sv[v])
		min = linalg.min(min, sv[v])
	}

	swidth := f32(renderer.width)
	sheight := f32(renderer.height)

	start := vec2{clamp(min.x, 0, swidth - 1), clamp(min.y, 0.0, sheight - 1)}
	end := vec2{clamp(max.x, 0, swidth - 1), clamp(max.y, 0.0, sheight - 1)}

	
	vtopleft := []bool {
		((cmd.edges[0].y == 0 && cmd.edges[0].x > 0) || cmd.edges[0].y > 0),
		((cmd.edges[1].y == 0 && cmd.edges[1].x > 0) || cmd.edges[1].y > 0),
		((cmd.edges[2].y == 0 && cmd.edges[2].x > 0) || cmd.edges[2].y > 0),}

	for y in start.y ..= end.y + 1 {

		tri_render_single_line(
			cmds,
			vtopleft,
			cast(i16)(start.x - 1.5),
			cast(i16)(end.x + 1.5),
			cast(i16)(y),
		)
	}


	// draw_world_point(&cmd.transform.mvp, cmd.vertWorld[0], {1,1,0,1})
	// draw_world_point(&cmd.transform.mvp, cmd.vertWorld[1], {1,1,0,1})
	// draw_world_point(&cmd.transform.mvp, cmd.vertWorld[2], {1,1,0,1})

	// draw_screen_pixel(cmd.vertScreen[0], {1,0,0,1})
	// draw_screen_pixel(cmd.vertScreen[1], {0,1,0,1})
	// draw_screen_pixel(cmd.vertScreen[2], {0,0,1,1})

}

tri_render_scanline :: proc(cmd: #soa[]TriRenderCmd, index: u32) {
	tracy.Zone()
	tri := cmd[0]

	if renderer.onlyClipped && tri.clipCount < 1 {
		return
	}

	if index < renderer.triRenderIdStart ||
	   index >= renderer.triRenderIdStart + renderer.triRenderIdCount {
		return
	}

	sv := tri.vertScreen

	tri_bbox_render(cmd)


	// slice.sort_by(sv[:], proc(a, b: vec4) -> bool {
	// 	return a.y < b.y
	// })	

	// sv += 0.5

	// if int(sv[0].y) == int(sv[1].y) {
	// 	// flat top
	// 	tri_render_bress_flat_top(cmd, sv)
	// } else if int(sv[1].y) == int(sv[2].y) {
	// 	// flat bottom
	// 	tri_render_bress_flat_bottom(cmd, sv)
	// } else {
	// 	// mid point on longest edge
	// 	v4 := vec4 {
	// 		sv[0].x + ((sv[1].y - sv[0].y) / (sv[2].y - sv[0].y)) * (sv[2].x - sv[0].x),
	// 		sv[1].y,
	// 		0,
	// 		1,
	// 	}

	// 	assert(sv[1].y == v4.y)
	// 	tri_render_bress_flat_bottom(cmd, {sv[0], sv[1], v4})

	// 	tri_render_bress_flat_top(cmd, {sv[1], v4, sv[2]})
	// }

	// if renderer.debugNormals {
	// 	vp := tri.transform.proj^ * tri.transform.view^
	// 	for i in 0..<3 {
	// 		normalOrigin := tri.vertWorld[i]
	// 		draw_world_line(&vp, normalOrigin, normalOrigin + tri.vertNormals[i] * 0.1, {1.0, 0, 0, 1})
	// 	}

	// }
}

tri_render_bress_flat_bottom :: proc(cmd: #soa[]TriRenderCmd, sv: [3]vec4) {
	tri := cmd[0]
	assert(cast(i16)sv[1].y == cast(i16)sv[2].y)
	v := sv

	li1 := 1
	li2 := 2

	if v[1].x > v[2].x {
		li1 = 2
		li2 = 1
	}

	l := bress_line_init(
		auto_cast v[0].x,
		auto_cast v[0].y,
		auto_cast v[li1].x,
		auto_cast v[li1].y,
	)
	r := bress_line_init(
		auto_cast v[0].x,
		auto_cast v[0].y,
		auto_cast v[li2].x,
		auto_cast v[li2].y,
	)

	swidth := cast(i16)renderer.width - 1
	sheight := cast(i16)renderer.height - 1

	clipY := cast(i16)v[0].y
	clipX := cast(i16)v[0].x

	if clipY < 0 {
		bress_line_next_until_y(&l, 0)
		bress_line_next_until_y(&r, 0)
	}

	endy := min(sheight, cast(i16)v[1].y)

	vtopleft := []bool {
		((tri.edges[0].y == 0 && tri.edges[0].x > 0) || tri.edges[0].y > 0),
		((tri.edges[1].y == 0 && tri.edges[1].x > 0) || tri.edges[1].y > 0),
		((tri.edges[2].y == 0 && tri.edges[2].x > 0) || tri.edges[2].y > 0),}

	for y in l.cy ..= endy {
		assert(l.cy == r.cy)
		xs := clamp(l.cx, 0, swidth)
		xf := clamp(r.cx, 0, swidth)

		tri_render_single_line(cmd, vtopleft, auto_cast (xs), auto_cast (xf), auto_cast l.cy)


		bress_line_next_until_y(&l, y)
		bress_line_next_until_y(&r, y)
	}

	cmd[0].clipCount -= 1
}

tri_render_bress_flat_top :: proc(cmd: #soa[]TriRenderCmd, sv: [3]vec4) {
	tri := cmd[0]
	assert(cast(i16)sv[0].y == cast(i16)sv[1].y)

	v := sv

	li1 := 0
	li2 := 1

	if v[0].x > v[1].x {
		li1 = 1
		li2 = 0
	}

	l := bress_line_init(
		auto_cast v[li1].x,
		auto_cast v[li1].y,
		auto_cast v[2].x,
		auto_cast v[2].y,
	)
	r := bress_line_init(
		auto_cast v[li2].x,
		auto_cast v[li2].y,
		auto_cast v[2].x,
		auto_cast v[2].y,
	)

	swidth: i16 = auto_cast renderer.width - 1
	sheight: i16 = auto_cast renderer.height - 1

	clipY := cast(i16)v[0].y

	if clipY < 0 {
		bress_line_next_until_y(&l, 0)
		bress_line_next_until_y(&r, 0)
	}

	endy := min(sheight, cast(i16)v[2].y)

	vtopleft := []bool {
		((tri.edges[0].y == 0 && tri.edges[0].x > 0) || tri.edges[0].y > 0),
		((tri.edges[1].y == 0 && tri.edges[1].x > 0) || tri.edges[1].y > 0),
		((tri.edges[2].y == 0 && tri.edges[2].x > 0) || tri.edges[2].y > 0),
	}

	for y in l.cy ..= endy {
		assert(l.cy == r.cy)
		xs := clamp(l.cx, 0, swidth)
		xf := clamp(r.cx, 0, swidth)

		tri_render_single_line(cmd, vtopleft, auto_cast (xs), auto_cast (xf), auto_cast l.cy)

		bress_line_next_until_y(&l, y)
		bress_line_next_until_y(&r, y)
	}

	cmd[0].clipCount -= 1
}

tri_render_single_line :: proc(scmd: #soa[]TriRenderCmd, vtopleft:[]bool, x1: i16, x2: i16, y: i16) {
	// tracy.Zone()
	cmd := scmd[0]
	sv := cmd.vertScreen

	xs := x1
	xf := x2

	inside := false
	first := true

	


	for x in xs ..= xf {
		p := vec4{auto_cast x, auto_cast y, 0, 1}

		
		// pBary := vec4{
		// 	edgeFunction(sv[1], sv[2], p), // Signed area of the triangle v1v2p multiplied by 2
		// 	edgeFunction(sv[2], sv[0], p), // Signed area of the triangle v2v0p multiplied by 2
		// 	edgeFunction(sv[0], sv[1], p), 1} // Signed area of the triangle v0v1p multiplied by 2

		
		// pBary := math_barycentric_coords(baryData, cmd.vertScreen, p)

		pBary := math_barycentric_coords_edge_ba(cmd.vertScreen, cmd.edges, p)
		// pBary *= cmd.inv_area

		overlaps0 := (pBary.x == 0 ? vtopleft[0] : (pBary.x > 0))
		overlaps1 := (pBary.y == 0 ? vtopleft[1] : (pBary.y > 0))
		overlaps2 := (pBary.z == 0 ? vtopleft[2] : (pBary.z > 0))

		if !(overlaps0 && overlaps1 && overlaps2) {
			// if pBary.x < 0 || pBary.y < 0 || pBary.z < 0  {
			// if inside {
			// 	break
			// }

			continue
		}

		pBary *= cmd.inv_area

		// w is 1/z
		// p.z = (1.0 + (pBary.x * sv[0].z + pBary.y * sv[1].z + pBary.z * sv[2].z)) / 2
		p.z = 1 / (pBary.x * sv[0].z + pBary.y * sv[1].z + pBary.z * sv[2].z) 
		// z := 1 / (pBary.x * sv[0].w + pBary.y * sv[1].w + pBary.z * sv[2].w)

		if renderer.depthTest && !render_test_depth(p, true, renderer.depthFipped) {
			continue
		}


		cBary := math_bary_interp(pBary, cmd.colors) / p.z
		vertColor := vec4{cBary.x, cBary.y, cBary.z, 1.0}

		nBary := math_bary_interp(pBary, cmd.vertNormals)
		pxNorm := vec4{nBary.x, nBary.y, nBary.z, 1.0}
		// pxNorm := cmd.normal

		uv := math_bary_interp(pBary, cmd.uvs) / p.z
		cTex := mat_sample_texture(cmd.material, uv.xy) + vertColor
		// cTex := vec4{0,0,0,1}

		color := linalg.pow(cTex, vec4(2.2))

		color =(color * cmd.material.ambient) +
			color *
			(math.max(linalg.dot(pxNorm, -renderer.light_dir), 0) * renderer.light_intensity)


		// HDR tonemapping
		color = color / (color + vec4(1.0))
		// gamma correct
		color = linalg.pow(color, vec4(1.0 / 2.2))

		color = linalg.saturate(color)
		color.a = 1

		draw_screen_pixel(p, color)

	}
}

draw_screen_pixel :: proc(pos: vec4, pixel: vec4) {
	// tracy.Zone()
	x := cast(u32)pos.x
	y := cast(u32)pos.y

	if x < 0 || y < 0 || x >= auto_cast renderer.width || y >= auto_cast renderer.height {
		return
	}
	w := cast(u32)renderer.width

	renderer.screenBuffer[y * w + x] = pixel
}

mat_sample_texture :: proc(mat: Material, uv: vec2) -> vec4 {
	// tracy.Zone()
	size := vec2{auto_cast mat.texture.width - 1, auto_cast mat.texture.height - 1}
	sp := linalg.array_cast(linalg.saturate(uv) * size, i32)
	color := rl.GetImageColor(mat.texture, sp.x, sp.y)

	return linalg.array_cast(color, f32) / 255.0

}

render_begin :: proc() {
	tracy.Zone()
	clear(&renderer.commands)
	renderer.nextRenderCmdId = 1
	renderer.totalTriProcessed = 0
	// renderer.depthFipped = !renderer.depthFipped
	slice.fill(renderer.screenBuffer[:], vec4{15, 17, 26, 255} / 255)
	slice.fill(renderer.depthBuffer[:], 0)
}

render_end :: proc() {
	tracy.Zone()
	i := 0

	for i: u32 = 0; i < renderer.nextRenderCmdId - 1; i += 1 {
		tri_render_scanline(renderer.commands[i:i + 1], i)
		// tri_bbox_render(renderer.commands[i:i+1])
		// i += 1
	}

	// for &cmd in renderer.commands {
	// 	tri_render_scanline(cmd)
	// }
}

intersectClipEdge :: proc(
	plane: f32,
	outPoint: vec4,
	inPoint: vec4,
	axis: int = 2,
) -> IntersectClipResult {

	// const aval = p.v[axis];
	dw := abs(plane - outPoint[axis])

	toOut := outPoint - inPoint

	total := toOut[axis]
	delta := 1.0 - dw / total

	// point along this edge that lies on boundary
	offset := toOut * delta

	np := inPoint + offset
	np[axis] = plane

	return {v = np, delta = delta}
}

addClippedTri :: proc(cmd: TriRenderCmd, points: [3]vec4, barycoords: [3]vec4) {
	tracy.Zone()
	tri := cmd
	tri1 := TriRenderCmd(tri)
	tri1.clipCount += 1

	assert(&tri != &tri1)

	vp := vec4{auto_cast renderer.width, auto_cast renderer.height, 2, 2} / 2.0
	
	#unroll for i in 0 ..< 3 {
		tri1.normal = tri.normal
		tri1.vertCamera[i] = points[i]
		vc := points[i].xyzz
		vc.w = 1

		clipV := tri1.transform.proj^ * vc
		tri1.vertScreen[i] = clipV * (1 / clipV.w)

		tri1.vertClip[i] = clipV / clipV.w

		// viewport scale
		
		tri1.vertScreen[i] = viewport_scale(vp, tri1.vertScreen[i])
		tri1.vertScreen[i].z = 1 / tri1.vertClip[i].z

		#unroll for c in 0 ..< 3 {
			tri1.colors[c] = math_bary_interp(barycoords[c], tri.colors)
			tri1.uvs[c] = math_bary_interp(barycoords[c], tri.uvs)
			tri1.vertNormals[c] = math_bary_interp(barycoords[c], tri.vertNormals)
		}
	}

	tri1.bary = math_bary_data(tri1.vertScreen)
	tri1.edges = {
		tri1.vertScreen[2] - tri1.vertScreen[1],
		tri1.vertScreen[0] - tri1.vertScreen[2],
		tri1.vertScreen[1] - tri1.vertScreen[0],
	}

	tri1.area = math_tri_edge(tri1.vertScreen[0], tri1.vertScreen[1], tri1.vertScreen[2])
	tri1.inv_area = 1 / tri1.area

	// TODO: interpolate all value
	tri1.normal = math_tri_normal(tri1.vertWorld)
	tri1.id = tri.id
	renderer.nextRenderCmdId += 1

	append(&renderer.commands, tri1)
}

world_to_screen :: proc(mvp: ^mat44, p: vec4) -> vec4 {
	vc := vec4{p.x, p.y, p.z, 1}
	clip := mvp^ * vc
	projected := clip / clip.w

	// viewport scale
	vp := vec4{auto_cast renderer.width, auto_cast renderer.height, 2, 0} / 2.0
	screen := viewport_scale(vp, projected)

	return screen
}

draw_world_point :: proc(mvp: ^mat44, p: vec4, color: vec4) {
	screen := world_to_screen(mvp, p)
	draw_screen_pixel(screen, color)
}

draw_world_line :: proc(mvp: ^mat44, ps: vec4, pe: vec4, color: vec4) {
	sps := world_to_screen(mvp, ps)
	spe := world_to_screen(mvp, pe)
	// draw_screen_line(sps, spe, color)
	l := bress_line_init(auto_cast sps.x, auto_cast sps.y, auto_cast spe.x, auto_cast spe.y)
	bress_line_draw(&l, color)
}

// plotLine(x0, y0, x1, y1)
//     dx = abs(x1 - x0)
//     sx = x0 < x1 ? 1 : -1
//     dy = -abs(y1 - y0)
//     sy = y0 < y1 ? 1 : -1
//     error = dx + dy

//     while true
//         plot(x0, y0)
//         e2 = 2 * error
//         if e2 >= dy
//             if x0 == x1 break
//             error = error + dy
//             x0 = x0 + sx
//         end if
//         if e2 <= dx
//             if y0 == y1 break
//             error = error + dx
//             y0 = y0 + sy
//         end if
//     end while

bress_line :: struct {
	x0, y0, x1, y1: i16,
	cx, cy:         i16,
	dx, dy:         i16,
	sx, sy:         i16,
	err:            i16,
}

bress_line_init :: proc(x0: i16, y0: i16, x1: i16, y1: i16) -> bress_line {
	dx := abs(x1 - x0)
	dy := -abs(y1 - y0)
	return bress_line {
		x0 = x0,
		x1 = x1,
		y0 = y0,
		y1 = y1,
		dx = dx,
		sx = x0 < x1 ? 1 : -1,
		dy = dy,
		sy = y0 < y1 ? 1 : -1,
		err = dx + dy,
		cx = x0,
		cy = y0,
	}
}

bress_line_next :: proc(l: ^bress_line) -> bool {
	errorx2 := 2 * l.err
	if errorx2 >= l.dy {
		if l.cx == l.x1 {return false}
		l.err += l.dy
		l.cx += l.sx
	}
	if errorx2 <= l.dx {
		if l.cy == l.y1 {return false}
		l.err += l.dx
		l.cy += l.sy
	}

	return true
}

bress_line_next_until_y :: proc(l: ^bress_line, ty: i16) {
	for l.cy != ty && bress_line_next(l) {

	}
}

bress_line_next_until_x :: proc(l: ^bress_line, tx: i16) {
	for l.cx != tx && bress_line_next(l) {

	}
}

bress_line_draw :: proc(line: ^bress_line, color: vec4) {
	l := line^
	loop: for {
		draw_screen_pixel({f32(l.cx), f32(l.cy), 0, 0}, color)
		if !bress_line_next(&l) {return}
	}
}

draw_screen_line_bress :: proc(x0: i16, y0: i16, x1: i16, y1: i16, color: vec4) {
	deltax := abs(x1 - x0)
	stepx: i16 = x0 < x1 ? 1 : -1
	deltay := -abs(y1 - y0)
	stepy: i16 = y0 < y1 ? 1 : -1
	error := deltax + deltay

	x := x0
	y := y0

	loop: for {
		draw_screen_pixel({f32(x), f32(y), 0, 0}, color)
		errorx2 := 2 * error
		if errorx2 >= deltay {
			if x == x1 {break loop}
			error += deltay
			x += stepx
		}
		if errorx2 <= deltax {
			if y == y1 {break loop}
			error += deltax
			y += stepy
		}
	}
}

draw_screen_line :: proc(ps: vec4, pe: vec4, color: vec4) {
	start := ps
	end := pe

	if ps.y > pe.y {
		start = pe
		end = ps
	}

	invslope := (end.x - start.x) / max(1.0, end.y - start.y)


	swidth := f32(renderer.width)
	sheight := f32(renderer.height)


	clipY := start.y

	offsetY: f32 = clipY < 0 ? f32(-clipY) : 0

	curx := start.x + f32(offsetY) * invslope

	minx := max(0, min(start.x, end.x))
	maxx := min(swidth, max(start.x, end.x))


	for y in max(0, clipY) ..= min(sheight - 1, end.y) {
		x := int(clamp(curx, minx, maxx))
		draw_screen_pixel({f32(x), f32(y), 0, 0}, color)
		curx = curx + invslope
	}
}

clipTri :: proc(cmd: TriRenderCmd) -> bool {
	tracy.Zone()

	if !renderer.clipping || cmd.clipCount > 0 {
		return true
	}

	tri := cmd

	clipped := tri.vertCamera

	insideCount := 0
	outsideIndex := 2
	insideIndex := [3]int{-1, -1, -1}
	insideDir := [3]f32{0.0, 0.0, 0.0}

	nearZ := -renderer.nearZ

	#unroll for v in 0 ..< 3 {
		inside := clipped[v].z < nearZ

		if inside {
			insideIndex[insideCount] = v
			insideCount += 1
		} else {
			insideIndex[outsideIndex] = v
			outsideIndex -= 1
		}

		insideDir[v] = cast(f32)cast(int)inside
	}

	switch insideCount {
	case 0:
		return false

	case 1:
		// one inside, two out, only need to make one
		p := clipped[insideIndex[0]]
		o1 := intersectClipEdge(nearZ, clipped[insideIndex[1]], p)
		o2 := intersectClipEdge(nearZ, clipped[insideIndex[2]], p)

		pb := math_barycentric_coords_edge_ba(tri.vertCamera, tri.edges, p) / tri.inv_area
		o1b := math_barycentric_coords_edge_ba(tri.vertCamera, tri.edges, o1.v) / tri.inv_area
		o2b := math_barycentric_coords_edge_ba(tri.vertCamera, tri.edges, o2.v) / tri.inv_area

		tri.clipCount += 1
		addClippedTri(tri, {o2.v, o1.v, p}, {o2b, o1b, pb})
		return false

	case 2:
		// two inside one out, need to make 2 news
		ip := clipped[insideIndex[0]]
		ip2 := clipped[insideIndex[1]]
		o1 := intersectClipEdge(nearZ, clipped[insideIndex[2]], ip)
		o2 := intersectClipEdge(nearZ, clipped[insideIndex[2]], ip2)

		ipb := math_barycentric_coords_edge_ba(tri.vertCamera, tri.edges, ip) / tri.inv_area
		ip2b := math_barycentric_coords_edge_ba(tri.vertCamera, tri.edges, ip2)/ tri.inv_area
		o1b := math_barycentric_coords_edge_ba(tri.vertCamera,  tri.edges, o1.v)/ tri.inv_area
		o2b := math_barycentric_coords_edge_ba(tri.vertCamera,  tri.edges, o2.v)/ tri.inv_area

		tri.clipCount += 1
		addClippedTri(tri, {ip, o2.v, ip2}, {ipb, o2b, ip2b})

		tri.clipCount += 1
		addClippedTri(tri, {ip, o1.v, o2.v}, {ipb, o1b, o2b})
		return false
	case 3:
		return true

	case:
		return false
	}

	return true
}

render_debug_ui :: proc(dt: f32, window: bool = true) {

	// if window {
	// 	ui.window(ctx, "Renderer", {renderer.width + 20, 20, 300, 450}, {.NO_CLOSE})
	// }

	// if .ACTIVE in ui.header(ctx, "Info") {
	// 	win := ui.get_current_container(ctx)
	// 	ui.layout_row(ctx, {54, -1}, 0)
	// 	ui.label(ctx, "Size:")
	// 	ui.label(ctx, fmt.tprintf("%dx%d", renderer.width, renderer.height))
	// }

	// if .ACTIVE in ui.header(ctx, "Window Options") {
	// 	ui.layout_row(ctx, {120, 120, 120}, 0)
	// 	for opt in ui.Opt {
	// 		state := opt in opts
	// 		if .CHANGE in ui.checkbox(ctx, fmt.tprintf("%v", opt), &state) {
	// 			if state {
	// 				opts += {opt}
	// 			} else {
	// 				opts -= {opt}
	// 			}
	// 		}
	// 	}
	// }

	// if .ACTIVE in ui.header(ctx, "Test Buttons", {.EXPANDED}) {
	// 	ui.layout_row(ctx, {86, -110, -1})
	// 	ui.label(ctx, "Test buttons 1:")
	// 	if .SUBMIT in ui.button(ctx, "Button 1") {write_log("Pressed button 1")}
	// 	if .SUBMIT in ui.button(ctx, "Button 2") {write_log("Pressed button 2")}
	// 	ui.label(ctx, "Test buttons 2:")
	// 	if .SUBMIT in ui.button(ctx, "Button 3") {write_log("Pressed button 3")}
	// 	if .SUBMIT in ui.button(ctx, "Button 4") {write_log("Pressed button 4")}
	// }

	// if .ACTIVE in ui.header(ctx, "Commands", {.EXPANDED}) {
	// 	ui.checkbox(ctx, "Depth Test", &renderer.depthTest)
	// 	ui.checkbox(ctx, "Backface", &renderer.backfaceCull)
	// 	ui.layout_row(ctx, {140, -1})
	// ui.layout_begin_column(ctx)

	// for cmd in renderer.commands {
	// 	if .ACTIVE in ui.treenode(ctx, fmt.tprintf("{}", cmd.id), {.EXPANDED}) {
	// 		ui.layout_row(ctx, {70, -1}, 0)
	// 		ui.label(ctx, "Step:")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.step))

	// 		ui.label(ctx, "p:")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_final))

	// 		ui.label(ctx, "Area:")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.area))

	// 		ui.label(ctx, "Min:")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.min))
	// 		ui.label(ctx, "Max:")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.max))

	// 		ui.label(ctx, "pix bary")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_bary))

	// 		ui.label(ctx, "pix outside")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_outside))

	// 		ui.label(ctx, "calc bary")
	// 		ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_bary_calc))
	// 	}
	// }

	// }
}
