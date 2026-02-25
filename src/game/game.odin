package game

import "core:log"
import "core:math"

MAX_CONTROLLERS :: 4

World_Position :: struct {
	abs_tile_x: u32,
	abs_tile_y: u32,
	tile_rel_x: f32,
	tile_rel_y: f32,
}

Tile_Chunk_Position :: struct {
	tile_chunk_x: u32,
	tile_chunk_y: u32,
	rel_tile_x:   u32,
	rel_tile_y:   u32,
}

Tile_Chunk :: struct {
	tiles: [^]u32,
}

World :: struct {
	chunk_shift:         u32,
	chunk_mask:          u32,
	chunk_size:          u32,
	tile_side_in_meters: f32,
	tile_side_in_pixels: i32,
	meters_to_pixels:    f32,
	tile_chunk_count_x:  i32,
	tile_chunk_count_y:  i32,
	tile_chunks:         [^]Tile_Chunk,
}

GameState :: struct {
	tsine:    f32,
	player_p: World_Position,
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

get_chunk_position_for :: proc(world: ^World, abs_tile_x, abs_tile_y: u32) -> Tile_Chunk_Position {
	return Tile_Chunk_Position {
		tile_chunk_x = abs_tile_x >> world.chunk_shift,
		tile_chunk_y = abs_tile_y >> world.chunk_shift,
		rel_tile_x = abs_tile_x & world.chunk_mask,
		rel_tile_y = abs_tile_y & world.chunk_mask,
	}
}

get_tile_chunk :: proc(world: ^World, chunk_x, chunk_y: u32) -> ^Tile_Chunk {
	if chunk_x >= u32(world.tile_chunk_count_x) || chunk_y >= u32(world.tile_chunk_count_y) {
		return nil
	}
	return &world.tile_chunks[chunk_y * u32(world.tile_chunk_count_x) + chunk_x]
}

get_tile_value_unchecked :: proc(world: ^World, chunk: ^Tile_Chunk, tile_x, tile_y: u32) -> u32 {
	assert(chunk != nil)
	assert(tile_x < world.chunk_size)
	assert(tile_y < world.chunk_size)
	return chunk.tiles[tile_y * world.chunk_size + tile_x]
}

get_tile_value_from_chunk :: proc(world: ^World, chunk: ^Tile_Chunk, tile_x, tile_y: u32) -> u32 {
	if chunk == nil || tile_x >= world.chunk_size || tile_y >= world.chunk_size {
		return 0
	}
	return get_tile_value_unchecked(world, chunk, tile_x, tile_y)
}

get_tile_value :: proc(world: ^World, abs_tile_x, abs_tile_y: u32) -> u32 {
	chunk_pos := get_chunk_position_for(world, abs_tile_x, abs_tile_y)
	chunk := get_tile_chunk(world, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y)
	return get_tile_value_from_chunk(world, chunk, chunk_pos.rel_tile_x, chunk_pos.rel_tile_y)
}

is_world_point_empty :: proc(world: ^World, pos: World_Position) -> bool {
	return get_tile_value(world, pos.abs_tile_x, pos.abs_tile_y) == 0
}

recanonical_coord :: proc(world: ^World, tile: ^u32, tile_rel: ^f32) {
	offset := i32(math.round(tile_rel^ / world.tile_side_in_meters))
	tile^ = u32(i32(tile^) + offset)
	tile_rel^ -= f32(offset) * world.tile_side_in_meters
	assert(tile_rel^ >= -0.5 * world.tile_side_in_meters)
	assert(tile_rel^ <= 0.5 * world.tile_side_in_meters)
}

recanonical_position :: proc(world: ^World, pos: World_Position) -> World_Position {
	result := pos
	recanonical_coord(world, &result.abs_tile_x, &result.tile_rel_x)
	recanonical_coord(world, &result.abs_tile_y, &result.tile_rel_y)
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

update_and_render :: proc(
	memory: ^Memory,
	backbuffer: Backbuffer,
	sound_buffer: SoundBuffer,
	input: ^Input,
) {
	assert(size_of(GameState) <= memory.permanent_storage_size)
	game_state := cast(^GameState)memory.permanent_storage

	// Tile data — same layout as C++ Day 33. Exactly 9 rows × 24 cols specified;
	// the 256×256 chunk is zero-initialized (empty/walkable) beyond those bounds.
	room: [9][24]u32 = {
		{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1},
		{1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		{1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}
	tiles00: [256][256]u32 // zero-initialized; rows/cols beyond room data stay walkable
	for y in 0 ..< 9 {
		for x in 0 ..< 24 {
			tiles00[y][x] = room[y][x]
		}
	}

	chunk: Tile_Chunk
	chunk.tiles = cast([^]u32)(&tiles00[0][0])

	world: World
	world.chunk_shift = 8
	world.chunk_mask = 0xFF
	world.chunk_size = 256
	world.tile_side_in_meters = 1.4
	world.tile_side_in_pixels = 60
	world.meters_to_pixels = f32(world.tile_side_in_pixels) / world.tile_side_in_meters
	world.tile_chunk_count_x = 1
	world.tile_chunk_count_y = 1
	world.tile_chunks = cast([^]Tile_Chunk)(&chunk)

	if !memory.is_initialized {
		game_state.tsine = 0.0
		game_state.player_p.abs_tile_x = 3
		game_state.player_p.abs_tile_y = 3
		game_state.player_p.tile_rel_x = 0.1
		game_state.player_p.tile_rel_y = 0.1
		memory.is_initialized = true
	}

	player_height := world.tile_side_in_meters
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
			new_pos = recanonical_position(&world, new_pos)

			new_pos_left := new_pos
			new_pos_left.tile_rel_x -= player_width / 2
			new_pos_left = recanonical_position(&world, new_pos_left)

			new_pos_right := new_pos
			new_pos_right.tile_rel_x += player_width / 2
			new_pos_right = recanonical_position(&world, new_pos_right)

			if is_world_point_empty(&world, new_pos) &&
			   is_world_point_empty(&world, new_pos_left) &&
			   is_world_point_empty(&world, new_pos_right) {
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

			tile_id := get_tile_value(&world, col, row)

			gray: f32 = 0.5
			if tile_id == 1 {
				gray = 1.0
			}
			if col == game_state.player_p.abs_tile_x && row == game_state.player_p.abs_tile_y {
				gray = 0.0
			}

			min_x :=
				center_x -
				world.meters_to_pixels * game_state.player_p.tile_rel_x +
				(f32(rel_col) - 0.5) * f32(world.tile_side_in_pixels)
			min_y :=
				center_y +
				world.meters_to_pixels * game_state.player_p.tile_rel_y -
				f32(rel_row) * f32(world.tile_side_in_pixels)
			max_x := min_x + f32(world.tile_side_in_pixels)
			max_y := min_y - f32(world.tile_side_in_pixels)
			draw_rectangle(backbuffer, min_x, max_y, max_x, min_y, gray, gray, gray)
		}
	}

	// Player (yellow)
	player_left := center_x - 0.5 * world.meters_to_pixels * player_width
	player_top := center_y - world.meters_to_pixels * player_height
	draw_rectangle(
		backbuffer,
		player_left,
		player_top,
		player_left + world.meters_to_pixels * player_width,
		player_top + world.meters_to_pixels * player_height,
		1.0,
		1.0,
		0.0,
	)
}
