package game

import "core:log"
import "core:math"
import "core:mem"

_ :: log

MAX_CONTROLLERS :: 4

World :: struct {
	tilemap: ^Tilemap,
}

GameState :: struct {
	tsine:       f32,
	player_p:    Tilemap_Position,
	world:       ^World,
	world_arena: mem.Arena,
}

Memory :: struct {
	permanent_storage:      rawptr,
	transient_storage:      rawptr,
	permanent_storage_size: int,
	transient_storage_size: int,
	is_initialized:         bool,
}

SoundBuffer :: struct {
	sample_count: u32,
	samples:      []i16,
	sample_rate:  u32,
}

Backbuffer :: struct {
	width, height: i32,
	pixels:        []u32,
}

Button_State :: struct {
	half_transition_count: i32,
	ended_down:            bool,
}

Controller_Input :: struct {
	is_analog:       bool,
	is_connected:    bool,
	stick_average_x: f32,
	stick_average_y: f32,
	using _buttons:  struct #raw_union {
		buttons:      [12]Button_State,
		using _named: struct {
			move_up:        Button_State,
			move_down:      Button_State,
			move_left:      Button_State,
			move_right:     Button_State,
			action_up:      Button_State,
			action_down:    Button_State,
			action_left:    Button_State,
			action_right:   Button_State,
			left_shoulder:  Button_State,
			right_shoulder: Button_State,
			back:           Button_State,
			start:          Button_State,
		},
	},
}

Input :: struct {
	mouse_buttons: [5]Button_State,
	mouse_x:       i32,
	mouse_y:       i32,
	mouse_z:       i32,
	delta_time:    f32,
	controllers:   [MAX_CONTROLLERS + 1]Controller_Input,
}

recanonical_coord :: proc(tilemap: ^Tilemap, tile: ^u32, tile_rel: ^f32) {
	offset := i32(math.round(tile_rel^ / tilemap.tile_side_in_meters))
	tile^ = u32(i32(tile^) + offset)
	tile_rel^ -= f32(offset) * tilemap.tile_side_in_meters
	assert(tile_rel^ >= -0.5 * tilemap.tile_side_in_meters)
	assert(tile_rel^ <= 0.5 * tilemap.tile_side_in_meters)
}

recanonical_position :: proc(tilemap: ^Tilemap, pos: Tilemap_Position) -> Tilemap_Position {
	result := pos
	recanonical_coord(tilemap, &result.abs_tile_x, &result.tile_rel_x)
	recanonical_coord(tilemap, &result.abs_tile_y, &result.tile_rel_y)
	return result
}

draw_rectangle :: proc(
	buffer: Backbuffer,
	real_min_x, real_min_y, real_max_x, real_max_y, r, g, b: f32,
) {
	min_x := i32(math.round(real_min_x))
	min_y := i32(math.round(real_min_y))
	max_x := i32(math.round(real_max_x))
	max_y := i32(math.round(real_max_y))

	if min_x < 0 {min_x = 0}
	if min_y < 0 {min_y = 0}
	if max_x > buffer.width {max_x = buffer.width}
	if max_y > buffer.height {max_y = buffer.height}

	// Pixel format: UNCOMPRESSED_R8G8B8A8 on little-endian => R|G<<8|B<<16|A<<24
	color := u32(r * 255.0) | (u32(g * 255.0) << 8) | (u32(b * 255.0) << 16) | (0xFF << 24)

	for y in min_y ..< max_y {
		for x in min_x ..< max_x {
			buffer.pixels[y * buffer.width + x] = color
		}
	}
}

ENABLE_SINE_WAVE :: false

output_sound :: proc(sound_buffer: SoundBuffer, game_state: ^GameState) {
	if sound_buffer.sample_count == 0 {return}

	tone_hz := 256
	wave_period := f32(sound_buffer.sample_rate) / f32(tone_hz)

	for i in 0 ..< sound_buffer.sample_count {
		sample_value: i16 = 0
		when ENABLE_SINE_WAVE {
			tone_volume: f32 = 3000
			sample_value = i16(math.sin(game_state.tsine) * tone_volume)
		}
		sound_buffer.samples[i * 2] = sample_value
		sound_buffer.samples[i * 2 + 1] = sample_value
		game_state.tsine += 2.0 * math.PI / wave_period
		if game_state.tsine > 2.0 * math.PI {
			game_state.tsine -= 2.0 * math.PI
		}
	}
}

initialize_arena :: proc(arena: ^mem.Arena, memory: ^Memory, already_used: int) {
	base := uintptr(memory.permanent_storage) + uintptr(already_used)
	size := memory.permanent_storage_size - already_used
	arena.data = (cast([^]u8)base)[:size]
}


