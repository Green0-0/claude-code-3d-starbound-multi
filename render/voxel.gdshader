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
uniform float back_darken : hint_range(0.0, 1.0) = 0.50;
uniform float back_desaturate : hint_range(0.0, 1.0) = 0.42;
uniform float back_fog : hint_range(0.0, 1.0) = 0.10;
uniform float light_floor : hint_range(0.0, 1.0) = 0.32;
uniform float emission_energy : hint_range(0.0, 8.0) = 2.2;
// Per-voxel edge darkening. Without it a pale material against a pale sky (snow
// at noon, sand on a desert world) has no silhouette at all and the player looks
// like they are standing on nothing. A thin darker border on every tile gives
// the grid definition independently of what is behind it.
uniform float edge_darken : hint_range(0.0, 0.6) = 0.24;
uniform float edge_width : hint_range(0.0, 0.25) = 0.06;
// Layers in *front* of the play layer must not hide the player, but leaving them
// completely invisible means you cannot tell solid rock is between you and the
// camera — which matters a great deal when deciding whether to shift a layer.
// So the interior is discarded and only a thin edge remains: a ghost wireframe
// that reads the material without occluding anything.
uniform float front_ghost : hint_range(0.0, 1.0) = 0.18;
uniform float front_ghost_width : hint_range(0.0, 0.25) = 0.045;
// Only the nearest couple of front layers ghost. Standing on any slope puts
// several layers between you and the camera, and outlining them all fills the
// screen with a wire mesh that hides the very thing it is meant to clarify.
uniform float front_ghost_layers : hint_range(0.0, 8.0) = 1.0;

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

	// Position inside this one voxel face. `UV` counts whole tiles, so fract()
	// works even on a greedy-merged quad spanning many voxels.
	vec2 cell = fract(UV);
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));

	// Layers in front of the play layer may not fill — only outline. Their
	// interiors are discarded so nothing ever occludes the player, but a thin
	// ghost edge remains so you can still tell solid matter is between you and
	// the camera before deciding to shift a layer.
	bool in_front = layer_off < -slab_front - 0.5;
	float depth_in_front = -layer_off - slab_front;
	if (in_front && (front_ghost <= 0.001
			|| depth_in_front > front_ghost_layers + 0.5
			|| edge > front_ghost_width)) {
		discard;
	}

	vec4 tex = texture(albedo_tex, vec3(UV, v_layer));
	float shade = max(COLOR.a, light_floor);
	vec3 col = tex.rgb * shade;

	// Voxel outline, so a pale material against a pale sky still has a silhouette.
	if (!in_front && edge_darken > 0.001) {
		col *= mix(1.0 - edge_darken, 1.0, smoothstep(0.0, edge_width, edge));
	}

	// Depth grading: a hard step at the play/background boundary, then a gentle
	// ramp. The most important readability rule in the game — the layer you can
	// stand on must never be mistaken for one you fall through — so layer 1
	// jumps straight to half-faded instead of easing in from zero.
	float fade = (layer_off < 0.5) ? 0.0
		: mix(0.5, 1.0, clamp((layer_off - 1.0) / max(slab_behind - 1.0, 1.0), 0.0, 1.0));
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(grey), fade * back_desaturate);
	col *= mix(1.0, 1.0 - back_darken, fade);
	col = mix(col, fog_color, fade * back_fog);

	// Mid-flip wash so the 90 degree rotation reads as a deliberate transition.
	if (flip_blend > 0.0) {
		float fl = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(col, vec3(fl) * 1.15, flip_blend * 0.35);
	}

	// `fragment()` may not `return`, so both cases are selected, not branched out.
	float ghost = front_ghost / (1.0 + 1.4 * max(depth_in_front - 1.0, 0.0));
	vec3 ghost_col = mix(fog_color, tex.rgb, 0.65) * ghost;
	vec3 emit = texture(emission_tex, vec3(UV, v_layer)).rgb
		* v_emit * emission_energy * (1.0 - fade * 0.85);

	ALBEDO = in_front ? ghost_col : col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	AO = in_front ? 1.0 : clamp(COLOR.a, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.45;
	EMISSION = in_front ? vec3(0.0) : emit;
}

