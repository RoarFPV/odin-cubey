package cubey


import "core:c"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

import rl "vendor:raylib"
import mu "vendor:microui"


@private
state := struct {
	screen_width:    c.int,
	screen_height:   c.int,
	screen_texture:  rl.RenderTexture2D,
    atlas_texture:   rl.RenderTexture2D,
    ctx:          mu.Context,

	mouse_pos : vec2,
	mouse_pos_delta: vec2,
} {
	screen_width  = 960,
	screen_height = 540,
}

RaylibFont :: struct {
    fontId: u16,
    font:   rl.Font,
}

raylibFonts := [10]RaylibFont{}
// currentPointerState : ui.PointerData

mouse_buttons_map := [mu.Mouse]rl.MouseButton{
	.LEFT    = .LEFT,
	.RIGHT   = .RIGHT,
	.MIDDLE  = .MIDDLE,
}

key_map := [mu.Key][2]rl.KeyboardKey{
	.SHIFT     = {.LEFT_SHIFT,   .RIGHT_SHIFT},
	.CTRL      = {.LEFT_CONTROL, .RIGHT_CONTROL},
	.ALT       = {.LEFT_ALT,     .RIGHT_ALT},
	.BACKSPACE = {.BACKSPACE,    .KEY_NULL},
	.DELETE    = {.DELETE,       .KEY_NULL},
	.RETURN    = {.ENTER,        .KP_ENTER},
	.LEFT      = {.LEFT,         .KEY_NULL},
	.RIGHT     = {.RIGHT,        .KEY_NULL},
	.HOME      = {.HOME,         .KEY_NULL},
	.END       = {.END,          .KEY_NULL},
	.A         = {.A,            .KEY_NULL},
	.X         = {.X,            .KEY_NULL},
	.C         = {.C,            .KEY_NULL},
	.V         = {.V,            .KEY_NULL},
}

// ui_colorFromNormal :: proc( color:[4]f32) -> ui.Color {
//     return color * 255
// }
ui_ctx := &state.ctx

ui_init :: proc(screen: [2]u32) {

	state.screen_width = rl.GetScreenWidth()
	state.screen_height = rl.GetScreenHeight()

	ctx := &state.ctx

    

	mu.init(ctx,
		set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
			cstr := strings.clone_to_cstring(text)
			rl.SetClipboardText(cstr)
			delete(cstr)
			return true
		},
		get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
			cstr := rl.GetClipboardText()
			if cstr != nil {
				text = string(cstr)
				ok = true
			}
			return
		},
	)

    ctx.style.indent = 5
	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	state.atlas_texture = rl.LoadRenderTexture(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT))

	image := rl.GenImageColor(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})
	defer rl.UnloadImage(image)

	for alpha, i in mu.default_atlas_alpha {
		x := i % mu.DEFAULT_ATLAS_WIDTH
		y := i / mu.DEFAULT_ATLAS_WIDTH
		color := rl.Color{255, 255, 255, alpha}
		rl.ImageDrawPixel(&image, c.int(x), c.int(y), color)
	}

	rl.BeginTextureMode(state.atlas_texture)
	rl.UpdateTexture(state.atlas_texture.texture, rl.LoadImageColors(image))
	rl.EndTextureMode()
    
	ui_load_font(0, 16, "assets/fonts/Michroma-Regular.ttf")
	ui_load_font(1, 16, "assets/fonts/Quicksand-Semibold.ttf")

	state.screen_texture = rl.LoadRenderTexture(state.screen_width, state.screen_height)
}

ui_shudown :: proc() {
	rl.UnloadRenderTexture(state.screen_texture)
	rl.UnloadRenderTexture(state.atlas_texture)
}

ui_mouse_position :: proc "contextless" () -> vec2 {
	return state.mouse_pos
}

ui_mouse_position_delta :: proc "contextless" () -> vec2 {
	return state.mouse_pos_delta
}

