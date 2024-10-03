package cubey

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

main :: proc() {

	rl.InitWindow(width, height, "cubey")
	defer rl.CloseWindow()

	rl.SetTargetFPS(165)

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		rl.BeginDrawing()
		rl.ClearBackground(color(0))
		defer rl.EndDrawing()

		game_update_state(dt)

		rl.DrawFPS(rl.GetScreenWidth() - 100, 10)

		free_all(context.temp_allocator)
	}
}
