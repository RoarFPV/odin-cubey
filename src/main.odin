package cubey

import rl "vendor:raylib"
// import rlgl "vendor:raylib/rlgl"


main :: proc() {

	//Profile heap allocations with Tracy for this context.
	// context.allocator = tracy.MakeProfiledAllocator(
	// 	self = &tracy.ProfiledAllocatorData{},
	// 	callstack_size = 5,
	// 	backing_allocator = context.allocator,
	// 	secure = true,
	// )

	// tracy.SetThreadName("main")

	rl.InitWindow(width, height, "cubey")
	rl.SetWindowState(rl.ConfigFlags{.WINDOW_RESIZABLE, .WINDOW_UNDECORATED})
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)


	for !rl.WindowShouldClose() {
		{
			tracy.Zone()
			dt := rl.GetFrameTime()


			game_update_state(dt)


			free_all(context.temp_allocator)
		}
		tracy.FrameMark()
	}
}
