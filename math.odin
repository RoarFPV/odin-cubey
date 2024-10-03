package cubey

import "core:math/linalg"


math_bary_interp :: proc(bary: vec3, v:[3]vec3) -> vec3 {
	return bary.x * v[0] + bary.y * v[1] + bary.z * v[2] 
}

math_tri_edge :: proc "contextless" (a, b, c: vec3) -> f32 {
	ca := (c - a)
	ba := (b - a)
	return ca.x * ba.y - ca.y * ba.x
}

// Compute barycentric coordinates (u, v, w) for
// point p with respect to triangle (a, b, c)
math_barycentric_coords :: proc "contextless" (v: [3]vec3, p: vec3) -> vec3 {

	// void Barycentric(Point p, Point a, Point b, Point c, float &u, float &v, float &w)
	// {
	v0 := v[1] - v[0]
	v1 := v[2] - v[0]
	v2 := p - v[0]

	d00 := linalg.dot(v0, v0)
	d01 := linalg.dot(v0, v1)
	d11 := linalg.dot(v1, v1)
	d20 := linalg.dot(v2, v0)
	d21 := linalg.dot(v2, v1)
	denom := 1 / (d00 * d11 - d01 * d01)
	v := (d11 * d20 - d01 * d21) * denom
	w := (d00 * d21 - d01 * d20) * denom
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

