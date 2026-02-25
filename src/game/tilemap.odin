package game

Tilemap :: struct {
	chunk_shift:         u32,
	chunk_mask:          u32,
	chunk_size:          u32,
	tile_side_in_meters: f32,
	tile_side_in_pixels: i32,
	meters_to_pixels:    f32,
	tile_chunk_count_x:  i32,
	tile_chunk_count_y:  i32,
	tile_chunks:         []Tilemap_Chunk,
}

Tilemap_Position :: struct {
	abs_tile_x: u32,
	abs_tile_y: u32,
	tile_rel_x: f32,
	tile_rel_y: f32,
}

Tilemap_Chunk_Position :: struct {
	tile_chunk_x: u32,
	tile_chunk_y: u32,
	rel_tile_x:   u32,
	rel_tile_y:   u32,
}

Tilemap_Chunk :: struct {
	tiles: []u32,
}

get_chunk_position_for :: proc(
	tilemap: ^Tilemap,
	abs_tile_x, abs_tile_y: u32,
) -> Tilemap_Chunk_Position {
	return Tilemap_Chunk_Position {
		tile_chunk_x = abs_tile_x >> tilemap.chunk_shift,
		tile_chunk_y = abs_tile_y >> tilemap.chunk_shift,
		rel_tile_x = abs_tile_x & tilemap.chunk_mask,
		rel_tile_y = abs_tile_y & tilemap.chunk_mask,
	}
}

get_tile_chunk :: proc(tilemap: ^Tilemap, chunk_x, chunk_y: u32) -> ^Tilemap_Chunk {
	if chunk_x >= u32(tilemap.tile_chunk_count_x) || chunk_y >= u32(tilemap.tile_chunk_count_y) {
		return nil
	}
	return &tilemap.tile_chunks[chunk_y * u32(tilemap.tile_chunk_count_x) + chunk_x]
}

get_tile_value_unchecked :: proc(
	tilemap: ^Tilemap,
	chunk: ^Tilemap_Chunk,
	tile_x, tile_y: u32,
) -> u32 {
	assert(chunk != nil)
	assert(tile_x < tilemap.chunk_size)
	assert(tile_y < tilemap.chunk_size)
	return chunk.tiles[tile_y * tilemap.chunk_size + tile_x]
}

get_tile_value_from_chunk :: proc(
	tilemap: ^Tilemap,
	chunk: ^Tilemap_Chunk,
	tile_x, tile_y: u32,
) -> u32 {
	if chunk == nil || tile_x >= tilemap.chunk_size || tile_y >= tilemap.chunk_size {
		return 0
	}
	return get_tile_value_unchecked(tilemap, chunk, tile_x, tile_y)
}

get_tile_value :: proc(tilemap: ^Tilemap, abs_tile_x, abs_tile_y: u32) -> u32 {
	chunk_pos := get_chunk_position_for(tilemap, abs_tile_x, abs_tile_y)
	chunk := get_tile_chunk(tilemap, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y)
	return get_tile_value_from_chunk(tilemap, chunk, chunk_pos.rel_tile_x, chunk_pos.rel_tile_y)
}

set_tile_value :: proc(tilemap: ^Tilemap, abs_tile_x, abs_tile_y: u32, value: u32) {
	chunk_pos := get_chunk_position_for(tilemap, abs_tile_x, abs_tile_y)
	chunk := get_tile_chunk(tilemap, chunk_pos.tile_chunk_x, chunk_pos.tile_chunk_y)

	assert(chunk != nil)
	assert(chunk_pos.rel_tile_x < tilemap.chunk_size)
	assert(chunk_pos.rel_tile_y < tilemap.chunk_size)
	assert(chunk_pos.tile_chunk_x < u32(tilemap.tile_chunk_count_x))
	assert(chunk_pos.tile_chunk_y < u32(tilemap.tile_chunk_count_y))

	chunk.tiles[chunk_pos.rel_tile_y * tilemap.chunk_size + chunk_pos.rel_tile_x] = value
}

is_world_point_empty :: proc(tilemap: ^Tilemap, pos: Tilemap_Position) -> bool {
	return get_tile_value(tilemap, pos.abs_tile_x, pos.abs_tile_y) == 1
}
