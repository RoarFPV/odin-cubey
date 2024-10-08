package cubey


import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:strings"

GameState :: enum {
	Reset,
	MainMenu,
	Load,
	Play,
	GameOver,
}

Entity :: struct {
	id:     u32,
	radius: f32,
	color:  byte,
	pos:    [2]f32,
	rot:    f32,
	alpha:  byte,
}


vanilia_milkshake :: [?][4]byte {
	{0x28, 0x28, 0x2e, 255}, // 0
	{0x6c, 0x56, 0x71, 255}, // 1
	{0xd9, 0xc8, 0xbf, 255}, // 2
	{0xf9, 0x82, 0x84, 255}, // 3
	{0xb0, 0xa9, 0xe4, 255}, // 4
	{0xac, 0xcc, 0xe4, 255}, // 5
	{0xb3, 0xe3, 0xda, 255}, // 6
	{0xfe, 0xaa, 0xe4, 255}, // 7
	{0x87, 0xa8, 0x89, 255}, // 8
	{0xb0, 0xeb, 0x93, 255}, // 9
	{0xe9, 0xf5, 0x9d, 255}, // 10
	{0xff, 0xe6, 0xc6, 255}, // 11
	{0xde, 0xa3, 0x8b, 255}, // 12
	{0xff, 0xc3, 0x84, 255}, // 13
	{0xff, 0xf7, 0xa0, 255}, // 14
	{0xff, 0xf7, 0xe4, 255}, // 15
}

palette := vanilia_milkshake

color :: proc(index: byte) -> rl.Color {
	return rl.Color(palette[index < len(palette) ? index : len(palette) - 1])
}

// Game
score: u64 = 0
game_state: GameState = .Reset

width :: 1280
height :: 768

fov :: 70.0
near :: 1
far :: 1000

unit_scale :: 70.0
inv_unit_scale :: 1.0 / unit_scale
play_area :: [2]f32{11, 15}

scaled_width :: width * inv_unit_scale
scaled_height :: height * inv_unit_scale


activeMesh: ^Mesh = &mesh_triangle

// Entities
EntityMap :: map[u32]Entity

entities_dynamic := EntityMap{}
entities_static := EntityMap{}

nextEntityId: u32 = 1


// Input
leftDown := false

// Physics
gravity :: [3]f32{0, -9.81, 0}
restitution :: 0.1

vec2 :: linalg.Vector2f32
vec3 :: linalg.Vector3f32
vec4 :: linalg.Vector4f32
mat44 :: linalg.Matrix4x4f32

remove_entity_from_map :: proc(entities: ^EntityMap, id: u32) {
	e, found := entities[id]
	if !found {return}

	remove_entity(&e)

	delete_key(entities, id)
}

remove_entity :: proc(e: ^Entity) {
}

view_pos := vec3{0, -0.5, -3}
rotation := false
game_update_input :: proc(dt: f32) {
	if paused {
		return
	}
	speed: f32 = 2.0
	view_pos.x += ((rl.IsKeyDown(.D) ? 1.0 : 0.0) - (rl.IsKeyDown(.A) ? 1.0 : 0.0)) * -speed * dt
	view_pos.z += ((rl.IsKeyDown(.W) ? 1.0 : 0.0) - (rl.IsKeyDown(.S) ? 1.0 : 0.0)) * speed * dt
	view_pos.y +=
		((rl.IsKeyDown(.LEFT_CONTROL) ? 1.0 : 0.0) - (rl.IsKeyDown(.LEFT_SHIFT) ? 1.0 : 0.0)) *
		speed *
		dt

	if rotation {
		model_mat *= linalg.matrix4_rotate_f32(1 * dt, {1, 1, 1})
	}
}

camera := rl.Camera2D {
	target = {scaled_width / -2, 0},
	zoom   = unit_scale,
}

game_update_state :: proc(dt: f32) {
	switch game_state {

	case .Reset:
		for id, &entity in entities_dynamic {
			remove_entity(&entity)
		}

		for id, &entity in entities_static {
			remove_entity(&entity)
		}


		clear_map(&entities_dynamic)
		clear_map(&entities_static)

		game_state = .Load

	case .Load:
		game_init()
		ui_init({width, height})
		game_state = .Play

	case .MainMenu:
		ui_update()
		game_render()
		menu_update()
		ui_update_end()
		ui_render()

	case .Play:
		ui_update()
		game_update_input(dt)
		game_debug_ui(dt)
		ui_update_end()
		game_render()
		ui_render()

	case .GameOver:
		ui_update()
		game_render()
		game_render_score()
		ui_update_end()

		ui_render()

	}
}

menu_update :: proc() {
	// rl.DrawText("Play", rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2, 30, color(12))

	if rl.GuiButton({width / 2 - 50, height / 2 - 25, 100, 50}, "PLAY") ||
	   rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		game_state = .Reset
	}
}

proj := linalg.matrix4_perspective_f32(fov, f32(renderer.width) / f32(renderer.height), 10, far)

model_mat := mat44(1)
// proj := mat44(1)
// proj := linalg.matrix_ortho3d_f32(0,width,0, height, near, far)
paused := false

game_render :: proc() {
	v := linalg.matrix4_translate_f32(view_pos.xyz)

	if !paused {
		rl.BeginTextureMode(renderer.screenTexture)
		defer rl.EndTextureMode()
		rl.ClearBackground(color(0))
		render_begin()
		defer render_end()

		// if len(renderer.commands) == 0 {
			mesh_render(activeMesh, &model_mat, &v, &proj, true)
		// } else {
		// 	if renderer.commands[0].st.step == .Complete {
		// 		ordered_remove(&renderer.commands, 0)
		// 	}
		// }
	}

	{

		rl.DrawTexturePro(
			texture = renderer.screenTexture.texture,
			source = {0, 0, f32(renderer.width), -f32(renderer.height)},
			dest = {0, 0, width, height},
			origin = {0, 0},
			rotation = 0,
			tint = rl.WHITE,
		)
	}
}

game_render_score :: proc() {
	rl.DrawText(rl.TextFormat("Score: {}", score), 100, 10, 30, color(0))
	rl.DrawLineEx({-play_area.x, 1}, {play_area.x, 1}, 0.2, color(0))
}

game_init :: proc() {
	renderer_init(640,400)
	renderer.screenTexture = rl.LoadRenderTexture(renderer.width, renderer.height)
}


game_check_end :: proc() {

}

game_debug_ui :: proc(dt: f32, window: bool = true) {
	ctx := &state.mu_ctx
	if window {
		if !ui.begin_window(ctx, "Game", {20, 20, 300, 450}, {.NO_CLOSE}) {
			return
		}
	}

	if .ACTIVE in ui.header(ctx, "Meshes", {.EXPANDED}) {
		ui.layout_row(ctx, {100, 100}, 0)
		if .SUBMIT in ui.button(ctx, "triangle") {
			activeMesh = &mesh_triangle
		} else if .SUBMIT in ui.button(ctx, "cube") {
			activeMesh = &mesh_cube
		}

		if .SUBMIT in ui.button(ctx, "rotation") {
			rotation = !rotation
		}
	}


	if .ACTIVE in ui.header(ctx, "Renderer", {.EXPANDED}) {

		if .SUBMIT in ui.button(ctx, paused ? "Play" : "Pause") {
			if !paused {
				rl.BeginTextureMode(renderer.screenTexture)
				defer rl.EndTextureMode()
				rl.ClearBackground(color(0))
			}
			paused = !paused
		}

		render_debug_ui(dt, false)
	}


	if window {
		ui.end_window(ctx)
	}
}
