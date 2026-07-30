shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Terrain material for the voxel chunks.
//
// COLOR channels carry per-vertex bakes from the mesher:
//   r = ambient occlusion * per-block tone jitter
//   g = emission strength
//   b = 1 for terrain (unused spare)
//
// The cutaway globals are shared with cut_cap.gdshader and with the GDScript
// side (Cutaway.is_cut) so CPU and GPU agree on exactly which blocks exist.

#include "res://shaders/cutaway.gdshaderinc"

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rough : hint_range(0.0, 1.0) = 0.94;
uniform float spec : hint_range(0.0, 1.0) = 0.18;
uniform float emission_boost : hint_range(0.0, 8.0) = 4.0;
uniform vec3 warm_tint : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 ghost_tint : source_color = vec3(0.62, 0.78, 0.95);

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
	// Recover the exact block this fragment belongs to: step half a unit along
	// -normal to land inside the owning voxel, then snap to its centre. This is
	// what keeps the GPU predicate identical to the CPU one.
	vec3 bc = floor(v_world - v_wnormal * 0.5) + vec3(0.5);
	float ghost;
	if (cut_should_discard(bc, FRAGCOORD.xy, ghost)) {
		discard;
	}

	vec4 t = texture(atlas, UV);
	float ao = COLOR.r;
	vec3 base = t.rgb * warm_tint;

	// Face-direction tinting: a touch of sky bounce on tops, warmth on the
	// south/west faces. Cheap, and does a lot for the painted HD-2D look.
	float up = max(v_wnormal.y, 0.0);
	base = mix(base, base * vec3(1.06, 1.08, 1.14), up * 0.35);
	float side = max(-v_wnormal.y, 0.0);
	base = mix(base, base * vec3(0.72, 0.70, 0.78), side * 0.5);

	// A surviving ghost reads as a blueprint of the block rather than the block:
	// desaturated, cooled, and faintly lit so it stays legible against terrain.
	if (ghost > 0.0) {
		float grey = dot(base, vec3(0.299, 0.587, 0.114));
		base = mix(vec3(grey) * ghost_tint, base, 0.35);
	}

	ALBEDO = base * ao;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;
	EMISSION = t.rgb * COLOR.g * emission_boost + ghost_tint * ghost * 0.10;
	AO = ao;
	AO_LIGHT_AFFECT = 0.65;
}
