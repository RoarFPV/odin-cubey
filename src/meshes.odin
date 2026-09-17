package cubey

import "core:fmt"
import "core:reflect"
import rl "vendor:raylib"

Model :: rl.Model


load_model :: proc(path:cstring) -> Model {
	model := rl.LoadModel(path)

	return model
}