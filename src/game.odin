package cubey


import rl "vendor:raylib"


import "core:c"
import "core:strings"
import "core:fmt"
import "core:math/linalg"
import "core:path/filepath"
import "core:reflect"
import mu "vendor:microui"


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

// 222831

// 393E46

palette := vanilia_milkshake


color :: proc(index: byte) -> rl.Color {
	return rl.Color(palette[index < len(palette) ? index : len(palette) - 1])
}

// Game
score: u64 = 0
game_state: GameState = .Reset

width :: 1280
height :: 768

fov :: 60.0
near :: 0.1
far :: 10000

unit_scale :: 70.0
inv_unit_scale :: 1.0 / unit_scale
play_area :: [2]f32{11, 15}

scaled_width :: width * inv_unit_scale
scaled_height :: height * inv_unit_scale


activeMesh: ^Model
material: Material

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

COL_BG :: mu.Color{15, 17, 26, 255}
COL_PANEL :: mu.Color{20, 24, 36, 255}
COL_BORDER :: mu.Color{47, 54, 73, 255}
COL_HL :: mu.Color{0, 173, 181, 255}
COL_TXT :: mu.Color{255, 255, 255, 255}
COL_TXT_LOW :: mu.Color{131, 148, 173, 255}

GameInputMode :: enum {
	UI_MODE,
	CAMERA_MODE,
}


ui_mode : GameInputMode = .UI_MODE

found : [dynamic]string


remove_entity_from_map :: proc(entities: ^EntityMap, id: u32) {
	e, found := entities[id]
	if !found {return}

	remove_entity(&e)

	delete_key(entities, id)
}

remove_entity :: proc(e: ^Entity) {
}

view_pos := vec3{0, -0.5, -3}
view_rot_yaw := mat44(1)
view_rot_pitch := mat44(1)
rotation := true

game_update_input :: proc(dt: f32) {
	if paused {
		return
	}
	speed: f32 = 1 * (rl.IsKeyDown(.LEFT_SHIFT) ? 100 : 1)

	ui_mode : GameInputMode = .CAMERA_MODE if rl.IsMouseButtonDown(.RIGHT) else .UI_MODE
	
	mouse_delta := (ui_mouse_position_delta() * 0.1) if ui_mode == .CAMERA_MODE else vec2{0,0}

	yawInput := f32(cast(int)rl.IsKeyDown(.RIGHT) - cast(int)rl.IsKeyDown(.LEFT)) + mouse_delta.x
	rollInput := f32(cast(int)rl.IsKeyDown(.Q) - cast(int)rl.IsKeyDown(.E)) 
	pitchInput := f32(cast(int)rl.IsKeyDown(.DOWN) - cast(int)rl.IsKeyDown(.UP)) + mouse_delta.y
	
	if yawInput != 0 || rollInput != 0 || pitchInput != 0 {
		view_rot_yaw *= linalg.matrix4_rotate_f32(yawInput * dt, {0,1,0})
		view_rot_pitch *= linalg.matrix4_rotate_f32(pitchInput * dt, {1, 0, 0})
	}

	view_rot = view_rot_pitch * view_rot_yaw

	move : vec4 = { ((rl.IsKeyDown(.A) ? 1.0 : 0.0) - (rl.IsKeyDown(.D) ? 1.0 : 0.0)),
	                ((rl.IsKeyDown(.LEFT_CONTROL) ? 1.0 : 0.0) - (rl.IsKeyDown(.SPACE) ? 1.0 : 0.0)), 
					((rl.IsKeyDown(.W) ? 1.0 : 0.0) - (rl.IsKeyDown(.S) ? 1.0 : 0.0)) ,
					1}

	view_pos += (linalg.inverse(view_rot) * move).xyz * speed * dt
}

camera := rl.Camera2D {
	target = {scaled_width / -2, 0},
	zoom   = unit_scale,
}

game_update_state :: proc(dt: f32) {

	tracy.Zone()
	rl.BeginDrawing()
	rl.ClearBackground(color(0))
	defer rl.EndDrawing()


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
		ui_update_begin(dt)
		game_render()
		menu_update()
		ui_update_end(dt)

	case .Play:
		ui_update_begin(dt)
		game_update_input(dt)
		game_render()
		game_debug_ui(dt)

		ui_update_end(dt)

		rl.DrawFPS(100, 100)

	case .GameOver:
		ui_update_begin(dt)
		game_render()
		game_render_score()
		ui_update_end(dt)
	}
}

