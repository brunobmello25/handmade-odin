package platform

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import rl "vendor:raylib"

import "../game"

width, height :: 960, 540
FPS :: 60

// One second of audio. Large enough to absorb any frame-rate hiccup
// (resize, focus loss, etc.) without underrun.
AUDIO_RING_FRAMES :: 48000

// Safety margin: keep this many callback-periods buffered ahead of the read cursor.
// 4 gives one full extra period of slack before any underrun is possible.
AUDIO_LATENCY_PERIODS :: 4

// Accessed by the audio callback which has no userdata parameter.
_sound_buffer: ^SoundBuffer

SoundBuffer :: struct {
	ring:           []i16, // circular buffer; AUDIO_RING_FRAMES * channels samples
	ring_cap:       u32, // = AUDIO_RING_FRAMES
	write_pos:      u32, // absolute frame count; written by game thread
	read_pos:       u32, // absolute frame count; written by audio callback
	latency_frames: u32, // detected from first callback; latency = callback_size * AUDIO_LATENCY_PERIODS
	sample_rate:    u32,
	channels:       u32,
	stream:         rl.AudioStream,
	temp:           []i16, // scratch buffer; game writes here each frame
}

// Called by the audio thread whenever it needs more data.
// Reads from the ring buffer; outputs silence on underrun.
_audio_callback :: proc "c" (raw_buffer: rawptr, frames: u32) #no_bounds_check {
	sb := _sound_buffer
	out := (cast([^]i16)raw_buffer)[:frames * sb.channels]

	// Detect actual callback size on first call and derive a safe latency from it.
	// SetAudioStreamBufferSizeDefault is a request; the hardware may enforce a larger period.
	if sb.latency_frames == 0 {
		intrinsics.atomic_store(&sb.latency_frames, frames * AUDIO_LATENCY_PERIODS)
	}

	write_pos := intrinsics.atomic_load(&sb.write_pos)
	read_pos := sb.read_pos // only this thread writes read_pos

	available := write_pos - read_pos
	to_serve := min(frames, available)

	for i in 0 ..< to_serve {
		src := ((read_pos + i) % sb.ring_cap) * sb.channels
		out[i * 2] = sb.ring[src]
		out[i * 2 + 1] = sb.ring[src + 1]
	}
	for i in to_serve ..< frames {
		out[i * 2] = 0
		out[i * 2 + 1] = 0
	}

	intrinsics.atomic_store(&sb.read_pos, read_pos + to_serve)
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

init_sound_buffer :: proc() -> ^SoundBuffer {
	channels: u32 = 2
	sample_size: u32 = 16
	sample_rate: u32 = 48000
	ring_cap: u32 = AUDIO_RING_FRAMES

	rl.SetAudioStreamBufferSizeDefault(i32(sample_rate / u32(FPS)))
	stream := rl.LoadAudioStream(sample_rate, sample_size, channels)

	sb := new(SoundBuffer)
	sb^ = SoundBuffer {
		ring        = make([]i16, ring_cap * channels),
		ring_cap    = ring_cap,
		sample_rate = sample_rate,
		channels    = channels,
		stream      = stream,
		temp        = make([]i16, ring_cap * channels),
	}

	_sound_buffer = sb
	rl.SetAudioStreamCallback(sb.stream, _audio_callback)
	rl.PlayAudioStream(sb.stream)
	return sb
}

// Copies frames written to temp into the ring buffer and advances write_pos.
push_audio :: proc(sb: ^SoundBuffer, frames: u32) #no_bounds_check {
	for i in 0 ..< frames {
		dst := ((sb.write_pos + i) % sb.ring_cap) * sb.channels
		sb.ring[dst] = sb.temp[i * sb.channels]
		sb.ring[dst + 1] = sb.temp[i * sb.channels + 1]
	}
	intrinsics.atomic_store(&sb.write_pos, sb.write_pos + frames)
}

// How many frames to generate this tick.
// Always writes up to read_pos + latency_frames (derived from actual callback size).
// Self-correcting: a late frame finds read_pos has advanced further, so we
// generate more to catch up — no cumulative drift from delta_time truncation.
get_samples_to_generate :: proc(sound_buffer: ^SoundBuffer) -> u32 {
	latency := intrinsics.atomic_load(&sound_buffer.latency_frames)
	if latency == 0 {
		return 0 // wait for first callback to detect actual hardware period
	}
	read_pos := intrinsics.atomic_load(&sound_buffer.read_pos)
	target_pos := read_pos + latency
	if sound_buffer.write_pos >= target_pos {
		return 0
	}
	to_write := target_pos - sound_buffer.write_pos
	buffered := sound_buffer.write_pos - read_pos
	space := sound_buffer.ring_cap - buffered
	return min(to_write, space)
}

init_memory :: proc() -> (game.Memory, runtime.Allocator_Error) {
	permanent_storage_size := 64 * mem.Megabyte
	transient_storage_size := 2 * mem.Gigabyte

	permanent_storage, err := mem.alloc(permanent_storage_size)
	if err != nil {
		return game.Memory{}, err
	}

	transient_storage, transient_err := mem.alloc(transient_storage_size)
	if transient_err != nil {
		mem.free(permanent_storage)
		return game.Memory{}, transient_err
	}

	return game.Memory {
			permanent_storage = permanent_storage,
			permanent_storage_size = permanent_storage_size,
			transient_storage = transient_storage,
			transient_storage_size = transient_storage_size,
		},
		nil
}

when ODIN_DEBUG {
	debug_load_entire_file :: proc(path: string) -> []byte {
		return os.read_entire_file(path) or_else panic("Failed to read file")
	}
}

main :: proc() {
	context.logger = log.create_console_logger()

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(width, height, "Game - Handmade Raylib")
	rl.InitAudioDevice()
	rl.SetTargetFPS(FPS)

	backbuffer := init_backbuffer(width, height)
	sound_buffer := init_sound_buffer()
	defer rl.StopAudioStream(sound_buffer.stream)
	game_memory, err := init_memory()
	if err != nil {
		log.fatalf("Failed to initialize memory: %v", err)
	}

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)

		input := process_input()
		frames_to_generate := get_samples_to_generate(sound_buffer)

		game.update_and_render(
			&game_memory,
			game.Backbuffer {
				width = backbuffer.width,
				height = backbuffer.height,
				pixels = backbuffer.pixels,
			},
			game.SoundBuffer {
				sample_count = frames_to_generate,
				samples = sound_buffer.temp[:],
				sample_rate = sound_buffer.sample_rate,
			},
			&input,
			game.Platform_Procedures{read_entire_file = debug_load_entire_file},
		)
		push_audio(sound_buffer, frames_to_generate)

		blit_backbuffer(backbuffer)

		rl.EndDrawing()
	}
}
