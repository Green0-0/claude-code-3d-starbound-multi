// Planeshift slab shader — transparent voxel faces (glass, ice, leaves and the
// crossed quads used by plants).
//
// Identical slab maths to render/voxel.gdshader; the differences are alpha
// blending, no shadow casting (translucent voxels shadowing the play layer looks
// wrong and doubles the shadow cost) and two-sided rendering for cross quads,
// which the mesher emits with explicit front and back faces.
shader_type spatial;
render_mode cull_back, blend_mix, diffuse_lambert, specular_disabled, shadows_disabled;

uniform sampler2DArray albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2DArray emission_tex : source_color, filter_nearest_mipmap, repeat_enable;

uniform float depth_axis = 2.0;
uniform float depth_sign = -1.0;
uniform float play_layer = 0.0;
uniform float slab_behind = 12.0;
uniform float slab_front = 0.0;
uniform float flip_blend = 0.0;

uniform vec3 fog_color : source_color = vec3(0.09, 0.11, 0.16);
uniform float back_darken : hint_range(0.0, 1.0) = 0.78;
uniform float back_desaturate : hint_range(0.0, 1.0) = 0.70;
uniform float back_fog : hint_range(0.0, 1.0) = 0.60;
uniform float light_floor : hint_range(0.0, 1.0) = 0.16;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.2;
// Fragments below this alpha are dropped, which turns the plant and leaf tiles
// into clean cutouts while leaving glass smoothly blended.
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.06;
// Translucent voxels fade out faster with depth than solid ones.
uniform float back_dissolve : hint_range(0.0, 1.0) = 0.55;

varying vec3 v_world;
varying vec3 v_normal_w;
varying float v_layer;
varying float v_emit;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_layer = UV2.x;
	v_emit = UV2.y;
}

float voxel_layer(vec3 world_pos, vec3 nrm) {
	vec3 centre = world_pos - 0.5 * nrm;
	return floor(depth_axis < 1.0 ? centre.x : centre.z);
}

void fragment() {
	float layer_off = (voxel_layer(v_world, v_normal_w) - play_layer) * depth_sign;
	if (layer_off < -slab_front - 0.5) {
		discard;
	}

	vec4 tex = texture(albedo_tex, vec3(UV, v_layer));
	float shade = max(COLOR.a, light_floor);
	vec3 col = tex.rgb * shade;

	float t = clamp(layer_off / max(slab_behind, 1.0), 0.0, 1.0);
	float fade = t * t * (3.0 - 2.0 * t);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), fade * back_desaturate);
	col *= mix(1.0, 1.0 - back_darken, fade);
	col = mix(col, fog_color, fade * back_fog);

	if (flip_blend > 0.0) {
		float fl = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(fl) * 1.15, flip_blend * 0.35);
	}

	float a = tex.a * mix(1.0, 1.0 - back_dissolve, fade);
	if (a < alpha_cutoff) {
		discard;
	}

	ALBEDO = col;
	ALPHA = a;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	EMISSION = texture(emission_tex, vec3(UV, v_layer)).rgb
		* v_emit * emission_energy * (1.0 - fade * 0.85);
}