update_and_render :: proc(
	memory: ^Memory,
	backbuffer: Backbuffer,
	sound_buffer: SoundBuffer,
	input: ^Input,
) {
	assert(size_of(GameState) <= memory.permanent_storage_size)
	game_state := cast(^GameState)memory.permanent_storage
	context.allocator = mem.arena_allocator(&game_state.world_arena)

	if !memory.is_initialized {
		game_state.tsine = 0.0
		game_state.player_p.abs_tile_x = 1
		game_state.player_p.abs_tile_y = 3
		game_state.player_p.tile_rel_x = 0.1
		game_state.player_p.tile_rel_y = 0.1

		initialize_arena(&game_state.world_arena, memory, size_of(GameState))

		game_state.world = new(World)
		world := game_state.world
		world.tilemap = new(Tilemap)
		when ODIN_DEBUG {
			assert(is_in_permanent_storage(memory, game_state.world))
			assert(is_in_permanent_storage(memory, world.tilemap))
		}
		tilemap := world.tilemap

		tilemap.chunk_shift = 8
		tilemap.chunk_mask = 0xFF
		tilemap.chunk_size = 256
		tilemap.tile_side_in_meters = 1.4
		tilemap.tile_side_in_pixels = 60
		tilemap.meters_to_pixels = f32(tilemap.tile_side_in_pixels) / tilemap.tile_side_in_meters
		tilemap.tile_chunk_count_x = 4
		tilemap.tile_chunk_count_y = 4
		tilemap.tile_chunks = make(
			[]Tilemap_Chunk,
			tilemap.tile_chunk_count_x * tilemap.tile_chunk_count_y,
		)
		for y in 0 ..< tilemap.tile_chunk_count_y {
			for x in 0 ..< tilemap.tile_chunk_count_x {
				tilemap.tile_chunks[y * tilemap.tile_chunk_count_x + x].tiles = make(
					[]u32,
					tilemap.chunk_size * tilemap.chunk_size,
				)
			}
		}

		{
			// TODO(bruno): entender por que casey faz essas inicializações com 17 e 9, e 32 screens. Tirou do cu?
			tiles_per_width := 17
			tiles_per_height := 9
			for screen_y in 0 ..< 32 {
				for screen_x in 0 ..< 32 {
					for tile_y in 0 ..< tiles_per_height {
						for tile_x in 0 ..< tiles_per_width {
							abs_tile_x := u32(screen_x * tiles_per_width + tile_x)
							abs_tile_y := u32(screen_y * tiles_per_height + tile_y)

							banana := true ? 1 : 2
							set_tile_value(
								tilemap,
								abs_tile_x,
								abs_tile_y,
								bool(tile_x == tile_y) && bool(tile_y % 2) ? 1 : 0,
							)
						}
					}
				}
			}
		}

		memory.is_initialized = true
	}

	world := game_state.world
	tilemap := world.tilemap

	player_height := tilemap.tile_side_in_meters
	player_width := 0.75 * player_height

	for i in 0 ..< MAX_CONTROLLERS {
		controller := &input.controllers[i]
		if !controller.is_analog {
			speed := 5.0 * input.delta_time
			d_player_x: f32 = 0.0
			d_player_y: f32 = 0.0
			if controller.move_up.ended_down {d_player_y = 1.0}
			if controller.move_down.ended_down {d_player_y = -1.0}
			if controller.move_left.ended_down {d_player_x = -1.0}
			if controller.move_right.ended_down {d_player_x = 1.0}
			d_player_x *= speed
			d_player_y *= speed

			new_pos := game_state.player_p
			new_pos.tile_rel_x += d_player_x
			new_pos.tile_rel_y += d_player_y
			new_pos = recanonical_position(tilemap, new_pos)

			new_pos_left := new_pos
			new_pos_left.tile_rel_x -= player_width / 2
			new_pos_left = recanonical_position(tilemap, new_pos_left)

			new_pos_right := new_pos
			new_pos_right.tile_rel_x += player_width / 2
			new_pos_right = recanonical_position(tilemap, new_pos_right)

			if is_world_point_empty(tilemap, new_pos) &&
			   is_world_point_empty(tilemap, new_pos_left) &&
			   is_world_point_empty(tilemap, new_pos_right) {
				game_state.player_p = new_pos
			}
		}
	}

	output_sound(sound_buffer, game_state)

	// Background (dark red)
	draw_rectangle(backbuffer, 0, 0, f32(backbuffer.width), f32(backbuffer.height), 1.0, 0.0, 0.1)

	center_x := 0.5 * f32(backbuffer.width)
	center_y := 0.5 * f32(backbuffer.height)


	for rel_row in -10 ..< 10 {
		for rel_col in -20 ..< 20 {
			col := u32(i32(game_state.player_p.abs_tile_x) + i32(rel_col))
			row := u32(i32(game_state.player_p.abs_tile_y) + i32(rel_row))

			tile_id := get_tile_value(tilemap, col, row)

			gray: f32 = 0.5
			if tile_id == 1 {
				gray = 1.0
			}
			if col == game_state.player_p.abs_tile_x && row == game_state.player_p.abs_tile_y {
				gray = 0.0
			}

			min_x :=
				center_x -
				tilemap.meters_to_pixels * game_state.player_p.tile_rel_x +
				(f32(rel_col) - 0.5) * f32(tilemap.tile_side_in_pixels)
			min_y :=
				center_y +
				tilemap.meters_to_pixels * game_state.player_p.tile_rel_y -
				f32(rel_row) * f32(tilemap.tile_side_in_pixels)
			max_x := min_x + f32(tilemap.tile_side_in_pixels)
			max_y := min_y - f32(tilemap.tile_side_in_pixels)
			draw_rectangle(backbuffer, min_x, max_y, max_x, min_y, gray, gray, gray)
		}
	}

	// Player (yellow)
	player_left := center_x - 0.5 * tilemap.meters_to_pixels * player_width
	player_top := center_y - tilemap.meters_to_pixels * player_height
	draw_rectangle(
		backbuffer,
		player_left,
		player_top,
		player_left + tilemap.meters_to_pixels * player_width,
		player_top + tilemap.meters_to_pixels * player_height,
		1.0,
		1.0,
		0.0,
	)
}

when ODIN_DEBUG {
	is_in_permanent_storage :: proc(memory: ^Memory, ptr: rawptr) -> bool {
		base := uintptr(memory.permanent_storage)
		p := uintptr(ptr)
		return p >= base && p < base + uintptr(memory.permanent_storage_size)
	}
}
