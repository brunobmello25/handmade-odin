package game

import "core:log"

MAX_CONTROLLERS :: 4

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

update_and_render :: proc(backbuffer: Backbuffer, input: ^Input) {
	for i in 0 ..< MAX_CONTROLLERS {
		if input.controllers[i].move_up.ended_down {
			log.debugf("Controller %d: move up is pressed", i)
		}
	}

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