menu_update :: proc() {
	// rl.DrawText("Play", rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2, 30, color(12))

	if rl.GuiButton({width / 2 - 50, height / 2 - 25, 100, 50}, "PLAY") ||
	   rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		game_state = .Reset
	}
}

proj: mat44

model_mat := mat44(1)
view_rot := mat44(1)
// proj := mat44(1)
// proj := linalg.matrix_ortho3d_f32(0,width,0, height, near, far)
paused := false

game_render :: proc() {
	tracy.Zone()
	
	v := view_rot * linalg.matrix4_translate_f32(view_pos.xyz)

	if !paused {
		when RENDER_TILED {
			tile_render_begin()
			defer tile_render_end()

			if activeMesh != nil {
				tile_model_render(activeMesh, material, &model_mat, &v, &proj)
			}
		} else {
			render_begin()
			defer render_end()

			if activeMesh != nil {
				model_render(activeMesh, material, &model_mat, &v, &proj)
			}
		}

	}


	{
		tracy.ZoneN("update_depth_textures")
		when RENDER_TILED {
			rl.UpdateTexture(tile_renderer.screenTexture, raw_data(tile_renderer.screenBuffer))

			rl.UpdateTexture(tile_renderer.depthTexture, raw_data(tile_renderer.depthBuffer))
		} else {
			rl.UpdateTexture(renderer.screenTexture, raw_data(renderer.screenBuffer))

			rl.UpdateTexture(renderer.depthTexture, raw_data(renderer.depthBuffer))
		}

		// ui is drawing now
		// rl.BeginTextureMode(renderer.screenTextureFlipped)
		// defer rl.EndTextureMode()
		// rl.DrawTexturePro(
		// 	texture = renderer.screenTexture.texture,
		// 	source = {0, 0, f32(renderer.width), f32(renderer.height)},
		// 	dest = {0, 0, auto_cast renderer.width, auto_cast renderer.height},
		// 	origin = {0, 0},
		// 	rotation = 0,
		// 	tint = rl.WHITE,
		// )


	}
}

game_render_score :: proc() {
	// rl.DrawText(rl.TextFormat("Score: {}", score), 100, 10, 30, color(0))
	// rl.DrawLineEx({-play_area.x, 1}, {play_area.x, 1}, 0.2, color(0))
}

loadedModel: Model

make_render_textures :: proc(width, height: i32) -> (screen, depth: rl.Texture2D) {
	screenImg := rl.GenImageColor(width, height, rl.BLACK)
	rl.ImageFormat(&screenImg, .UNCOMPRESSED_R32G32B32A32)
	screen = rl.LoadTextureFromImage(screenImg)
	rl.UnloadImage(screenImg)

	depthImg := rl.GenImageColor(width, height, rl.BLACK)
	rl.ImageFormat(&depthImg, .UNCOMPRESSED_R32)
	depth = rl.LoadTextureFromImage(depthImg)
	rl.UnloadImage(depthImg)

	return
}

active_width :: proc "contextless" () -> i32 {
	when RENDER_TILED {
		return tile_renderer.width
	} else {
		return renderer.width
	}
}

active_height :: proc "contextless" () -> i32 {
	when RENDER_TILED {
		return tile_renderer.height
	} else {
		return renderer.height
	}
}

active_screen_texture :: proc "contextless" () -> ^rl.Texture2D {
	when RENDER_TILED {
		return &tile_renderer.screenTexture
	} else {
		return &renderer.screenTexture
	}
}

active_depth_texture :: proc "contextless" () -> ^rl.Texture2D {
	when RENDER_TILED {
		return &tile_renderer.depthTexture
	} else {
		return &renderer.depthTexture
	}
}