ui_update_begin :: proc(deltaTime:f32) {
	
	state.screen_width = rl.GetScreenWidth()
	state.screen_height = rl.GetScreenHeight()

	wheel := rl.GetMouseWheelMoveV()*10
 	mpos := rl.GetMousePosition()
	leftBtn := rl.IsMouseButtonDown(rl.MouseButton.LEFT)

	state.mouse_pos_delta = mpos - state.mouse_pos
	state.mouse_pos = mpos


	mu.input_mouse_move(&state.ctx, auto_cast mpos.x, auto_cast mpos.y)
    mu.input_scroll(&state.ctx, auto_cast wheel.x, auto_cast wheel.y)


    for button_rl, button_mu in mouse_buttons_map {
			switch {
			case rl.IsMouseButtonPressed(button_rl):
				mu.input_mouse_down(&state.ctx, auto_cast mpos.x, auto_cast mpos.y, button_mu)
			case rl.IsMouseButtonReleased(button_rl):
				mu.input_mouse_up  (&state.ctx, auto_cast mpos.x, auto_cast mpos.y, button_mu)
			}
		}

		for keys_rl, key_mu in key_map {
			for key_rl in keys_rl {
				switch {
				case key_rl == .KEY_NULL:
					// ignore
				case rl.IsKeyPressed(key_rl), rl.IsKeyPressedRepeat(key_rl):
					mu.input_key_down(&state.ctx, key_mu)
				case rl.IsKeyReleased(key_rl):
					mu.input_key_up  (&state.ctx, key_mu)
				}
			}
		}

		{
			buf: [512]byte
			n: int
			for n < len(buf) {
				c := rl.GetCharPressed()
				if c == 0 {
					break
				}
				b, w := utf8.encode_rune(c)
				n += copy(buf[n:], b[:w])
			}
			mu.input_text(&state.ctx, string(buf[:n]))
		}


    mu.begin(&state.ctx)
}


ui_update_end :: proc (deltaTime: f32) {
    tracy.Zone()

    mu.end(&state.ctx)
    render(&state.ctx)
}

ui_load_font :: proc(fontId: u16, fontSize: u16, path: cstring) {
    raylibFonts[fontId] = RaylibFont {
        font   = rl.LoadFontEx(path, cast(i32)fontSize * 2, nil, 0),
        fontId = cast(u16)fontId,
    }
    rl.SetTextureFilter(raylibFonts[fontId].font.texture, rl.TextureFilter.TRILINEAR)
}

@private
render :: proc "contextless" (ctx: ^mu.Context) {
	render_texture :: proc "contextless" (dst: ^rl.Rectangle, src: mu.Rect, color: rl.Color) {
		dst.width = f32(src.w)
		dst.height = f32(src.h)

		rl.DrawTextureRec(
			texture  = state.atlas_texture.texture,
			source   = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint     = color,
		)
	}

	to_rl_color :: proc "contextless" (in_color: mu.Color) -> (out_color: rl.Color) {
		return {in_color.r, in_color.g, in_color.b, in_color.a}
	}

	height := rl.GetScreenHeight()

	rl.EndScissorMode()

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) 
    {
		switch cmd in variant 
        {
		case ^mu.Command_Text:
			dst := rl.Rectangle{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str 
            {
				if ch&0xc0 != 0x80 
                {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(&dst, src, to_rl_color(cmd.color))
					dst.x += dst.width
				}
			}
        case ^mu.Command_Image:
            imageTexture := (^rl.Texture2D)(cmd.framebuffer)
            rl.DrawTextureEx(
				imageTexture^, 
				rl.Vector2{auto_cast cmd.rect.x, auto_cast cmd.rect.y}, 0,  
				f32(cmd.rect.w) / cast(f32)imageTexture.width, to_rl_color(cmd.color))

		case ^mu.Command_Rect:
			rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, to_rl_color(cmd.color))
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w)/2
			y := cmd.rect.y + (cmd.rect.h - src.h)/2
			render_texture(&rl.Rectangle {f32(x), f32(y), 0, 0}, src, to_rl_color(cmd.color))
		case ^mu.Command_Clip:
			rl.BeginScissorMode(cmd.rect.x, height - (cmd.rect.y + cmd.rect.h), cmd.rect.w, cmd.rect.h)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
}
