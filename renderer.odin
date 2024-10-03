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
	indicies:  [dynamic]u16,
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
	vertScreen: [3]vec3,
	indicies:   [3]u16,
	colors:     [3]vec3,
	area:       f32,
	inv_area:   f32,
	st:         TriRenderStateData,
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
	renderer.width       = width
	renderer.height      = height
	renderer.depthTest   = false
	renderer.depthFipped = true
	renderer.depthBuffer = make_dynamic_array_len([dynamic]f32, width * height)
}

mesh_render :: proc(mesh: ^Mesh, model: ^mat44, view: ^mat44, proj: ^mat44, draw: bool = true) {
	triCount := int(mesh_triangle_count(mesh))
	// reserve(&render_commands, triCount)
	mv := view^ * model^
	mvp := proj^ * mv

	cmd := TriRenderCmd {
		mesh      = mesh,
		transform = {mvp, model, view, proj},
	}

	vp := vec3{auto_cast renderer.width, auto_cast renderer.height, 0} / 2.0

	for t in 0 ..< triCount {
		for i in 0 ..< 3 {
			cmd.indicies[i] = mesh.indicies[t * 3 + i]
			mv := mesh.verticies[cmd.indicies[i]]
			cmd.vertClip[i] = {mv.x, mv.y, mv.z, 1}

			cmd.vertClip[i] = mvp * cmd.vertClip[i]
			cmd.colors[i] = mesh.colors[cmd.indicies[i]]

			w := cmd.vertClip[i].w
			cmd.vertScreen[i] = cmd.vertClip[i].xyz
			cmd.vertScreen[i] /= w
			// cmd.colors[i] /= w

			cmd.vertScreen[i] = viewport_scale(vp, cmd.vertScreen[i])
		}
		cmd.area = math_tri_edge(cmd.vertScreen[0], cmd.vertScreen[1], cmd.vertScreen[2])
		cmd.inv_area = 1 / cmd.area
		// if linalg.abs(cmd.area) <= 0.0 {
		// 	continue
		// }
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

	o := v
	o.x = half.x * v.x + half.x
	o.y = half.y * -v.y + half.y

	return o
}

tri_render_stepped :: proc(cmd: ^TriRenderCmd) {
	sv := cmd.vertScreen
	st := &cmd.st
	p := &st.pixel_final


	switch cmd.st.step {
	case .Bounds:
		st.min = sv[0]
		st.max = sv[0]
		for v in 1 ..< 3 {
			st.max = linalg.max(st.max, sv[v])
			st.min = linalg.min(st.min, sv[v])
		}
		st.pixel_final = st.min
		st.step = .Bary

		// rl.DrawRectangleLinesEx(
		// 	{st.min.x, st.min.y, st.max.x - st.min.x, st.max.y - st.min.y},
		// 	1,
		// 	rl.RED,
		// )

		rl.DrawLineV(sv[0].xy, sv[1].xy, rl.RED)
		rl.DrawLineV(sv[0].xy, sv[2].xy, rl.BLUE)
	// rl.DrawLineV(sv[0].xy, st.pixel_final.xy, rl.GREEN)

	case .Bary:
		st.step = .Pixel


	case .Pixel:
		rl.DrawPixelV(st.pixel_final.xy, color(3))

		st.pixel_bary = math_barycentric_coords_edge(sv, st.pixel_final)
		st.pixel_bary_calc = math_barycentric_coords(sv, st.pixel_final)
		// st.pixel_final = math_point_from_bary(st.bary, st.pixel_bary)


		st.pixel_outside =
			st.pixel_bary_calc.x < 0 || st.pixel_bary_calc.y < 0 || st.pixel_bary_calc.z < 0

		if !st.pixel_outside {
			st.pixel_bary /= cmd.area

			c := math_bary_interp(st.pixel_bary, cmd.colors)
			// st.pixel_color = color(6)
			st.pixel_color = rl.ColorFromNormalized({c.x, c.y, c.z, 1})
			st.pixel_color.a = st.pixel_outside ? 10 : 255
			rl.DrawPixelV(st.pixel_final.xy, st.pixel_color)
		}
		st.step = .NextPixel

	case .NextPixel:
		p.x += 1
		// next x
		st.step = .Pixel
		done :=
			(st.pixel_was_outside != st.pixel_outside && !st.pixel_was_outside) || p.x >= st.max.x

		st.pixel_was_outside = st.pixel_outside

		if done {
			p.x = st.min.x

			st.pixel_was_outside = true
			st.pixel_outside = false
			if p.y >= st.max.y {
				st.step = .Complete
			}

			p.y += 1
		}

	case .Complete:
		return
	}
}

tri_render :: proc(cmd: TriRenderCmd) {
	sv := cmd.vertScreen

	min := sv[0]
	max := sv[0]
	for v in 1 ..< 3 {
		max = linalg.max(max, sv[v])
		min = linalg.min(min, sv[v])
	}


	for y in min.y ..< max.y {

		outside := true
		for x in min.x ..< max.x {

			p := vec3{x, y, 0}

			pBary := math_barycentric_coords_edge(sv, p)

			is_outside := (pBary.x < 0 || pBary.y < 0 || pBary.z < 0)
			if is_outside {

				if !outside {
					break
				}

				// continue
			}

			outside = is_outside

			pBary *= cmd.inv_area

			p = vec3{x, y, pBary.x * sv[0].z + pBary.y * sv[1].z + pBary.z * sv[2].z}

			cBary := math_bary_interp(pBary, cmd.colors)


			c := rl.ColorFromNormalized({cBary.r, cBary.g, cBary.b, 1})
			c.a = outside ? 127 : 255
			rl.DrawPixelV({p.x, p.y}, c)
		}
	}

	// rl.DrawLineV({sv[0].x, sv[0].y}, {sv[1].x, sv[1].y}, color(3))
	// rl.DrawLineV({sv[0].x, sv[0].y}, {sv[2].x, sv[2].y}, color(4))
	// rl.DrawLineV({sv[2].x, sv[2].y}, {sv[1].x, sv[1].y}, color(5))
}


tri_render_scanline :: proc(cmd: TriRenderCmd) {
	sv := cmd.vertScreen - {0.5, 0.5, 0}

	slice.sort_by(sv[:3], proc(a, b: vec3) -> bool {
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

	for y in v[0].y ..= v[1].y {
		//   drawLine(curx1, scanlineY, (int)curx2, scanlineY);
		tri_render_single_line(cmd, curx1, curx2, y)
		curx1 += invslope1
		curx2 += invslope2
	}
}

tri_render_flat_top :: proc(cmd: TriRenderCmd, v: [3]vec3) {

	invslope1 := (v[2].x - v[0].x) / (v[2].y - v[0].y)
	invslope2 := (v[2].x - v[1].x) / (v[2].y - v[1].y)

	curx1 := v[2].x
	curx2 := v[2].x

	for y := v[2].y; y >= v[0].y; y -= 1 {
		//   drawLine(curx1, scanlineY, curx2, scanlineY);
		tri_render_single_line(cmd, curx1, curx2, y)
		curx1 -= invslope1
		curx2 -= invslope2
	}

}

tri_render_single_line :: proc(cmd: TriRenderCmd, x1: f32, x2: f32, y: f32) {
	sv := cmd.vertScreen

	xs := math.min(x1, x2)
	xf := math.max(x1, x2)

	for x in xs ..< xf {
		p := vec3{x, y, 0}

		pBary := math_barycentric_coords_edge(sv, p)
		pBary *= cmd.inv_area

		p = vec3{x, y, pBary.x * sv[0].z + pBary.y * sv[1].z + pBary.z * sv[2].z}

		if renderer.depthTest && !render_test_depth(p, true, renderer.depthFipped) {
			continue
		}
		// d := renderer.depthBuffer[x, y]
		cBary := math_bary_interp(pBary, cmd.colors)
		c := rl.ColorFromNormalized({cBary.r, cBary.g, cBary.b, 1})
		rl.DrawPixelV({p.x, p.y}, c)
	}
}

render_begin :: proc() {
	clear(&renderer.commands)
	renderer.depthFipped = !renderer.depthFipped
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

		ui.layout_row(ctx, {50, 50, -1}, 0)


		cmds := &renderer.commands
		btn_text := len(cmds) > 0 ? "Step" : "Running"
		step_res := ui.button(ctx, btn_text)
		btn_id := ui.get_id(ctx, btn_text)

		if .SUBMIT in step_res ||
		   (ctx.hover_id == btn_id && rl.IsMouseButtonDown(.LEFT) && rl.IsKeyDown(.LEFT_CONTROL)) {
			if len(cmds) > 0 {
				rl.BeginTextureMode(renderer.screenTexture)
				defer rl.EndTextureMode()
				tri_render_stepped(&cmds[0])
			}
		}
		ui.label(ctx, "res:")
		ui.label(ctx, fmt.tprintf("{}}", step_res))
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
		ui.checkbox(ctx, "Depth Test", &renderer.depthTest )
		ui.layout_row(ctx, {140, -1})
		// ui.layout_begin_column(ctx)

		for cmd in renderer.commands {
			if .ACTIVE in ui.treenode(ctx, fmt.tprintf("{}", cmd.id), {.EXPANDED}) {
				ui.layout_row(ctx, {70, -1}, 0)
				ui.label(ctx, "Step:")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.step))

				ui.label(ctx, "p:")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_final))

				ui.label(ctx, "Area:")
				ui.label(ctx, fmt.tprintf("{}", cmd.area))

				ui.label(ctx, "Min:")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.min))
				ui.label(ctx, "Max:")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.max))

				ui.label(ctx, "pix bary")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_bary))

				ui.label(ctx, "pix outside")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_outside))

				ui.label(ctx, "calc bary")
				ui.label(ctx, fmt.tprintf("{}", cmd.st.pixel_bary_calc))
			}
		}

	}
}
