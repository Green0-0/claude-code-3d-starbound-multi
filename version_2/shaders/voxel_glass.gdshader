shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Transparent voxel pass (glass, ice). Same cutaway predicate as voxel.gdshader.

#include "res://shaders/cutaway.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rough : hint_range(0.0, 1.0) = 0.12;
uniform float spec : hint_range(0.0, 1.0) = 0.75;
uniform float emission_boost : hint_range(0.0, 8.0) = 2.0;

// Cutaway globals. These are pushed by Cutaway.push_to_shader_globals(), and
// is_cut() below is a line-for-line transcription of Cutaway.is_cut() so the
// GPU discard and the CPU cross-section caps never disagree about which blocks

varying vec3 v_world;
varying vec3 v_wnormal;


void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 bc = floor(v_world - v_wnormal * 0.5) + vec3(0.5);
	float ghost;
	if (cut_should_discard(bc, FRAGCOORD.xy, ghost)) {
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
