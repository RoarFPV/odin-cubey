package cubey

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import "core:strings"

Renderer :: struct {
	width:         i32,
	height:        i32,
	screenTexture: rl.RenderTexture2D,
	depthBuffer:   [dynamic]f32,
	depthFipped:   bool,
	depthTest:     bool,
	backfaceCull:  bool,
	commands:      [dynamic]TriRenderCmd,
}

Transform :: struct {
	mvp:   mat44,
	// position: vec4,
	// rotation: quaternion128,
	model: ^mat44,
	view:  ^mat44,
	proj:  ^mat44,
}

Mesh :: struct {
	name:      string,
	verticies: [dynamic]vec3,
	colors:    [dynamic]vec3,
	normals:   [dynamic]vec3,
	uvs:       [dynamic]vec3,
	indicies:  [dynamic]u16,
}

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
	min:               vec3,
	max:               vec3,
	pixel_final:       vec3,
	pixel_bary_norm:   vec3,
	pixel_bary_calc:   vec3,
	pixel_bary_c:      vec3,
	pixel_bary:        vec3,
	pixel_color:       rl.Color,
	pixel_outside:     bool,
	pixel_was_outside: bool,
	pixel_step:        vec3,
	step:              TriRenderState,
}

TriRenderCmd :: struct {
	id:         u32,
	mesh:       ^Mesh,
	transform:  Transform,
	verticies:  [3]vec3,
	vertClip:   [3]vec4,
	vertCamera: [3]vec3,
	vertScreen: [3]vec3,
	vertWorld:  [3]vec3,
	indicies:   [3]u16,
	colors:     [3]vec3,
	uvs:        [3]vec3,
	area:       f32,
	inv_area:   f32,
	// st:         TriRenderStateData,
	bary:       BaryData,
	edges:      [3]vec3,
	normal:     vec3,
	material:   Material,
}


render_test_depth :: proc "contextless" (p: vec3, write: bool, less: bool) -> (res: bool) {
	idx := i32(p.y) * renderer.width + i32(p.x)
	if idx < 0 || idx >= auto_cast len(renderer.depthBuffer) {
		return false
	}
	d := renderer.depthBuffer[idx]
	res = (p.z < d) if less else (p.z > d)
	if res && write {
		renderer.depthBuffer[idx] = p.z
	}

	return
}

mesh_triangle_count :: proc(mesh: ^Mesh) -> u32 {
	return auto_cast len(mesh.indicies) / 3
}

renderer := Renderer {
	width  = 170,
	height = 100,
}

renderer_init :: proc(width, height: i32) {
	renderer.width = width
	renderer.height = height
	renderer.depthTest = true
	renderer.depthFipped = true
	renderer.backfaceCull = true
	renderer.depthBuffer = make_dynamic_array_len([dynamic]f32, width * height)
}

mesh_render :: proc(
	mesh: ^Mesh,
	material: Material,
	model: ^mat44,
	view: ^mat44,
	proj: ^mat44,
	draw: bool = true,
) {
	triCount := int(mesh_triangle_count(mesh))
	// reserve(&render_commands, triCount)
	mv := view^ * model^
	mvp := proj^ * mv

	cmd := TriRenderCmd {
		mesh      = mesh,
		transform = {mvp, model, view, proj},
		material  = material,
	}

	vp := vec3{auto_cast renderer.width, auto_cast renderer.height, 2} / 2.0

	for t in 0 ..< triCount {
		for i in 0 ..< 3 {
			cmd.indicies[i] = mesh.indicies[t * 3 + i]
			vmv := mesh.verticies[cmd.indicies[i]]
			cmd.vertClip[i] = {vmv.x, vmv.y, vmv.z, 1}

			cmd.vertWorld[i] = (model^ * cmd.vertClip[i]).xyz
			cmd.vertCamera[i] = (mv * cmd.vertClip[i]).xyz
			// TODO: clip vertCamera verticies
			cmd.vertClip[i] = mvp * cmd.vertClip[i]

			cmd.colors[i] = mesh.colors[cmd.indicies[i]]
			

			w := cmd.vertClip[i].w
			
			cmd.uvs[i] = mesh.uvs[cmd.indicies[i]] / w
			cmd.uvs[i].z = 1 / w

			cmd.vertScreen[i] = cmd.vertClip[i].xyz
			cmd.vertScreen[i] /= w

			cmd.vertScreen[i] = viewport_scale(vp, cmd.vertScreen[i])
		}
		cmd.area = math_tri_edge(cmd.vertScreen[0], cmd.vertScreen[1], cmd.vertScreen[2])
		cmd.inv_area = 1 / cmd.area

		cmd.bary = math_bary_data(cmd.vertScreen)
		cmd.edges = {
			cmd.vertScreen[2] - cmd.vertScreen[1],
			cmd.vertScreen[0] - cmd.vertScreen[2],
			cmd.vertScreen[1] - cmd.vertScreen[0],
		}


		// if linalg.abs(cmd.area) <= 0.0 {
		// 	continue
		// }

		cmd.normal = math_tri_normal(cmd.vertWorld)
		normal := math_tri_normal(cmd.vertCamera)
		if renderer.backfaceCull && linalg.dot(cmd.vertCamera[0], normal) <= 0 {
			continue
		}
		// assert(cmd.area != 0.0)
		if draw {
			// tri_render(cmd)
			tri_render_scanline(cmd)
		}

		cmd.id = auto_cast len(renderer.commands)
		append(&renderer.commands, cmd)
	}
}

@(require_results)
viewport_scale :: proc "contextless" (halfViewport: vec3, v: vec3) -> vec3 {
	half := halfViewport
	vv := (half * (v * {1, -1, 1})) + (half * {1, 1, 0})
	// vr := vec3{half.x * v.x + half.x, half.y * -v.y + half.y, v.z}
	return vv
}


