package cubey

import "core:math/linalg"

math_tri_normal :: proc "contextless" (tri: [3]vec3) -> vec3 {
	e0 := tri[1] - tri[0]
	e1 := tri[2] - tri[0]

	return linalg.normalize(linalg.cross(e0, e1))
}

math_bary_interp :: proc "contextless" (bary: vec3, v: [3]vec3) -> vec3 {
	return bary.x * v[0] + bary.y * v[1] + bary.z * v[2]
}

math_tri_edge :: proc "contextless" (a, b, c: vec3) -> f32 {
	ca := (c - a)
	ba := (b - a)
	return ca.x * ba.y - ca.y * ba.x
}

math_tri_edge_ba :: proc "contextless" (a, ba, c: vec3) -> f32 {
	ca := (c - a)
	return ca.x * ba.y - ca.y * ba.x
}

BaryData :: struct {
	e0:        vec3,
	e1:        vec3,
	d:         vec3,
	inv_denom: f32,
}

math_bary_data :: proc(v:[3]vec3) -> BaryData {
	e0 := v[1] - v[0]
	e1 := v[2] - v[0]


	d00 := linalg.dot(e0, e0)
	d01 := linalg.dot(e0, e1)
	d11 := linalg.dot(e1, e1)
	denom := 1 / (d00 * d11 - d01 * d01)

	return {e0, e1, {d00, d01, d11}, denom}
}

// Compute barycentric coordinates (u, v, w) for
// point p with respect to triangle (a, b, c)
math_barycentric_coords :: proc "contextless" (data:BaryData, tri: [3]vec3, p: vec3) -> vec3 {

	// void Barycentric(Point p, Point a, Point b, Point c, float &u, float &v, float &w)
	// {
	
	v2 := p - tri[0]
	d20 := linalg.dot(v2, data.e0)
	d21 := linalg.dot(v2, data.e1)
	v := (data.d[2] * d20 - data.d[1] * d21) * data.inv_denom
	w := (data.d[0] * d21 - data.d[1] * d20) * data.inv_denom
	u := 1.0 - v - w
	return vec3{u, v, w}
	// }
}

math_barycentric_coords_edge :: proc "contextless" (v: [3]vec3, p: vec3) -> vec3 {
	return {
		math_tri_edge(v[1], v[2], p), 
		math_tri_edge(v[2], v[0], p), 
		math_tri_edge(v[0], v[1], p)
	}
}


math_barycentric_coords_edge_ba :: proc "contextless" (v:[3]vec3, edge: [3]vec3, p: vec3) -> vec3 {
	return {
		math_tri_edge_ba(v[1], edge[0], p),
		math_tri_edge_ba(v[2], edge[1], p),
		math_tri_edge_ba(v[0], edge[2], p),
	}
}
