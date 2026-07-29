// Planeshift slab shader — opaque voxel faces.
//
// The world is genuinely 3D but the camera only ever sees one plane of it. This
// shader is what turns that into Starbound's foreground/background duality:
//
//   * every fragment works out which voxel layer it belongs to, from its world
//     position and its face normal;
//   * layers IN FRONT of the play layer are discarded outright, so the world
//     can never occlude the player no matter how deep into a mountain they are;
//   * layers BEHIND the play layer darken, desaturate and drift toward the fog
//     colour, so depth reads instantly even though it is all real geometry.
//
// Vertex contract (see render/chunk_mesher.gd):
//   COLOR.rgb : block tint * light * ambient occlusion  (fallback albedo)
//   COLOR.a   : light * ambient occlusion               (shade scalar)
//   UV        : tile coordinates, scaled by the greedy quad size
//   UV2.x     : texture array layer  (Atlas.layer_for)
//   UV2.y     : emission strength    (BlockType.emission)
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, depth_draw_opaque;

uniform sampler2DArray albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2DArray emission_tex : source_color, filter_nearest_mipmap, repeat_enable;

// --- driven every frame from View.shader_params() ---------------------------
// 0.0 => world X is the depth axis, 2.0 => world Z is.
uniform float depth_axis = 2.0;
// +1 or -1: the direction along that axis that leads away from the camera.
uniform float depth_sign = -1.0;
// Integer depth coordinate of the plane the player stands in.
uniform float play_layer = 0.0;
// How many layers behind the play layer stay visible before they are pure fog.
uniform float slab_behind = 12.0;
// How many layers in front of the play layer survive (normally 0).
uniform float slab_front = 0.0;
// 0..1 progress of a view flip; used for a brief desaturating wash.
uniform float flip_blend = 0.0;

// --- look tuning ------------------------------------------------------------
uniform vec3 fog_color : source_color = vec3(0.09, 0.11, 0.16);
uniform float back_darken : hint_range(0.0, 1.0) = 0.78;
uniform float back_desaturate : hint_range(0.0, 1.0) = 0.70;
uniform float back_fog : hint_range(0.0, 1.0) = 0.60;
uniform float light_floor : hint_range(0.0, 1.0) = 0.16;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.2;

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

// Depth coordinate of the voxel this fragment belongs to. Stepping half a voxel
// back along the face normal moves us from the face plane to the voxel centre,
// which is what makes the answer unambiguous on shared faces.
float voxel_layer(vec3 world_pos, vec3 nrm) {
	vec3 centre = world_pos - 0.5 * nrm;
	return floor(depth_axis < 1.0 ? centre.x : centre.z);
}

void fragment() {
	float layer_off = (voxel_layer(v_world, v_normal_w) - play_layer) * depth_sign;

	// Nothing in front of the player is ever allowed to draw.
	if (layer_off < -slab_front - 0.5) {
		discard;
	}

	vec4 tex = texture(albedo_tex, vec3(UV, v_layer));
	float shade = max(COLOR.a, light_floor);
	vec3 col = tex.rgb * shade;

	// Depth grading: darken, desaturate, then sink into the fog colour.
	float t = clamp(layer_off / max(slab_behind, 1.0), 0.0, 1.0);
	float fade = t * t * (3.0 - 2.0 * t);
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), fade * back_desaturate);
	col *= mix(1.0, 1.0 - back_darken, fade);
	col = mix(col, fog_color, fade * back_fog);

	// Mid-flip wash so the 90 degree rotation reads as a deliberate transition.
	if (flip_blend > 0.0) {
		float fl = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(fl) * 1.15, flip_blend * 0.35);
	}

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	AO = clamp(COLOR.a, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.45;
	EMISSION = texture(emission_tex, vec3(UV, v_layer)).rgb
		* v_emit * emission_energy * (1.0 - fade * 0.85);
}
