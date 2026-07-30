shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Transparent voxel pass (glass, ice). Same cutaway predicate as voxel.gdshader.

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rough : hint_range(0.0, 1.0) = 0.12;
uniform float spec : hint_range(0.0, 1.0) = 0.75;
uniform float emission_boost : hint_range(0.0, 8.0) = 2.0;

// Cutaway globals. These are pushed by Cutaway.push_to_shader_globals(), and
// is_cut() below is a line-for-line transcription of Cutaway.is_cut() so the
// GPU discard and the CPU cross-section caps never disagree about which blocks
// exist.
global uniform vec3 cut_cam_pos;
global uniform vec3 cut_target_pos;
global uniform float cut_radius;
global uniform float cut_target_padding;
global uniform float cut_enabled;

varying vec3 v_world;
varying vec3 v_wnormal;

bool is_cut(vec3 bc) {
	if (cut_enabled < 0.5) {
		return false;
	}
	vec3 seg = cut_target_pos - cut_cam_pos;
	vec3 rel = bc - cut_cam_pos;
	float len2 = dot(seg, seg);
	if (len2 < 0.001) {
		// camera sitting exactly on the target
		float rr = cut_radius + cut_target_padding;
		return dot(rel, rel) <= rr * rr;
	}
	// project onto the camera->player segment: t=0 at the lens, t=1 at the player
	float t = dot(rel, seg) / len2;
	vec3 closest;
	float er = cut_radius;
	if (t <= 0.0) {
		closest = cut_cam_pos;              // behind the lens
	} else if (t >= 1.0) {
		closest = cut_target_pos;           // past the player: widen the cap
		er += cut_target_padding;
	} else {
		closest = cut_cam_pos + seg * t;
	}
	vec3 d = bc - closest;
	return dot(d, d) <= er * er;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 bc = floor(v_world - v_wnormal * 0.5) + vec3(0.5);
	if (is_cut(bc)) {
		discard;
	}
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.r;
	ALPHA = t.a;
	ROUGHNESS = rough;
	SPECULAR = spec;
	EMISSION = t.rgb * COLOR.g * emission_boost;
	RIM = 0.5;
	RIM_TINT = 0.4;
}