game_init :: proc() {

	

	when RENDER_TILED {
		tile_renderer_init(640/2,400/2)
		tile_renderer.screenTexture, tile_renderer.depthTexture =
			make_render_textures(tile_renderer.width, tile_renderer.height)
	} else {
		renderer_init(640/2,400/2)
		renderer.screenTexture, renderer.depthTexture =
			make_render_textures(renderer.width, renderer.height)
	}

	proj = linalg.matrix4_perspective_f32(auto_cast linalg.to_radians(fov), f32(active_width()) / f32(active_height()), near, far)

	material.name = "material"
	material.texture = rl.LoadImage("assets/grass.png")
	// material.texture = rl.LoadImage("assets/models/UnitCube/testTexture.png")
	// material.texture = rl.LoadImage("assets/models/DamagedHelmet/glTF/Default_albedo.jpg")
	// material.texture = rl.LoadImage("assets/models/Suzanne/glTF/Suzanne_BaseColor.png")
	
	material.ambient = 0.1


	//  loadedModel = load_model("assets/models/Lantern/glTF/Lantern.gltf")


	// loadedModel = load_model("assets/models/Sponza/glTF/Sponza.gltf")
	//loadedModel = load_model("assets/models/Suzanne/glTF/Suzanne.gltf")
	// loadedModel = load_model("assets/models/BoxTextured/glTF/BoxTextured.gltf")
	sys_find_files("assets", ".gltf", &found)
	sys_find_files("assets", ".glb", &found)
	// game_load_model("assets/models/Triangle/glTF/Triangle.gltf")
    // game_load_model("assets/models/UnitCube/UnitCube.gltf")
	game_load_model("assets/models/Suzanne/glTF/Suzanne.gltf")
	// game_load_model("assets/models/Sponza/glTF/Sponza.gltf")
	// game_load_model("assets/models/E1M1.bsp.geometry.tri/result.gltf")
	// game_load_model("assets/models/Lantern/glTF/Lantern.gltf")
}

game_load_model :: proc(path: cstring) {
	loadedModel = load_model(path)
	activeMesh = &loadedModel

	tex := loadedModel.materials[0].maps[0].texture

	fmt.printfln("tex: %vx%v", tex.width, tex.height)
	// material.texture = rl.ImageCopy(rl.LoadImageFromTexture(tex))

	// data := rlgl.ReadTexturePixels(tex.id, tex.width, tex.height, auto_cast tex.format)
	
	// rl.ImageFormat(&material.texture, .UNCOMPRESSED_R32G32B32A32)
	bounds := rl.GetModelBoundingBox(loadedModel)

	radius := linalg.length(bounds.max - bounds.min)
	view_pos.z = -radius * 1.25

}

game_check_end :: proc() {

}

game_debug_ui :: proc(dt: f32, window: bool = true) {

	if mu.window(ui_ctx, "root", {0,0,width,height}, {.NO_FRAME, .NO_CLOSE, .NO_TITLE, .NO_RESIZE}) {
		if mu.window(ui_ctx, "Frame", {0, 0, width-300, height}, {.NO_CLOSE,}) {
			mu.layout_row(ui_ctx, {-1})
			mu.draw_image(ui_ctx, mu.layout_next(ui_ctx), active_screen_texture(), {255,255,255,255} )
		}


		if mu.window(ui_ctx, "Editor", {width-300, 0, 300, height}, {.NO_CLOSE}){

			cmdCount:u32 = renderer.nextRenderCmdId-1

			if .ACTIVE in mu.header(ui_ctx, "Renderer", {.EXPANDED}) {
				
				win := mu.get_current_container(ui_ctx)
				mu.layout_row(ui_ctx, {54, -1}, 0)
				mu.label(ui_ctx, "Index:")
				u32_slider(ui_ctx, &renderer.triRenderIdStart, 0, cmdCount-1 )

				mu.label(ui_ctx, "Count:")
				u32_slider(ui_ctx, &renderer.triRenderIdCount, 1, renderer.totalTriProcessed*2 )

				mu.label(ui_ctx, "Tris:")
				mu.label(ui_ctx, fmt.tprintf("%d", renderer.totalTriProcessed))

				mu.label(ui_ctx, "CMDs:")
				mu.label(ui_ctx, fmt.tprintf("%d", cmdCount))

				mu.label(ui_ctx, "CMD len:")
				mu.label(ui_ctx, fmt.tprintf("%d", len(renderer.commands)))
				
				
				mu.layout_row(ui_ctx, {-1})
				mu.checkbox(ui_ctx,"Back Face Cull", &renderer.backfaceCull )

				mu.layout_row(ui_ctx, {-1})
				mu.checkbox(ui_ctx,"Clipping", &renderer.clipping )

				mu.layout_row(ui_ctx, {-1})
				mu.checkbox(ui_ctx,"Only Clipped", &renderer.onlyClipped )

				mu.label(ui_ctx, "Near")
				mu.number(ui_ctx, &renderer.nearZ, 0.1 )

				mu.label(ui_ctx, "Light")
				mu.number(ui_ctx, &renderer.light_intensity, 0.01 )


				mu.layout_row(ui_ctx, {-1})
				mu.checkbox(ui_ctx,"Normals", &renderer.debugNormals )

				
				cmd := cmdCount > 0 ? renderer.commands[renderer.triRenderIdStart] : TriRenderCmd{}
				reflective_editor("TriRenderCmd", typeid_of(TriRenderCmd), cmd, true)
			}

			if .ACTIVE in mu.header(ui_ctx, "Models") {
				index :u32 = 0
				for filename in found {
					index += 1
					if .SUBMIT in mu.button(ui_ctx, filepath.base(filename)) {

						view_pos = vec3{0, -0.5, -3}
						view_rot = mat44(1)
						game_load_model(
							strings.clone_to_cstring(filename, context.temp_allocator),
						)
					}
				}
			}

			if .ACTIVE in mu.header(ui_ctx, "Depth") {
					mu.layout_row(ui_ctx, {-1})
					mu.checkbox(ui_ctx,"Less Than", &renderer.depthFipped )

					win := mu.get_current_container(ui_ctx)
					mu.layout_row(ui_ctx, {-1})
					mu.draw_image(ui_ctx, mu.layout_next(ui_ctx), active_depth_texture(), {255,255,255,255} )
				}

		}
	}
}

