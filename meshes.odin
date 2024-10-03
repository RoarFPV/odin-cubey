package cubey

mesh_triangle := Mesh {
	// verticies = {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}}, // flat top
	// verticies = {{0, 0, 0}, {0, 1, 0}, {1, 0, 0}}, // flat bottom
	verticies = {{0, 0, 0}, {1, 1, 0}, {1, -1, 0}}, // both
	indicies  = {0, 1, 2},
	colors    = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
}

mesh_cube := Mesh {
	verticies = {
		{0, 0, 0},
		{0, 1, 0},
		{1, 0, 0},
		{1, 1, 0},
		{0, 0, 1},
		{0, 1, 1},
		{1, 0, 1},
		{1, 1, 1},
	},
	colors    = {
		{1, 0, 0},
		{0, 1, 0},
		{0, 0, 1},
		{1, 0, 0},
		{0, 1, 0},
		{0, 0, 1},
		{1, 0, 0},
		{0, 1, 0},
	},
	indicies  = {
		4,
		2,
		0,
		2,
		7,
		3,
		6,
		5,
		7,
		1,
		7,
		5,
		0,
		3,
		1,
		4,
		1,
		5,
		4,
		6,
		2,
		2,
		6,
		7,
		6,
		4,
		5,
		1,
		3,
		7,
		0,
		2,
		3,
		4,
		0,
		1,
	},
}