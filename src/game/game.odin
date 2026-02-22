package game

Backbuffer :: struct {
	width, height: i32,
	pixels:        []u32,
}

update_and_render :: proc(backbuffer: Backbuffer) {
	render_weird_gradient(backbuffer)
}

render_weird_gradient :: proc(backbuffer: Backbuffer) {
	for y in 0 ..< backbuffer.height {
		for x in 0 ..< backbuffer.width {
			blue := u32(x)
			green := u32(y)
			backbuffer.pixels[y * backbuffer.width + x] = (0xFF << 24) | (green << 8) | blue
		}
	}
}
