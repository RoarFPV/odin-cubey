package cubey



import "core:c"
import "core:math"
import "core:strings"

import rl "vendor:raylib"
import clay "lib/clay/bindings/odin/clay-odin"

UI_CLAY :: #config(UI_CLAY, false)

when UI_CLAY {
ui :: clay 

state := struct {
	screen_width:    c.int,
	screen_height:   c.int,
	screen_texture:  rl.RenderTexture2D,
} {
	screen_width  = 960,
	screen_height = 540,
}


RaylibFont :: struct {
    fontId: u16,
    font:   rl.Font,
}

raylibFonts := [10]RaylibFont{}
currentPointerState : ui.PointerData


DefaultLayout :: ui.LayoutConfig

ui_colorFromNormal :: proc( color:[4]f32) -> ui.Color {
    return color * 255
}


_errorHandler :: proc "c" (errorData: clay.ErrorData) {
    if (errorData.errorType == clay.ErrorType.DuplicateId) {

    }
}

ui_init :: proc(screen: [2]u32) {

	state.screen_width = rl.GetScreenWidth()
	state.screen_height = rl.GetScreenHeight()

	minMemorySize: c.size_t = cast(c.size_t)clay.MinMemorySize()
    memory := make([^]u8, minMemorySize)
    arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(minMemorySize, memory)
    
    clay.Initialize(arena, {cast(f32)state.screen_width, cast(f32)state.screen_height}, { handler = _errorHandler })
    clay.SetMeasureTextFunction(measure_text_ascii, nil)
    
	ui_load_font(0, 16, "assets/fonts/Michroma-Regular.ttf")
	ui_load_font(1, 16, "assets/fonts/Quicksand-Semibold.ttf")

	state.screen_texture = rl.LoadRenderTexture(state.screen_width, state.screen_height)
}

ui_shudown :: proc() {
	rl.UnloadRenderTexture(state.screen_texture)
}

ui_update_begin :: proc(deltaTime:f32) {
	
	state.screen_width = rl.GetScreenWidth()
	state.screen_height = rl.GetScreenHeight()

	wheel := rl.GetMouseWheelMoveV()
 	mpos := rl.GetMousePosition()
	leftBtn := rl.IsMouseButtonDown(rl.MouseButton.LEFT)

	size : clay.Dimensions = {cast(f32)state.screen_width, cast(f32)state.screen_height}
    clay.SetLayoutDimensions(size)

	clay.SetPointerState(mpos, leftBtn)
    currentPointerState = clay.GetPointerState()
	clay.UpdateScrollContainers(false, wheel , deltaTime)	
	clay.BeginLayout()
}


ui_update_end :: proc (deltaTime: f32) {
    tracy.Zone()
	renderCommands := clay.EndLayout(deltaTime)
	
	clayRaylibRender(&renderCommands)

}

ui_load_font :: proc(fontId: u16, fontSize: u16, path: cstring) {
    raylibFonts[fontId] = RaylibFont {
        font   = rl.LoadFontEx(path, cast(i32)fontSize * 2, nil, 0),
        fontId = cast(u16)fontId,
    }
    rl.SetTextureFilter(raylibFonts[fontId].font.texture, rl.TextureFilter.TRILINEAR)
}

clayColorToRaylibColor :: proc(color: clay.Color) -> rl.Color {
    return rl.Color{cast(u8)color.r, cast(u8)color.g, cast(u8)color.b, cast(u8)color.a}
}

measureText :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, userData:rawptr) -> clay.Dimensions {
    // Measure string size for Font
    
	textSize: clay.Dimensions = {0, 0}

    maxTextWidth: f32 = 0
    lineTextWidth: f32 = 0

    textHeight := cast(f32)config.fontSize
	font := raylibFonts[config.fontId]
    fontToUse := raylibFonts[config.fontId].font

	
	// size := rl.MeasureTextEx(fontToUse, cast(cstring) text.chars, auto_cast fontToUse.baseSize, 1 )

    for i in 0 ..< int(text.length) {
        if (text.chars[i] == '\n') {
            maxTextWidth = max(maxTextWidth, lineTextWidth)
            lineTextWidth = 0
            continue
        }
        index := cast(i32)text.chars[i] - 32
        if (fontToUse.glyphs[index].advanceX != 0) {
            lineTextWidth += cast(f32)fontToUse.glyphs[index].advanceX
        } else {
            lineTextWidth += (fontToUse.recs[index].width + cast(f32)fontToUse.glyphs[index].offsetX)
        }
    }

    maxTextWidth = max(maxTextWidth, lineTextWidth)

    textSize.width = maxTextWidth / 2
    textSize.height = textHeight

    return textSize
}

