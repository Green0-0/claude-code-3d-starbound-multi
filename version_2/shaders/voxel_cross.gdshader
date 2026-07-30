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

#include "res://shaders/cutaway.gdshaderinc"


varying vec3 v_world;


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
	float ghost;
	if (cut_should_discard(bc, FRAGCOORD.xy, ghost)) {
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