u32_slider :: proc(ctx: ^mu.Context, val: ^u32, lo, hi: u32) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))

	@static tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u32(tmp)
	mu.pop_id(ctx)
	return
}

reflective_editor :: proc(tname:string, tid:typeid, v:any, header:bool){

	info := type_info_of(tid)

	if !reflect.is_struct(info) && !reflect.is_array(info) {
	
		mu.label(ui_ctx, tname)
		mu.label(ui_ctx, fmt.tprintf("%v", v))
		
		return
	}

	element := header ? mu.header(ui_ctx, tname, {}) : mu.begin_treenode(ui_ctx, tname)

	if .ACTIVE in element {
		// if .ACTIVE in mu.header(ui_ctx, "Window Info") {
		win := mu.get_current_container(ui_ctx)
		mu.layout_row(ui_ctx, {54, -1}, 0)
		

		if reflect.is_struct(info) {

			names := reflect.struct_field_names(tid)
			types := reflect.struct_field_types(tid)
			tags  := reflect.struct_field_tags(tid)

			for name, i in names {
				tag, type := tags[i], types[i]
				
				mu.layout_row(ui_ctx,{100, -1})
				
				fvalue := reflect.struct_field_value_by_name(v, name)

				reflective_editor(name, type.id, fvalue, false)
			}
		} else if reflect.is_array(info) {
			it : int
			tid := reflect.typeid_elem(type_of(v))

			for e,i in reflect.iterate_array(v, &it) {
				reflective_editor(fmt.tprintf("%d",i), tid , e, false)
			}	
		}

		if !header { mu.end_treenode(ui_ctx) }
	}
}

// game_debug_ui_clay :: proc(dt: f32, window: bool = true) {
// 	tracy.Zone()

// 	// ui.SetDebugModeEnabled(true)
// 	if ui.UI(uidOuterContainer)({
// 		layout = {
// 			layoutDirection = .TopToBottom, sizing = style.sizeFill,
// 		}
// 	}) {
// 		//ui.Rectangle({color = COL_BG}),

// 		// if ui.UI(ui.ID("Menu"))(
// 		// {a
// 		// 	layout = 
// 		// 		{
// 		// 			layoutDirection = .LEFT_TO_RIGHT,
// 		// 			sizing = {ui.SizingGrow({}), ui.SizingFit({})},
// 		// 			padding = {8, 4},
// 		// 			childGap = 8,
// 		// 		},
// 		// 	//ui.Rectangle({color = COL_PANEL, cornerRadius = ui.CornerRadiusAll(8)}),
// 		// 	// ui.Border({bottom = {color = COL_PANEL, width=2}})
// 		// },
// 	    // ) {

// 		// 	pointerOver := false // ui.PointerOver(uiMenuFile.id)
// 		// 	if ui.UI(
// 		// 		uiMenuFile,
// 		// 		ui.Layout({childAlignment = {x = .CENTER, y = .CENTER}, padding = {8, 8}}),
// 		// 		ui.Rectangle(
// 		// 			{
// 		// 				color = pointerOver ? COL_HL : COL_BORDER,
// 		// 				cornerRadius = ui.CornerRadiusAll(8),
// 		// 			},
// 		// 		),
// 		// 	) {
// 		// 		if pointerOver && currentPointerState == .RELEASED_THIS_FRAME {
// 		// 			ui.Text("Pressed", &style.text)


// 		// 			clear(&found)
// 		// 			sys_find_files("assets", ".gltf", &found)


// 		// 		}
// 		// 		ui.Text("File", &style.text)

// 		// 	}

// 		// 	pointerOver = ui.PointerOver(uiMenuDebug.id)

