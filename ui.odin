package cubey


import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"

import rl "vendor:raylib"
import clay "lib/clay-odin"

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


ui_init :: proc(screen: [2]u32) {

	state.screen_width = rl.GetScreenWidth()
	state.screen_height = rl.GetScreenHeight()

	minMemorySize: u32 = clay.MinMemorySize()
    memory := make([^]u8, minMemorySize)
    arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(minMemorySize, memory)
    clay.SetMeasureTextFunction(measureText)
    clay.Initialize(arena, {cast(f32)state.screen_width, cast(f32)state.screen_height})

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

	// clay.SetDebugModeEnabled(true)

	clay.SetPointerState(mpos, leftBtn)
	clay.UpdateScrollContainers(false, wheel , deltaTime)

	clay.SetLayoutDimensions(size)
	// animValue := animationLerpValue < 0 ? (animationLerpValue + 1) : (1 - animationLerpValue)
	
	clay.BeginLayout()
}


ui_update_end :: proc () {

	renderCommands := clay.EndLayout()
	
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

measureText :: proc "c" (text: ^clay.String, config: ^clay.TextElementConfig) -> clay.Dimensions {
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

clayRaylibRender :: proc(renderCommands: ^clay.ClayArray(clay.RenderCommand), allocator := context.temp_allocator) {
    for i in 0 ..< int(renderCommands.length) {
        renderCommand := clay.RenderCommandArray_Get(renderCommands, cast(i32)i)
        boundingBox := renderCommand.boundingBox
        switch (renderCommand.commandType) {
        case clay.RenderCommandType.None:
            {}
        case clay.RenderCommandType.Text:
            // Raylib uses standard C strings so isn't compatible with cheap slices, we need to clone the string to append null terminator
            text := string(renderCommand.text.chars[:renderCommand.text.length])
            cloned := strings.clone_to_cstring(text, allocator)
            fontToUse: rl.Font = raylibFonts[renderCommand.config.textElementConfig.fontId].font
            rl.DrawTextEx(
                fontToUse,
                cloned,
                rl.Vector2{boundingBox.x, boundingBox.y},
                cast(f32)renderCommand.config.textElementConfig.fontSize,
                cast(f32)renderCommand.config.textElementConfig.letterSpacing,
                clayColorToRaylibColor(renderCommand.config.textElementConfig.textColor),
            )
        case clay.RenderCommandType.Image:
            // TODO image handling
            imageTexture := cast(^rl.Texture2D)renderCommand.config.imageElementConfig.imageData
            rl.DrawTextureEx(imageTexture^, rl.Vector2{boundingBox.x, boundingBox.y}, 0, boundingBox.width / cast(f32)imageTexture.width, rl.WHITE)
        case clay.RenderCommandType.ScissorStart:
            rl.BeginScissorMode(
                cast(i32)math.round(boundingBox.x),
                cast(i32)math.round(boundingBox.y),
                cast(i32)math.round(boundingBox.width),
                cast(i32)math.round(boundingBox.height),
            )
        case clay.RenderCommandType.ScissorEnd:
            rl.EndScissorMode()
        case clay.RenderCommandType.Rectangle:
            config: ^clay.RectangleElementConfig = renderCommand.config.rectangleElementConfig
            if (config.cornerRadius.topLeft > 0) {
                radius: f32 = (config.cornerRadius.topLeft * 2) / min(boundingBox.width, boundingBox.height)
                rl.DrawRectangleRounded(rl.Rectangle{boundingBox.x, boundingBox.y, boundingBox.width, boundingBox.height}, radius, 8, clayColorToRaylibColor(config.color))
            } else {
                rl.DrawRectangle(cast(i32)boundingBox.x, cast(i32)boundingBox.y, cast(i32)boundingBox.width, cast(i32)boundingBox.height, clayColorToRaylibColor(config.color))
            }
        case clay.RenderCommandType.Border:
            config := renderCommand.config.borderElementConfig
            // Left border
            if (config.left.width > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x),
                    cast(i32)math.round(boundingBox.y + config.cornerRadius.topLeft),
                    cast(i32)config.left.width,
                    cast(i32)math.round(boundingBox.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft),
                    clayColorToRaylibColor(config.left.color),
                )
            }
            // Right border
            if (config.right.width > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + boundingBox.width - cast(f32)config.right.width),
                    cast(i32)math.round(boundingBox.y + config.cornerRadius.topRight),
                    cast(i32)config.right.width,
                    cast(i32)math.round(boundingBox.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight),
                    clayColorToRaylibColor(config.right.color),
                )
            }
            // Top border
            if (config.top.width > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + config.cornerRadius.topLeft),
                    cast(i32)math.round(boundingBox.y),
                    cast(i32)math.round(boundingBox.width - config.cornerRadius.topLeft - config.cornerRadius.topRight),
                    cast(i32)config.top.width,
                    clayColorToRaylibColor(config.top.color),
                )
            }
            // Bottom border
            if (config.bottom.width > 0) {
                rl.DrawRectangle(
                    cast(i32)math.round(boundingBox.x + config.cornerRadius.bottomLeft),
                    cast(i32)math.round(boundingBox.y + boundingBox.height - cast(f32)config.bottom.width),
                    cast(i32)math.round(boundingBox.width - config.cornerRadius.bottomLeft - config.cornerRadius.bottomRight),
                    cast(i32)config.bottom.width,
                    clayColorToRaylibColor(config.bottom.color),
                )
            }
            if (config.cornerRadius.topLeft > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + config.cornerRadius.topLeft), math.round(boundingBox.y + config.cornerRadius.topLeft)},
                    math.round(config.cornerRadius.topLeft - cast(f32)config.top.width),
                    config.cornerRadius.topLeft,
                    180,
                    270,
                    10,
                    clayColorToRaylibColor(config.top.color),
                )
            }
            if (config.cornerRadius.topRight > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + boundingBox.width - config.cornerRadius.topRight), math.round(boundingBox.y + config.cornerRadius.topRight)},
                    math.round(config.cornerRadius.topRight - cast(f32)config.top.width),
                    config.cornerRadius.topRight,
                    270,
                    360,
                    10,
                    clayColorToRaylibColor(config.top.color),
                )
            }
            if (config.cornerRadius.bottomLeft > 0) {
                rl.DrawRing(
                    rl.Vector2{math.round(boundingBox.x + config.cornerRadius.bottomLeft), math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomLeft)},
                    math.round(config.cornerRadius.bottomLeft - cast(f32)config.top.width),
                    config.cornerRadius.bottomLeft,
                    90,
                    180,
                    10,
                    clayColorToRaylibColor(config.bottom.color),
                )
            }
            if (config.cornerRadius.bottomRight > 0) {
                rl.DrawRing(
                    rl.Vector2 {
                        math.round(boundingBox.x + boundingBox.width - config.cornerRadius.bottomRight),
                        math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomRight),
                    },
                    math.round(config.cornerRadius.bottomRight - cast(f32)config.bottom.width),
                    config.cornerRadius.bottomRight,
                    0.1,
                    90,
                    10,
                    clayColorToRaylibColor(config.bottom.color),
                )
            }
        case clay.RenderCommandType.Custom:
        // Implement custom element rendering here
        }
    }
}