measure_text_ascii :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, userData: rawptr) -> clay.Dimensions {
	line_width: f32 = 0

	font := raylibFonts[config.fontId].font
	text_str := string(text.chars[:text.length])

	for i in 0 ..< len(text_str) {
		glyph_index := text_str[i] - 32

		glyph := font.glyphs[glyph_index]

		if glyph.advanceX != 0 {
			line_width += f32(glyph.advanceX)
		} else {
			line_width += font.recs[glyph_index].width + f32(font.glyphs[glyph_index].offsetX)
		}
	}

	scaleFactor := f32(config.fontSize) / f32(font.baseSize)

	// Note:
	//   I'd expect this to be `len(text_str) - 1`,
	//   but that seems to be one letterSpacing too small
	//   maybe that's a raylib bug, maybe that's Clay?
	total_spacing := f32(len(text_str)) * f32(config.letterSpacing)

	return {width = line_width * scaleFactor + total_spacing, height = f32(config.fontSize)}
}

clayRaylibRender :: proc(renderCommands: ^clay.ClayArray(clay.RenderCommand), allocator := context.temp_allocator) {
    overlay_colors := make([dynamic]clay.Color, allocator)
    for i in 0 ..< int(renderCommands.length) {
        renderCommand := clay.RenderCommandArray_Get(renderCommands, cast(i32)i)
        boundingBox := renderCommand.boundingBox

        switch (renderCommand.commandType) {
        case .None:
        case .Text:
            config := renderCommand.renderData.text
            // Raylib uses standard C strings so isn't compatible with cheap slices, we need to clone the string to append null terminator
            text := string(config.stringContents.chars[:config.stringContents.length])
            cloned := strings.clone_to_cstring(text, allocator)
            fontToUse: rl.Font = raylibFonts[config.fontId].font
            rl.DrawTextEx(
                fontToUse,
                cloned,
                rl.Vector2{boundingBox.x, boundingBox.y},
                 f32(config.fontSize), f32(config.letterSpacing),
                clayColorToRaylibColor(config.textColor),
            )
        case .Image:
            config := renderCommand.renderData.image
			tint: clay.Color
			if len(overlay_colors) > 0 {
				tint = overlay_colors[len(overlay_colors) - 1]
			}
			if tint == 0 {
				tint = {255, 255, 255, 255}
			}

			imageTexture := (^rl.Texture2D)(config.imageData)
            rl.DrawTextureEx(imageTexture^, rl.Vector2{boundingBox.x, boundingBox.y}, 0, boundingBox.width / cast(f32)imageTexture.width, rl.WHITE)
        case .ScissorStart:
            rl.BeginScissorMode(
                cast(i32)math.round(boundingBox.x),
                cast(i32)math.round(boundingBox.y),
                cast(i32)math.round(boundingBox.width),
                cast(i32)math.round(boundingBox.height),
            )
        case .ScissorEnd:
            rl.EndScissorMode()
        case .Rectangle:
            config := renderCommand.renderData.rectangle
            if (config.cornerRadius.topLeft > 0) {
                radius: f32 = (config.cornerRadius.topLeft * 2) / min(boundingBox.width, boundingBox.height)
                rl.DrawRectangleRounded(rl.Rectangle{boundingBox.x, boundingBox.y, boundingBox.width, boundingBox.height}, radius, 8, clayColorToRaylibColor(config.backgroundColor))
            } else {
                rl.DrawRectangle(cast(i32)boundingBox.x, cast(i32)boundingBox.y, cast(i32)boundingBox.width, cast(i32)boundingBox.height, clayColorToRaylibColor(config.backgroundColor))
            }

        case .Border:
            config := renderCommand.renderData.border
            // Left border
            if (config.width.left > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x),
                    cast(i32)math.round(boundingBox.y + config.cornerRadius.topLeft),
                    cast(i32)config.width.left,
                    cast(i32)math.round(boundingBox.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft),
                    clayColorToRaylibColor(config.color),
                )
            }
            // Right border
            if (config.width.right > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + boundingBox.width - cast(f32)config.width.right),
                    cast(i32)math.round(boundingBox.y + config.cornerRadius.topRight),
                    cast(i32)config.width.right,
                    cast(i32)math.round(boundingBox.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight),
                    clayColorToRaylibColor(config.color),
                )
            }
            // Top border
            if (config.width.top > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + config.cornerRadius.topLeft),
                    cast(i32)math.round(boundingBox.y),
                    cast(i32)math.round(boundingBox.width - config.cornerRadius.topLeft - config.cornerRadius.topRight),
                    cast(i32)config.width.top,
                    clayColorToRaylibColor(config.color),
                )
            }
            // Bottom border
            if (config.width.bottom > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + config.cornerRadius.bottomLeft),
                    cast(i32)math.round(boundingBox.y + boundingBox.height - cast(f32)config.width.bottom),
                    cast(i32)math.round(boundingBox.width - config.cornerRadius.bottomLeft - config.cornerRadius.bottomRight),
                    cast(i32)config.width.bottom,
                    clayColorToRaylibColor(config.color),
                )
            }
            if (config.cornerRadius.topLeft > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + config.cornerRadius.topLeft), math.round(boundingBox.y + config.cornerRadius.topLeft)},
                    math.round(config.cornerRadius.topLeft - cast(f32)config.width.top),
                    config.cornerRadius.topLeft,
                    180,
                    270,
                    10,
                    clayColorToRaylibColor(config.color),
                )
            }
            if (config.cornerRadius.topRight > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + boundingBox.width - config.cornerRadius.topRight), math.round(boundingBox.y + config.cornerRadius.topRight)},
                    math.round(f32(config.cornerRadius.topRight) - f32(config.width.top)),
                    config.cornerRadius.topRight,
                    270,
                    360,
                    10,
                    clayColorToRaylibColor(config.color),
                )
            }
            if (config.cornerRadius.bottomLeft > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + config.cornerRadius.bottomLeft), math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomLeft)},
                    math.round(config.cornerRadius.bottomLeft - cast(f32)config.width.top),
                    config.cornerRadius.bottomLeft,
                    90,
                    180,
                    10,
                    clayColorToRaylibColor(config.color),
                )
            }
            if (config.cornerRadius.bottomRight > 0) {
                rl.DrawRing(
                    rl.Vector2 {
                        math.round(boundingBox.x + boundingBox.width - config.cornerRadius.bottomRight),
                        math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomRight),
                    },
                    math.round(config.cornerRadius.bottomRight - cast(f32)config.width.bottom),
                    config.cornerRadius.bottomRight,
                    0.1,
                    90,
                    10,
                    clayColorToRaylibColor(config.color),
                )
            }
        case .OverlayColorStart:
			config := renderCommand.renderData.overlayColor
			append(&overlay_colors, config.color)
		case .OverlayColorEnd:
			pop(&overlay_colors)
		case .Custom:
        // Implement custom element rendering here
        }
    }
}




