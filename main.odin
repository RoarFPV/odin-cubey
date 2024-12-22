package cubey

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

main :: proc() {

	rl.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI,})
	rl.InitWindow(width, height, "cubey")
	defer rl.CloseWindow()

	rl.SetTargetFPS(165)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		

		game_update_state(dt)

		

		free_all(context.temp_allocator)
	}
}
