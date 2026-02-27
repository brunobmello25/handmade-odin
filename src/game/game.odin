package game

import "core:log"
import "core:math"
import "core:math/rand"
import "core:mem"

_ :: log

MAX_CONTROLLERS :: 4

World :: struct {
	tilemap: ^Tilemap,
}

GameState :: struct {
	tsine:            f32,
	player_p:         Tilemap_Position,
	world:            ^World,
	world_arena:      mem.Arena,
	was_on_staircase: bool,
	bitmap_pointer:   []u32, // DEBUG: remove this
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

push_struct :: proc(arena: ^mem.Arena, $T: typeid) -> ^T {
	size := size_of(T)
	ptr := mem.arena_alloc(arena, size) or_else panic("out of memory")
	return cast(^T)ptr
}

push_array :: proc(arena: ^mem.Arena, $T: typeid, count: int) -> []T {
	size := count * size_of(T)
	ptr := mem.arena_alloc(arena, size) or_else panic("out of memory")
	return (cast([^]T)ptr)[:count]
}

update_and_render :: proc(
	memory: ^Memory,
	backbuffer: Backbuffer,
	sound_buffer: SoundBuffer,
	input: ^Input,
	platform_procedures: Platform_Procedures,
) {
	assert(size_of(GameState) <= memory.permanent_storage_size)
	game_state := cast(^GameState)memory.permanent_storage

	if !memory.is_initialized {
		game_state.tsine = 0.0
		game_state.player_p.abs_tile_x = 1
		game_state.player_p.abs_tile_y = 3
		game_state.player_p.abs_tile_z = 0
		game_state.player_p.tile_rel_x = 0.1
		game_state.player_p.tile_rel_y = 0.1

		initialize_arena(&game_state.world_arena, memory, size_of(GameState))
		game_state.world = push_struct(&game_state.world_arena, World)
		game_state.world.tilemap = push_struct(&game_state.world_arena, Tilemap)

		when ODIN_DEBUG {
			assert(is_in_permanent_storage(memory, game_state.world))
			assert(is_in_permanent_storage(memory, game_state.world.tilemap))
		}

		world := game_state.world
		tilemap := world.tilemap

		tilemap.chunk_shift = 4
		tilemap.chunk_mask = (1 << tilemap.chunk_shift) - 1
		tilemap.chunk_size = (1 << tilemap.chunk_shift)
		tilemap.tile_side_in_meters = 1.4
		tilemap.tile_chunk_count_x = 128
		tilemap.tile_chunk_count_y = 128
		tilemap.tile_chunk_count_z = 2

		count := int(
			tilemap.tile_chunk_count_x * tilemap.tile_chunk_count_y * tilemap.tile_chunk_count_z,
		)
		tilemap.tile_chunks = push_array(&game_state.world_arena, Tilemap_Chunk, count)

		{
			// TODO(bruno): entender por que casey faz essas inicializações com 17 e 9, e 32 screens. Tirou do cu?
			tiles_per_width := 17
			tiles_per_height := 9

			door_left, door_right, door_top, door_bottom := false, false, false, false
			door_up, door_down := false, false

			screen_x, screen_y, screen_z := 0, 0, 0
			last_was_z_change := false
			// 1 = last z move went up, -1 = went down; used to place entrance staircase
			last_z_dir := 0

			for screen_index in 0 ..< 100 {
				can_go_z :=
					!last_was_z_change &&
					(screen_z > 0 || screen_z < int(tilemap.tile_chunk_count_z) - 1)

				random_choice: u32
				if can_go_z {
					random_choice = rand.uint32() % 3
				} else {
					random_choice = rand.uint32() % 2
				}

				next_z := screen_z
				if random_choice == 2 {
					can_up := screen_z < int(tilemap.tile_chunk_count_z) - 1
					can_down := screen_z > 0
					if can_up && can_down {
						if rand.uint32() % 2 == 0 {
							door_up = true
							next_z = screen_z + 1
						} else {
							door_down = true
							next_z = screen_z - 1
						}
					} else if can_up {
						door_up = true
						next_z = screen_z + 1
					} else {
						door_down = true
						next_z = screen_z - 1
					}
				} else if random_choice == 0 {
					door_right = true
				} else {
					door_top = true
				}

				for tile_y in 0 ..< tiles_per_height {
					for tile_x in 0 ..< tiles_per_width {
						abs_tile_x := u32(screen_x * tiles_per_width + tile_x)
						abs_tile_y := u32(screen_y * tiles_per_height + tile_y)
						abs_tile_z := u32(screen_z)

						tile_value := 1
						if tile_x == 0 && (!door_left || tile_y != tiles_per_height / 2) {
							tile_value = 2
						}
						if tile_x == tiles_per_width - 1 &&
						   (!door_right || tile_y != tiles_per_height / 2) {
							tile_value = 2
						}
						if tile_y == 0 && (!door_bottom || tile_x != tiles_per_width / 2) {
							tile_value = 2
						}
						if tile_y == tiles_per_height - 1 &&
						   (!door_top || tile_x != tiles_per_width / 2) {
							tile_value = 2
						}

						at_center :=
							tile_x == tiles_per_width / 2 && tile_y == tiles_per_height / 2

						// Outgoing staircase for this room
						if door_up && at_center {tile_value = 3}
						if door_down && at_center {tile_value = 4}

						// Entrance staircase from the previous z transition:
						// if we came up (last_z_dir==1), this floor has staircase down (4) to go back
						// if we came down (last_z_dir==-1), this floor has staircase up (3) to go back
						if last_was_z_change && at_center {
							if last_z_dir == 1 {
								tile_value = 4
							} else {
								tile_value = 3
							}
						}

						set_tile_value(
							&game_state.world_arena,
							tilemap,
							abs_tile_x,
							abs_tile_y,
							abs_tile_z,
							u32(tile_value),
						)
					}
				}

				last_was_z_change = door_up || door_down
				if door_up {last_z_dir = 1}
				if door_down {last_z_dir = -1}

				door_left = door_right
				door_bottom = door_top
				door_right = false
				door_top = false
				door_up = false
				door_down = false

				if random_choice == 0 {
					screen_x += 1
				} else if random_choice == 1 {
					screen_y += 1
				} else {
					screen_z = next_z
				}
			}
		}

		game_state.bitmap_pointer = debug_load_bmp(
			platform_procedures,
			"data/test/structure_test_art.bmp",
		)

		memory.is_initialized = true
	}

	world := game_state.world
	tilemap := world.tilemap

	tile_side_in_pixels := 60
	meters_to_pixels := f32(tile_side_in_pixels) / tilemap.tile_side_in_meters

	player_height := tilemap.tile_side_in_meters
	player_width := 0.75 * player_height

	for i in 0 ..< MAX_CONTROLLERS {
		controller := &input.controllers[i]
		if !controller.is_analog {
			speed := 10.0 * input.delta_time
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

			// Z transition: trigger once when entering a staircase tile,
			// reset only when the player steps off it (prevents oscillation)
			current_tile := get_tile_value(
				tilemap,
				game_state.player_p.abs_tile_x,
				game_state.player_p.abs_tile_y,
				game_state.player_p.abs_tile_z,
			)
			if !game_state.was_on_staircase {
				if current_tile == 3 &&
				   game_state.player_p.abs_tile_z + 1 < u32(tilemap.tile_chunk_count_z) {
					game_state.player_p.abs_tile_z += 1
					game_state.was_on_staircase = true
				} else if current_tile == 4 && game_state.player_p.abs_tile_z > 0 {
					game_state.player_p.abs_tile_z -= 1
					game_state.was_on_staircase = true
				}
			} else if current_tile != 3 && current_tile != 4 {
				game_state.was_on_staircase = false
			}
		}
	}

	output_sound(sound_buffer, game_state)

	// Background (dark red)
	draw_rectangle(backbuffer, 0, 0, f32(backbuffer.width), f32(backbuffer.height), 1.0, 0.0, 0.1)

	center_x := 0.5 * f32(backbuffer.width)
	center_y := 0.5 * f32(backbuffer.height)


	for rel_row in -100 ..< 100 {
		for rel_col in -200 ..< 200 {
			col := u32(i32(game_state.player_p.abs_tile_x) + i32(rel_col))
			row := u32(i32(game_state.player_p.abs_tile_y) + i32(rel_row))

			tile_id := get_tile_value(tilemap, col, row, game_state.player_p.abs_tile_z)

			if tile_id > 0 {
				gray: f32 = 0.5
				if tile_id == 2 {gray = 1.0} 	// wall
				if tile_id == 3 {gray = 0.3} 	// stair up (darker)
				if tile_id == 4 {gray = 0.7} 	// stair down (lighter)
				if col == game_state.player_p.abs_tile_x && row == game_state.player_p.abs_tile_y {
					gray = 0.0
				}

				min_x :=
					center_x -
					meters_to_pixels * game_state.player_p.tile_rel_x +
					(f32(rel_col) - 0.5) * f32(tile_side_in_pixels)
				min_y :=
					center_y +
					meters_to_pixels * game_state.player_p.tile_rel_y -
					f32(rel_row) * f32(tile_side_in_pixels)
				max_x := min_x + f32(tile_side_in_pixels)
				max_y := min_y - f32(tile_side_in_pixels)
				draw_rectangle(backbuffer, min_x, max_y, max_x, min_y, gray, gray, gray)
			}
		}
	}

	// Player (yellow)
	player_left := center_x - 0.5 * meters_to_pixels * player_width
	player_top := center_y - meters_to_pixels * player_height
	draw_rectangle(
		backbuffer,
		player_left,
		player_top,
		player_left + meters_to_pixels * player_width,
		player_top + meters_to_pixels * player_height,
		1.0,
		1.0,
		0.0,
	)

	when false {
		for y in 0 ..< backbuffer.height {
			for x in 0 ..< backbuffer.width {
				pixel := game_state.bitmap_pointer[y * backbuffer.width + x]
				if pixel != 0 {
					backbuffer.pixels[y * backbuffer.width + x] = pixel
				}
			}
		}
	}
}

when ODIN_DEBUG {
	Bitmap_Header :: struct #packed {
		file_type:         [2]u8,
		file_size:         u32,
		reserved1:         u16,
		reserved2:         u16,
		pixel_data_offset: u32,
		size:              u32,
		width:             i32,
		height:            i32,
		planes:            u16,
		bits_per_pixel:    u16,
	}

	debug_load_bmp :: proc(platform_procedures: Platform_Procedures, filename: string) -> []u32 {
		contents := platform_procedures.read_entire_file(filename)
		header := cast(^Bitmap_Header)raw_data(contents)
		pixels_mp := cast([^]u32)raw_data(contents)[header.pixel_data_offset:]
		pixel_count := header.width * header.height
		pixels := pixels_mp[:pixel_count]
		// TODO: leaking memory here - returning pixels slice that points into a subslice of contents, but contents itself is never freed.
		return pixels
	}
}

when ODIN_DEBUG {
	Platform_Procedures :: struct {
		read_entire_file: proc(name: string) -> []byte,
	}

} else {
	Platform_Procedures :: struct {}
}

when ODIN_DEBUG {
	is_in_permanent_storage :: proc(memory: ^Memory, ptr: rawptr) -> bool {
		base := uintptr(memory.permanent_storage)
		p := uintptr(ptr)
		return p >= base && p < base + uintptr(memory.permanent_storage_size)
	}
}
