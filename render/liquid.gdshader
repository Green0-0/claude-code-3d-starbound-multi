// Planeshift slab shader — liquids (water, lava, anything with Render.LIQUID).
//
// Same slab grading as the solid voxel shaders, plus:
//   * a gentle two-frequency surface wave applied only to up-facing vertices,
//     so the top of a pool ripples while its walls stay put;
//   * a shallow specular response and a fresnel rim, which is what reads as
//     "wet" at this art scale;
//   * scrolling UVs so large bodies of liquid are never static.
//
// The mesher lowers the top face by the fill level from `Chunk.liquid_at()`
// before this shader ever sees it; the wave only adds the last few centimetres.
shader_type spatial;
render_mode cull_back, blend_mix, diffuse_lambert, depth_draw_opaque, shadows_disabled;

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
uniform float light_floor : hint_range(0.0, 1.0) = 0.24;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.2;

uniform float wave_height : hint_range(0.0, 0.4) = 0.055;
uniform float wave_scale : hint_range(0.1, 8.0) = 1.35;
uniform float wave_speed : hint_range(0.0, 6.0) = 1.15;
uniform vec2 flow = vec2(0.035, 0.018);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;

varying vec3 v_world;
varying vec3 v_normal_w;
varying float v_layer;
varying float v_emit;
varying float v_surface;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Only the top surface moves; side walls must stay welded to the voxel grid.
	v_surface = step(0.5, NORMAL.y);
	float w = sin(world.x * wave_scale + TIME * wave_speed)
		* cos(world.z * wave_scale * 0.87 + TIME * wave_speed * 0.73);
	w += 0.45 * sin((world.x + world.z) * wave_scale * 2.1 - TIME * wave_speed * 1.6);
	VERTEX.y += w * wave_height * v_surface;
	world.y += w * wave_height * v_surface;

	v_world = world;
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

	vec2 uv = UV + flow * TIME;
	vec4 tex = texture(albedo_tex, vec3(uv, v_layer));
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

	// Fresnel rim brightens grazing angles: cheap, and it makes the surface pop
	// against the slab behind it.
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col += col * fres * rim_strength * (1.0 - fade);

	ALBEDO = col;
	ALPHA = clamp(tex.a * mix(1.0, 0.55, fade), 0.0, 1.0);
	ROUGHNESS = mix(0.55, 0.12, v_surface);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	EMISSION = texture(emission_tex, vec3(uv, v_layer)).rgb
		* v_emit * emission_energy * (1.0 - fade * 0.85);
}