// style->WindowPadding = ImVec2(15, 15);
// style->WindowRounding = 5.0f;
// style->FramePadding = ImVec2(5, 5);
// style->FrameRounding = 4.0f;
// style->ItemSpacing = ImVec2(12, 8);
// style->ItemInnerSpacing = ImVec2(8, 6);
// style->IndentSpacing = 25.0f;
// style->ScrollbarSize = 15.0f;
// style->ScrollbarRounding = 9.0f;
// style->GrabMinSize = 5.0f;
// style->GrabRounding = 3.0f;

// Text                  0.80 0.80 0.83 1.00
// TextDisabled          0.24 0.23 0.29 1.00
// WindowBg              0.06 0.05 0.07 1.00
// ChildWindowBg         0.07 0.07 0.09 1.00
// PopupBg               0.07 0.07 0.09 1.00
// Border                0.80 0.80 0.83 0.88
// BorderShadow          0.92 0.91 0.88 0.00
// FrameBg               0.10 0.09 0.12 1.00
// FrameBgHovered        0.24 0.23 0.29 1.00
// FrameBgActive         0.56 0.56 0.58 1.00
// TitleBg               0.10 0.09 0.12 1.00
// TitleBgCollapsed      1.00 0.98 0.95 0.75
// TitleBgActive         0.07 0.07 0.09 1.00
// MenuBarBg             0.10 0.09 0.12 1.00
// ScrollbarBg           0.10 0.09 0.12 1.00
// ScrollbarGrab         0.80 0.80 0.83 0.31
// ScrollbarGrabHovered  0.56 0.56 0.58 1.00
// ScrollbarGrabActive   0.06 0.05 0.07 1.00
// ComboBg               0.19 0.18 0.21 1.00
// CheckMark             0.80 0.80 0.83 0.31
// SliderGrab            0.80 0.80 0.83 0.31
// SliderGrabActive      0.06 0.05 0.07 1.00
// Button                0.10 0.09 0.12 1.00
// ButtonHovered         0.24 0.23 0.29 1.00
// ButtonActive          0.56 0.56 0.58 1.00
// Header                0.10 0.09 0.12 1.00
// HeaderHovered         0.56 0.56 0.58 1.00
// HeaderActive          0.06 0.05 0.07 1.00
// Column                0.56 0.56 0.58 1.00
// ColumnHovered         0.24 0.23 0.29 1.00
// ColumnActive          0.56 0.56 0.58 1.00
// ResizeGrip            0.00 0.00 0.00 0.00
// ResizeGripHovered     0.56 0.56 0.58 1.00
// ResizeGripActive      0.06 0.05 0.07 1.00
// CloseButton           0.40 0.39 0.38 0.16
// CloseButtonHovered    0.40 0.39 0.38 0.39
// CloseButtonActive     0.40 0.39 0.38 1.00
// PlotLines             0.40 0.39 0.38 0.63
// PlotLinesHovered      0.25 1.00 0.00 1.00
// PlotHistogram         0.40 0.39 0.38 0.63
// PlotHistogramHovered  0.25 1.00 0.00 1.00
// TextSelectedBg        0.25 1.00 0.00 0.43
// ModalWindowDarkening  1.00 0.98 0.95 0.73