// 		// 	if ui.UI(
// 		// 		uiMenuDebug,
// 		// 		ui.Layout({childAlignment = {x = .CENTER, y = .CENTER}, padding = {8, 8}}),
// 		// 		ui.Rectangle(
// 		// 			{
// 		// 				color = (pointerOver || drawUiDebugger) ? COL_HL : COL_PANEL,
// 		// 				cornerRadius = ui.CornerRadiusAll(8),
// 		// 			},
// 		// 		),
// 		// 	) {
// 		// 		if ui.PointerOver(uiMenuDebug.id) && currentPointerState == .RELEASED_THIS_FRAME {

// 		// 			drawUiDebugger = !drawUiDebugger
// 		// 			ui.SetDebugModeEnabled(drawUiDebugger)
// 		// 		}

// 		// 		ui.Text("Debug", &style.text)

// 		// 	}


// 		// }

// 		if ui.UI(ui.ID("MainContent"))({
// 			layout = 
// 				{
// 					layoutDirection = .LeftToRight,
// 					sizing = style.sizeFill,
// 					padding = {8, 8, 8, 8},
// 					childGap = 8,
// 				},
// 			},
// 			) {

// 				if ui.UI(ui.ID("RenderTarget"))({
// 					layout = {
// 						sizing = style.sizeFill,
						
// 					},
// 					aspectRatio = {cast(f32)active_width() / cast(f32)active_height()},
// 					image = {
// 						imageData = active_screen_texture(),
// 					},
// 				}){}

// 				if ui.UI(ui.ID("Sidebar"))({
// 					layout = 
// 						{
// 							layoutDirection = .TopToBottom,
// 							sizing = { ui.SizingFit({200, 300}), ui.SizingGrow({})},
// 							childGap = 10,
// 						},
// 				}){
// 					if ui.UI(ui.ID("Models"))(
// 					{
// 						layout =
// 							{
// 								layoutDirection = .TopToBottom,
// 								sizing = {ui.SizingGrow({}), ui.SizingFit({})},
// 								padding = {20, 8, 8, 8},
// 								childGap = 10,
// 							},
// 					},
// 					) {
// 							// ui.Rectangle({color = COL_PANEL, cornerRadius = ui.CornerRadiusAll(8)}),
// 							// ui.BorderAllRadius({1, COL_BORDER}, 8),
						
// 							ui.Text("Models", style.textHeader)

// 							ui.Text(fmt.tprint("Rend Tri  Id: ", renderer.triRenderIdStart), style.text)
// 							ui.Text(fmt.tprint("Rend Tri Cnt: ", renderer.triRenderIdCount), style.text)

// 							index :u32 = 0
// 							for filename in found {
// 								uid := ui.ID(filename, index)
// 								index += 1
// 								// pointerOver := ui.PointerOver(uid.id)
// 								// fmt.bprintf("model_file_%v", filename)
// 								if ui.UI(uid)({
// 									layout = {
// 											layoutDirection = .TopToBottom,
// 											sizing = {ui.SizingGrow({}), ui.SizingFit({})},
// 											padding = {8, 8, 8 ,8},
// 										},
// 										backgroundColor = ui.Hovered() ? COL_HL : COL_BG,
// 								}){
// 									// ui.Rectangle(
// 									// 	{
// 									// 		color = pointerOver ? COL_HL : COL_PANEL,
// 									// 		cornerRadius = ui.CornerRadiusAll(8),
// 									// 	},
// 									// ),
							
// 									ui.Text(filepath.base(filename), style.text)
// 									// 
// 									if ui.Hovered() && currentPointerState.state == .PressedThisFrame {

// 										game_load_model(
// 											strings.clone_to_cstring(filename, context.temp_allocator),
// 										)
// 									}
// 								}
// 							}
// 						}

// 					// if ui.UI(
// 					// 	ui.ID("Properties"),
// 					// 	ui.Layout(
// 					// 		{
// 					// 			layoutDirection = .TOP_TO_BOTTOM,
// 					// 			sizing = {ui.SizingGrow({}), ui.SizingFit({})},
// 					// 			padding = {20, 8},
// 					// 			childGap = 10,
// 					// 		},
// 					// 	),
// 					// 	ui.Rectangle({color = COL_PANEL, cornerRadius = ui.CornerRadiusAll(8)}),
// 					// 	// ui.BorderAllRadius({1, COL_BORDER}, 8),
// 					// ) {
// 					// 	ui.Text("Properties", &style.textHeader)

// 					// 	ui.Text(fmt.tprint("FPS:", rl.GetFPS()), &style.text)
// 					// }
			

// 				}
// 			}
// 		}
// }