tri_render_scanline :: proc(cmd: TriRenderCmd) {
	sv := cmd.vertScreen // {1, 1, 0}

	slice.sort_by(sv[:], proc(a, b: vec3) -> bool {
		return a.y < b.y
	})


	if sv[0].y == sv[1].y {
		// flat top
		tri_render_flat_top(cmd, sv)
	} else if sv[1].y == sv[2].y {
		// flat bottom
		tri_render_flat_bottom(cmd, sv)
	} else {
		v4 := vec3 {
			sv[0].x + ((sv[1].y - sv[0].y) / (sv[2].y - sv[0].y)) * (sv[2].x - sv[0].x),
			sv[1].y,
			0,
		}
		tri_render_flat_bottom(cmd, {sv[0], sv[1], v4})
		tri_render_flat_top(cmd, {sv[1], v4, sv[2]})
	}

	// rl.DrawLineV({sv[0].x, sv[0].y}, {sv[1].x, sv[1].y}, color(3))
	// rl.DrawLineV({sv[0].x, sv[0].y}, {sv[2].x, sv[2].y}, color(4))
	// rl.DrawLineV({sv[2].x, sv[2].y}, {sv[1].x, sv[1].y}, color(5))
}

tri_render_flat_bottom :: proc(cmd: TriRenderCmd, v: [3]vec3) {
	invslope1 := (v[1].x - v[0].x) / (v[1].y - v[0].y)
	invslope2 := (v[2].x - v[0].x) / (v[2].y - v[0].y)

	curx1 := v[0].x
	curx2 := v[0].x

	for y in int(v[0].y) - 1 ..= int(v[1].y) + 1 {
		//   drawLine(curx1, scanlineY, (int)curx2, scanlineY);
		tri_render_single_line(cmd, int(curx1), int(curx2), int(y))
		curx1 += invslope1
		curx2 += invslope2
	}
}

tri_render_flat_top :: proc(cmd: TriRenderCmd, v: [3]vec3) {

	invslope1 := (v[2].x - v[0].x) / (v[2].y - v[0].y)
	invslope2 := (v[2].x - v[1].x) / (v[2].y - v[1].y)

	curx1 := v[2].x
	curx2 := v[2].x

	for y := int(v[2].y) + 1; y >= int(v[0].y) - 1; y -= 1 {
		//   drawLine(curx1, scanlineY, curx2, scanlineY);
		tri_render_single_line(cmd, int(curx1), int(curx2), int(y))
		curx1 -= invslope1
		curx2 -= invslope2
	}

}

light_dir := linalg.normalize(vec3{0, -0.25, 0})
light_intensity: f32 = 2

tri_render_single_line :: proc(cmd: TriRenderCmd, x1: int, x2: int, y: int) {
	sv := cmd.vertScreen

	xs := math.min(x1, x2)
	xf := math.max(x1, x2)

	for x in xs - 1 ..= xf + 1 {
		p := vec3{f32(x) + 0.5, f32(y) + 0.5, 0}

		pBary := math_barycentric_coords_edge_ba(sv, cmd.edges, p)
		pBary *= cmd.inv_area

		if linalg.min(pBary) < 0 || linalg.max(pBary) > 1 {
			continue
		}

		p.z = pBary.x * sv[0].z + pBary.y * sv[1].z + pBary.z * sv[2].z

		if renderer.depthTest && !render_test_depth(p, true, renderer.depthFipped) {
			continue
		}


		cBary := math_bary_interp(pBary, cmd.colors)
		uv := math_bary_interp(pBary, cmd.uvs)
		cTex := mat_sample_texture(cmd.material, uv.xy / uv.z)
		cTex *=
			cmd.material.ambient + math.max(linalg.dot(cmd.normal, light_dir), 0) * light_intensity

		c := linalg.saturate(cTex) * {255, 255, 255, 255}
		rl.DrawPixelV({p.x, p.y}, {u8(c.r), u8(c.g), u8(c.b), 255})
	}
}

mat_sample_texture :: proc(mat: Material, at: vec2) -> vec4 {
	w: f32 = auto_cast mat.texture.width - 1
	h: f32 = auto_cast mat.texture.height - 1
	color := rl.GetImageColor(mat.texture, i32(w * at.x), i32(h * at.y))
	return vec4 {
		f32(color.x) / 255.0,
		f32(color.y) / 255.0,
		f32(color.z) / 255.0,
		f32(color.w) / 255.0,
	}
}

render_begin :: proc() {
	clear(&renderer.commands)
	// renderer.depthFipped = !renderer.depthFipped
	slice.fill(renderer.depthBuffer[:], 0.0)
}

render_end :: proc() {

}

render_debug_ui :: proc(dt: f32, window: bool = true) {
	ctx := &state.mu_ctx

	if window {
		ui.window(ctx, "Renderer", {renderer.width + 20, 20, 300, 450}, {.NO_CLOSE})
	}

	if .ACTIVE in ui.header(ctx, "Info") {
		win := ui.get_current_container(ctx)
		ui.layout_row(ctx, {54, -1}, 0)
		ui.label(ctx, "Size:")
		ui.label(ctx, fmt.tprintf("%dx%d", renderer.width, renderer.height))
	}

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

	if .ACTIVE in ui.header(ctx, "Commands", {.EXPANDED}) {
		ui.checkbox(ctx, "Depth Test", &renderer.depthTest)
		ui.checkbox(ctx, "Backface", &renderer.backfaceCull)
		ui.layout_row(ctx, {140, -1})
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

	}
}
