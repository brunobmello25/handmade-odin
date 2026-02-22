package main

import rl "vendor:raylib"

width, height :: 800, 600

main :: proc() {
	rl.InitWindow(width, height, "Handmade Raylib")

	running := true

	for running {
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)

		if rl.IsKeyDown(.ESCAPE) {
			running = false
		}

		rl.EndDrawing()
	}
}
