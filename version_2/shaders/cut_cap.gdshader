shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// The cross-section "caps".
//
// When the cutaway predicate deletes a block, any solid neighbour that survives
// suddenly has a face with nothing on the other side of it. The mesher on the
// CPU walks the boundary of the cut volume and emits exactly those faces into
// this material, so the cutaway reads as a clean sliced-open diagram instead of
// a hole into the skybox.
//
// It is deliberately styled: desaturated strata, a faint survey grid, and a
// warm glow that falls off with distance from the player, which is what
// "highlights the tunnel" you just walked into.

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 slice_tint : source_color = vec3(0.20, 0.17, 0.22);
uniform float slice_mix : hint_range(0.0, 1.0) = 0.34;
uniform float grid_strength : hint_range(0.0, 1.0) = 0.09;
uniform vec3 glow_color : source_color = vec3(1.0, 0.62, 0.30);
uniform float glow_strength : hint_range(0.0, 6.0) = 0.42;
uniform float glow_falloff = 11.0;
uniform float floor_light : hint_range(0.0, 1.0) = 0.16;

global uniform vec3 cut_target_pos;
global uniform float cut_opacity;

varying vec3 v_world;
varying vec3 v_wnormal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec4 t = texture(atlas, UV);
	float ao = COLOR.r;

	// Sedimentary banding so a deep cut reads as strata rather than mush.
	float band = 0.5 + 0.5 * sin(v_world.y * 1.7);
	vec3 base = mix(t.rgb, slice_tint, slice_mix);
	base *= mix(0.86, 1.10, band);

	// Faint 1-block survey grid on the cut surfaces.
	vec3 g = abs(fract(v_world - 0.5) - 0.5);
	vec2 gu = (abs(v_wnormal.x) > 0.5) ? vec2(g.y, g.z)
			: ((abs(v_wnormal.y) > 0.5) ? vec2(g.x, g.z) : vec2(g.x, g.y));
	float line = 1.0 - smoothstep(0.0, 0.06, min(gu.x, gu.y));
	base = mix(base, base * 1.35, line * grid_strength);

	// Warm highlight around the opening the player is standing in.
	float dist = length(v_world - cut_target_pos);
	float glow = exp(-dist / glow_falloff);
	// When cut blocks are drawn as ghosts rather than deleted, the caps behind
	// them would double up; fade them back so the ghost reads instead.
	float cap_fade = 1.0 - clamp(cut_opacity, 0.0, 1.0) * 0.55;

	ALBEDO = base * ao * cap_fade;
	ROUGHNESS = 1.0;
	// A large slice runs well past the reach of any lamp, and an unlit
	// cross-section reads as a void rather than as a diagram. Floor it.
	EMISSION = glow_color * glow * glow_strength * (0.25 + 0.75 * line)
		+ base * floor_light * cap_fade;
	AO = ao;
	AO_LIGHT_AFFECT = 0.8;
}
