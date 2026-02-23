package main

import "core:log"
import rl "vendor:raylib"

import "../game"

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


blit_backbuffer :: proc(backbuffer: Backbuffer) {
	rl.UpdateTexture(backbuffer.texture, raw_data(backbuffer.pixels))
	rl.DrawTexture(backbuffer.texture, 0, 0, rl.WHITE)
}

resize_backbuffer :: proc(backbuffer: ^Backbuffer, width, height: i32) {
	backbuffer.width = width
	backbuffer.height = height

	if backbuffer.pixels != nil {
		delete(backbuffer.pixels)
	}

	backbuffer.pixels = make([]u32, width * height)
	rl.UnloadTexture(backbuffer.texture)
	backbuffer.texture = rl.LoadTextureFromImage(
		rl.Image {
			width = width,
			height = height,
			mipmaps = 1,
			format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
			data = raw_data(backbuffer.pixels),
		},
	)
}

main :: proc() {
	context.logger = log.create_console_logger()


	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(width, height, "Game - Handmade Raylib")

	backbuffer := make_backbuffer(width, height)

	rl.SetTargetFPS(FPS)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)

		if rl.IsWindowResized() {
			new_width := rl.GetScreenWidth()
			new_height := rl.GetScreenHeight()
			resize_backbuffer(&backbuffer, new_width, new_height)
			log.info("Resized backbuffer to %d x %d", new_width, new_height)
		}

		game_backbuffer := game.Backbuffer {
			width  = backbuffer.width,
			height = backbuffer.height,
			pixels = backbuffer.pixels,
		}
		game.update_and_render(game_backbuffer)
		blit_backbuffer(backbuffer)

		rl.EndDrawing()
	}
}