// [data-bs-theme=dark] {
//     color-scheme: dark;
//     --ct-body-color: #aab8c5;
//     --ct-body-color-rgb: 170, 184, 197;
//     --ct-body-bg: #343a40;
//     --ct-body-bg-rgb: 52, 58, 64;
//     --ct-emphasis-color: #dee2e6;
//     --ct-emphasis-color-rgb: 222, 226, 230;
//     --ct-secondary-color: #8391a2;
//     --ct-secondary-color-rgb: 131, 145, 162;
//     --ct-secondary-bg: #37404a;
//     --ct-secondary-bg-rgb: 55, 64, 74;
//     --ct-tertiary-color: #f1f1f1;
//     --ct-tertiary-color-rgb: 241, 241, 241;
//     --ct-tertiary-bg: #404954;
//     --ct-tertiary-bg-rgb: 64, 73, 84;
//     --ct-primary-text-emphasis: rgb(170.4, 176.4, 249);
//     --ct-secondary-text-emphasis: #dee2e6;
//     --ct-success-text-emphasis: rgb(108, 226.2, 192.6);
//     --ct-info-text-emphasis: rgb(136.2, 207, 227.4);
//     --ct-warning-text-emphasis: #ffdb9c;
//     --ct-danger-text-emphasis: rgb(252, 157.2, 176.4);
//     --ct-light-text-emphasis: #f6f7fb;
//     --ct-dark-text-emphasis: #dee2e6;
//     --ct-primary-bg-subtle: rgba(var(--ct-primary-rgb), .15);
//     --ct-secondary-bg-subtle: rgba(108, 117, 125, .15);
//     --ct-success-bg-subtle: rgba(var(--ct-success-rgb), .15);
//     --ct-info-bg-subtle: rgba(var(--ct-info-rgb), .15);
//     --ct-warning-bg-subtle: rgba(var(--ct-warning-rgb), .15);
//     --ct-danger-bg-subtle: rgba(var(--ct-danger-rgb), .15);
//     --ct-light-bg-subtle: rgba(var(--ct-light-rgb), .15);
//     --ct-dark-bg-subtle: rgba(var(--ct-dark-rgb), .15);
//     --ct-primary-border-subtle: rgb(68.4, 74.4, 147);
//     --ct-secondary-border-subtle: #6c757d;
//     --ct-success-border-subtle: rgb(6, 124.2, 90.6);
//     --ct-info-border-subtle: rgb(34.2, 105, 125.4);
//     --ct-warning-border-subtle: #997536;
//     --ct-danger-border-subtle: rgb(150, 55.2, 74.4);
//     --ct-light-border-subtle: #6c757d;
//     --ct-dark-border-subtle: #343a40;
//     --ct-heading-color: #aab8c5;
//     --ct-link-color: rgb(170.4, 176.4, 249);
//     --ct-link-hover-color: rgb(183.09, 188.19, 249.9);
//     --ct-link-color-rgb: 170, 176, 249;
//     --ct-link-hover-color-rgb: 183, 188, 250;
//     --ct-code-color: rgb(136.2, 207, 227.4);
//     --ct-highlight-color: #dee2e6;
//     --ct-highlight-bg: rgb(102, 77.2, 2.8);
//     --ct-border-color: #464f5b;
//     --ct-border-color-translucent: #8391a2;
//     --ct-form-valid-color: rgb(108, 226.2, 192.6);
//     --ct-form-valid-border-color: rgb(108, 226.2, 192.6);
//     --ct-form-invalid-color: rgb(252, 157.2, 176.4);
//     --ct-form-invalid-border-color: rgb(252, 157.2, 176.4)
// }

}