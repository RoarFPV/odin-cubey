package cubey

import "core:fmt"
import "core:reflect"
import "vendor:cgltf"

mesh_triangle := Mesh {
	// verticies = {{0, 0, 0}, {0, 1, 0}, {1, 1, 0}}, // flat top
	// verticies = {{0, 0, 0}, {0, 1, 0}, {1, 0, 0}}, // flat bottom
	verticies = {{0, 0, 0}, {1, 1, 0}, {1, -1, 0}}, // both
	indicies  = {0, 1, 2},
	colors    = {{1, 0, 0}, {0, 1, 0}, {0, 0, 1}},
	uvs       = {{0, 1, 0}, {1, 1, 0}, {1, 0, 0}},
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
	uvs       = {
		{0, 1, 0},
		{0, 1, 0},
		{1, 0, 0},
		{1, 1, 0},
		{0, 1, 0},
		{0, 1, 0},
		{1, 0, 0},
		{1, 1, 0},
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


// test_cgltf_load :: proc() {
// 	options: cgltf.options

// 	data, result := cgltf.parse_file(options, "assets/models/BoxTextured/glTF/BoxTextured.gltf")
// 	if result != .success {
// 		/* TODO handle error */
// 		// fmt.error()		
// 		return
// 	}

// 	for node in data.nodes {
// 		fmt.println(node.name)
// 		for child in node.children {
// 			mat := child.matrix_
// 			fmt.printfln("  - {}, {}, mesh: {}", child.name, mat, child.mesh.name)

// 			mesh := child.mesh

// 			for prim in mesh.primitives {
// 				fmt.printfln("    - {}", prim.type)


// 				for attr in prim.attributes {

// 					data := attr.data
// 					fmt.printfln("      - {}:{}:[{}]", attr.type, attr.name, attr.index)
// 					fmt.printfln(
// 						"        - data:{}:{}:{}",
// 						data.name,
// 						data.component_type,
// 						data.type,
// 					)
// 					fmt.printfln("          offset:{}", data.offset)
// 					fmt.printfln("          count:{}", data.count)
// 					fmt.printfln("          stride:{}", data.stride)

// 				}
// 			}


// 		}
// 	}

// 	defer cgltf.free(data)
	
// }

// cgltf_show_ui :: proc(data:^cgltf.data) {
// 	im.BeginTable("Nodes", 2,  
// 		im.TableFlags_BordersV | 
// 		im.TableFlags_BordersOuterH | 
// 		im.TableFlags_Resizable | 
// 		im.TableFlags_RowBg | 
// 		im.TableFlags_NoBordersInBody
// 	)

// 	im.TableSetupColumn("Name", {.NoHide})
// 	im.TableSetupColumn("Children", {.WidthFixed}, 12)
// 	// im.TableSetupColumn("Type", {.WidthFixed}, 18)
// 	im.TableHeadersRow()

// 	for &node in data.nodes {
// 		draw_node(&node)
// 	}

// 	im.EndTable()
// }

// draw_node_children :: proc(node:^cgltf.node)
// {
// 	count := len(node.children)
// 	node_flags : im.TreeNodeFlags = {.SpanAllColumns}

// 	if count <= 0 {
// 		return	
// 	}

// 	im.TableNextRow()
// 	im.TableNextColumn()

// 	open := im.TreeNodeExPtr(rawptr(&node.children), node_flags, "children")
// 	im.TableNextColumn()
// 	im.Text("%d", count)

// 	t := type_info_of(type_of(node))
	

// 	if open {		
// 		for &child in node.children {
// 			draw_node(child)
// 		}
// 		im.TreePop()
// 	}
// }

// draw_node :: proc(node:^cgltf.node)
// {


// 	im.TableNextRow()
// 	im.TableNextColumn()

// 	count := len(node.children)
// 	node_flags : im.TreeNodeFlags = {.SpanAllColumns}

// 	if count <= 0 {
// 		node_flags |= {.Leaf, .Bullet}
// 	}

// 	name := node.mesh != nil ? node.mesh.name : "n" //node.name

// 	open := im.TreeNodeExPtr(node, node_flags, name)
// 	im.TableNextColumn()
// 	im.Text("%d", count)
// 	if open {

// 		draw_node_children(node)
// 		im.TreePop()
// 	}
// }


// draw_editor_value()