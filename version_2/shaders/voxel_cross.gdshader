shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

// Cross-quad pass: foliage, crops, torches, vines.
//
// Two quads crossed at 90° per block, which reads identically from all four
// camera facings — the reason every plant in the game is built this way rather
// than as a billboard, since the camera is rotated constantly.
//
// Unlike the cube passes this cannot recover its owning voxel by stepping along
// the normal (the normal is a flat fake so foliage lights softly). The geometry
// is strictly inside its own cell instead, so plain floor() is exact.

uniform sampler2D atlas : source_color, filter_nearest;
uniform float emission_boost : hint_range(0.0, 8.0) = 4.0;
uniform float sway : hint_range(0.0, 0.4) = 0.045;

global uniform vec3 cut_cam_pos;
global uniform vec3 cut_target_pos;
global uniform float cut_radius;
global uniform float cut_target_padding;
global uniform float cut_enabled;

varying vec3 v_world;

bool is_cut(vec3 bc) {
	if (cut_enabled < 0.5) {
		return false;
	}
	vec3 seg = cut_target_pos - cut_cam_pos;
	vec3 rel = bc - cut_cam_pos;
	float len2 = dot(seg, seg);
	if (len2 < 0.001) {
		float rr = cut_radius + cut_target_padding;
		return dot(rel, rel) <= rr * rr;
	}
	float t = dot(rel, seg) / len2;
	vec3 closest;
	float er = cut_radius;
	if (t <= 0.0) {
		closest = cut_cam_pos;
	} else if (t >= 1.0) {
		closest = cut_target_pos;
		er += cut_target_padding;
	} else {
		closest = cut_cam_pos + seg * t;
	}
	vec3 d = bc - closest;
	return dot(d, d) <= er * er;
}

void vertex() {
	// chunk meshes are pure translations, so world = model space + node origin
	vec3 w = VERTEX + NODE_POSITION_WORLD;
	// COLOR.b carries "how far up the plant this vertex is", so only tips move
	float h = COLOR.b;
	VERTEX.x += sin(TIME * 1.3 + w.x * 0.7 + w.z * 0.9) * sway * h;
	VERTEX.z += cos(TIME * 1.1 + w.z * 0.6 + w.x * 0.8) * sway * h;
	v_world = VERTEX + NODE_POSITION_WORLD;
}

void fragment() {
	vec3 bc = floor(v_world - vec3(0.0, 0.002, 0.0)) + vec3(0.5);
	if (is_cut(bc)) {
		discard;
	}
	vec4 t = texture(atlas, UV);
	if (t.a < 0.4) {
		discard;
	}
	ALBEDO = t.rgb * COLOR.r;
	ALPHA = 1.0;
	ROUGHNESS = 0.92;
	EMISSION = t.rgb * COLOR.g * emission_boost;
	// foliage is lit soft and two-sided rather than faceted
	NORMAL = mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65);
}
