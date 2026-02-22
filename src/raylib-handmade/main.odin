package main

import rl "vendor:raylib"

width, height :: 960, 540
FPS :: 60

Backbuffer :: struct {
	width, height: i32,
	pixels:        []u32,
	texture:       rl.Texture2D,
}

make_backbuffer :: proc(width, height: i32) -> Backbuffer {
	pixels := make([]u32, width * height)
	texture := rl.LoadTextureFromImage(
		rl.Image {
			width = width,
			height = height,
			mipmaps = 1,
			format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
			data = raw_data(pixels),
		},
	)
	return Backbuffer{texture = texture, width = width, height = height, pixels = pixels}
}

render_weird_gradient :: proc(backbuffer: ^Backbuffer) {
	for y in 0 ..< backbuffer.height {
		for x in 0 ..< backbuffer.width {
			blue := u32(x)
			green := u32(y)
			backbuffer.pixels[y * backbuffer.width + x] = (0xFF << 24) | (green << 8) | blue
		}
	}
}

blit_backbuffer :: proc(backbuffer: Backbuffer) {
	rl.UpdateTexture(backbuffer.texture, raw_data(backbuffer.pixels))
	rl.DrawTexture(backbuffer.texture, 0, 0, rl.WHITE)
}

main :: proc() {
	rl.InitWindow(width, height, "Handmade Raylib")

	backbuffer := make_backbuffer(width, height)

	rl.SetTargetFPS(FPS)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)

		render_weird_gradient(&backbuffer)
		blit_backbuffer(backbuffer)

		rl.EndDrawing()
	}
}
