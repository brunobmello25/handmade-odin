package platform

import "core:log"
import rl "vendor:raylib"

import "../game"

width, height :: 960, 540
FPS :: 60

SoundBuffer :: struct {
	samples:           []i16,
	sample_rate:       u32,
	channels:          u32,
	stream:            rl.AudioStream,
	write_cursor:      u32, // frames accumulated but not yet pushed
	frames_per_buffer: u32, // sub-buffer size (frames per push to raylib)
	push_count:        u32, // total pushes made; used to delay playback start
}

Backbuffer :: struct {
	width, height: i32,
	pixels:        []u32,
	texture:       rl.Texture2D,
}

init_backbuffer :: proc(width, height: i32) -> Backbuffer {
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

init_sound_buffer :: proc() -> SoundBuffer {
	channels: u32 = 2
	sample_size: u32 = 16
	sample_rate: u32 = 48000

	frames_per_buffer := sample_rate / u32(FPS) * 2
	samples := make([]i16, sample_rate * channels) // 1 second of audio

	rl.SetAudioStreamBufferSizeDefault(i32(frames_per_buffer))
	stream := rl.LoadAudioStream(sample_rate, sample_size, channels)
	// PlayAudioStream is called lazily in blit_audio after both sub-buffers are primed.

	return SoundBuffer {
		sample_rate = sample_rate,
		channels = channels,
		stream = stream,
		samples = samples,
		frames_per_buffer = frames_per_buffer,
	}
}

get_samples_to_generate :: proc(sound_buffer: SoundBuffer, seconds_elapsed: f32) -> u32 {
	samples_to_generate := u32(seconds_elapsed * f32(sound_buffer.sample_rate))
	// Cap so we never write past the end of the accumulation buffer.
	// Two sub-buffers worth is a safe maximum — beyond that we'd be
	// too far behind for smooth audio anyway.
	max_samples := sound_buffer.frames_per_buffer * 2
	remaining_capacity := max_samples - min(sound_buffer.write_cursor, max_samples)
	return clamp(samples_to_generate, 0, remaining_capacity)
}

blit_audio :: proc(sound_buffer: ^SoundBuffer) {
	for rl.IsAudioStreamProcessed(sound_buffer.stream) && sound_buffer.write_cursor >= sound_buffer.frames_per_buffer {
		rl.UpdateAudioStream(
			sound_buffer.stream,
			raw_data(sound_buffer.samples),
			i32(sound_buffer.frames_per_buffer),
		)

		remaining := sound_buffer.write_cursor - sound_buffer.frames_per_buffer
		if remaining > 0 {
			src_start := sound_buffer.frames_per_buffer * sound_buffer.channels
			copy_len := remaining * sound_buffer.channels
			// Forward copy is safe since dst < src
			for i in 0 ..< copy_len {
				sound_buffer.samples[i] = sound_buffer.samples[src_start + i]
			}
		}
		sound_buffer.write_cursor -= sound_buffer.frames_per_buffer
		sound_buffer.push_count += 1
	}
	// Delay playback until both sub-buffers have real audio so playback starts cleanly.
	if !rl.IsAudioStreamPlaying(sound_buffer.stream) && sound_buffer.push_count >= 2 {
		rl.PlayAudioStream(sound_buffer.stream)
	}
}

main :: proc() {
	context.logger = log.create_console_logger()

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(width, height, "Game - Handmade Raylib")
	rl.InitAudioDevice()

	backbuffer := init_backbuffer(width, height)

	rl.SetTargetFPS(FPS)

	sound_buffer := init_sound_buffer()

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)

		game_backbuffer := game.Backbuffer {
			width  = backbuffer.width,
			height = backbuffer.height,
			pixels = backbuffer.pixels,
		}
		input := process_input()
		frames_to_generate := get_samples_to_generate(sound_buffer, input.delta_time)
		sample_offset := sound_buffer.write_cursor * sound_buffer.channels
		game_soundbuffer := game.SoundBuffer {
			sample_count = frames_to_generate,
			samples      = sound_buffer.samples[sample_offset:],
			sample_rate  = sound_buffer.sample_rate,
		}
		game.update_and_render(game_backbuffer, game_soundbuffer, &input)
		sound_buffer.write_cursor += frames_to_generate

		blit_backbuffer(backbuffer)
		blit_audio(&sound_buffer)

		// Resize happens after audio is pushed so the slow GPU realloc doesn't
		// delay the next blit_audio call and drain the stream.
		if rl.IsWindowResized() {
			new_width := rl.GetScreenWidth()
			new_height := rl.GetScreenHeight()
			resize_backbuffer(&backbuffer, new_width, new_height)
			log.info("Resized backbuffer to %d x %d", new_width, new_height)
		}

		rl.EndDrawing()
	}
}
