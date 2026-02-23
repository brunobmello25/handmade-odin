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

// Returns a Button_State sampled from a keyboard key this frame.
fill_button_key :: proc(key: rl.KeyboardKey) -> game.Button_State {
	changed := rl.IsKeyPressed(key) || rl.IsKeyReleased(key)
	return game.Button_State {
		ended_down = rl.IsKeyDown(key),
		half_transition_count = cast(i32)changed,
	}
}

// Returns a Button_State sampled from a gamepad button this frame.
fill_button_gamepad :: proc(pad: i32, btn: rl.GamepadButton) -> game.Button_State {
	changed := rl.IsGamepadButtonPressed(pad, btn) || rl.IsGamepadButtonReleased(pad, btn)
	return game.Button_State {
		ended_down = rl.IsGamepadButtonDown(pad, btn),
		half_transition_count = cast(i32)changed,
	}
}

// Returns a Button_State sampled from a mouse button this frame.
fill_button_mouse :: proc(btn: rl.MouseButton) -> game.Button_State {
	changed := rl.IsMouseButtonPressed(btn) || rl.IsMouseButtonReleased(btn)
	return game.Button_State {
		ended_down = rl.IsMouseButtonDown(btn),
		half_transition_count = cast(i32)changed,
	}
}

// Builds a game.Input by polling all raylib input sources.
// Controller 0 is always the keyboard; controllers 1..MAX_CONTROLLERS are gamepads.
process_input :: proc() -> game.Input {
	input: game.Input
	input.delta_time = rl.GetFrameTime()

	// --- Controller 0: keyboard ---
	kb := &input.controllers[0]
	kb.is_connected = true
	kb.move_up = fill_button_key(.W)
	kb.move_down = fill_button_key(.S)
	kb.move_left = fill_button_key(.A)
	kb.move_right = fill_button_key(.D)
	kb.action_up = fill_button_key(.UP)
	kb.action_down = fill_button_key(.DOWN)
	kb.action_left = fill_button_key(.LEFT)
	kb.action_right = fill_button_key(.RIGHT)
	kb.left_shoulder = fill_button_key(.Q)
	kb.right_shoulder = fill_button_key(.E)
	kb.back = fill_button_key(.BACKSPACE)
	kb.start = fill_button_key(.ENTER)

	// --- Controllers 1..MAX_CONTROLLERS: gamepads ---
	for i in 0 ..< game.MAX_CONTROLLERS {
		pad := i32(i)
		ctrl := &input.controllers[i + 1]

		if !rl.IsGamepadAvailable(pad) {
			ctrl.is_connected = false
			continue
		}

		ctrl.is_connected = true
		ctrl.move_up = fill_button_gamepad(pad, .LEFT_FACE_UP)
		ctrl.move_down = fill_button_gamepad(pad, .LEFT_FACE_DOWN)
		ctrl.move_left = fill_button_gamepad(pad, .LEFT_FACE_LEFT)
		ctrl.move_right = fill_button_gamepad(pad, .LEFT_FACE_RIGHT)
		ctrl.action_up = fill_button_gamepad(pad, .RIGHT_FACE_UP)
		ctrl.action_down = fill_button_gamepad(pad, .RIGHT_FACE_DOWN)
		ctrl.action_left = fill_button_gamepad(pad, .RIGHT_FACE_LEFT)
		ctrl.action_right = fill_button_gamepad(pad, .RIGHT_FACE_RIGHT)
		ctrl.left_shoulder = fill_button_gamepad(pad, .LEFT_TRIGGER_1)
		ctrl.right_shoulder = fill_button_gamepad(pad, .RIGHT_TRIGGER_1)
		ctrl.back = fill_button_gamepad(pad, .MIDDLE_LEFT)
		ctrl.start = fill_button_gamepad(pad, .MIDDLE_RIGHT)

		stick_x := rl.GetGamepadAxisMovement(pad, .LEFT_X)
		stick_y := rl.GetGamepadAxisMovement(pad, .LEFT_Y)
		ctrl.stick_average_x = stick_x
		ctrl.stick_average_y = stick_y

		dpad_pressed :=
			ctrl.move_up.ended_down ||
			ctrl.move_down.ended_down ||
			ctrl.move_left.ended_down ||
			ctrl.move_right.ended_down
		ctrl.is_analog = !dpad_pressed && (stick_x != 0 || stick_y != 0)
	}

	// --- Mouse ---
	input.mouse_buttons[0] = fill_button_mouse(.LEFT)
	input.mouse_buttons[1] = fill_button_mouse(.MIDDLE)
	input.mouse_buttons[2] = fill_button_mouse(.RIGHT)
	input.mouse_buttons[3] = fill_button_mouse(.SIDE)
	input.mouse_buttons[4] = fill_button_mouse(.EXTRA)
	input.mouse_x = rl.GetMouseX()
	input.mouse_y = rl.GetMouseY()
	input.mouse_z = i32(rl.GetMouseWheelMove())

	return input
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
		input := process_input()
		game.update_and_render(game_backbuffer, &input)
		blit_backbuffer(backbuffer)

		rl.EndDrawing()
	}
}
