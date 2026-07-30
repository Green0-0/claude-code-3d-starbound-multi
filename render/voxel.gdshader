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
// Master switch for the front-layer treatment; 0 reverts to hard culling.
uniform float front_ghost : hint_range(0.0, 1.0) = 1.0;
// Width of the solid outline kept around every front-layer voxel face.
uniform float front_ghost_width : hint_range(0.0, 0.25) = 0.045;
// How many layers in front of the play layer are drawn at all.
// Every front layer the renderer streams is drawn, not just the nearest few:
// culling deeper ones leaves the same hole-to-the-sky this was meant to fix.
// The mesher already culls faces between solid neighbours, so in a solid mass
// this is one surface, not a stack of them.
uniform float front_ghost_layers : hint_range(0.0, 64.0) = 40.0;
// Front-layer voxels are drawn SOLID by default: a hole punched through to the
// sky reads as a blank white void, which is worse than not seeing past them.
// Legibility comes from a peek window instead — a soft circle centred on the
// player, inside which those voxels thin out to a screen-door dither so the
// player, and any cave they are standing in, show through.
uniform vec2 cut_center = vec2(0.5, 0.5);
uniform float cut_radius : hint_range(0.0, 1.0) = 0.21;
uniform float cut_aspect = 1.777;
// Dither density at the very centre of the window. Deliberately NOT near zero:
// at 0 the blocking voxel disappears completely, and wherever nothing lies
// behind it that leaves a hole straight through to the sky — the blank void this
// whole scheme exists to avoid. A quarter of the pixels is enough to keep the
// material present while leaving the player plainly readable through the gaps.
uniform float front_fill_center : hint_range(0.0, 1.0) = 0.16;
// ...and at its edge, blending out to fully solid beyond.
uniform float front_fill_edge : hint_range(0.0, 1.0) = 0.55;
// How much of the real material colour survives in a front-layer pixel.
uniform float front_material : hint_range(0.0, 1.0) = 0.78;

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

// 4x4 ordered dither, the compact recursive form. Screen-space so the stipple
// stays put as the world scrolls, which reads as translucency rather than noise.
float ps_bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float ps_bayer4(vec2 a) {
	return ps_bayer2(0.5 * a) * 0.25 + ps_bayer2(a);
}

void fragment() {
	float layer_off = (voxel_layer(v_world, v_normal_w) - play_layer) * depth_sign;

	// Position inside this one voxel face. `UV` counts whole tiles, so fract()
	// works even on a greedy-merged quad spanning many voxels.
	vec2 cell = fract(UV);
	float edge = min(min(cell.x, 1.0 - cell.x), min(cell.y, 1.0 - cell.y));

	// Layers in front of the play layer must not hide the player, but they must
	// not vanish either: culling them outright punches a hole straight through
	// to the sky, which reads as a blank white void wherever there is nothing
	// behind to draw. Instead the blocking voxel is drawn for real through a
	// screen-space dither — solid enough to be recognisable matter, sparse
	// enough that a cave (or the player) behind it shows through the gaps.
	bool in_front = layer_off < -slab_front - 0.5;
	float depth_in_front = -layer_off - slab_front;
	// Distance from the peek window's centre, in units of its radius.
	vec2 cd = SCREEN_UV - cut_center;
	cd.x *= cut_aspect;
	float cut_r = length(cd) / max(cut_radius, 0.0001);
	// 1 at the centre of the window, 0 outside it.
	float openness = 1.0 - smoothstep(0.55, 1.0, cut_r);
	float fill = mix(front_fill_edge, front_fill_center, openness);
	fill = mix(1.0, fill, step(0.001, openness) * min(openness * 3.0, 1.0));
	bool keep = ps_bayer4(FRAGCOORD.xy) < fill;
	if (in_front && (front_ghost <= 0.001
			|| depth_in_front > front_ghost_layers + 0.5
			|| !keep)) {
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
	// A front-layer pixel keeps most of its material colour but is hazed toward
	// the fog and dimmed with depth, so it reads as "in front of you, not yours".
	// Front voxels are real terrain, but they must never be mistaken for the
	// layer you can stand on: dim and desaturate them, and dim harder inside the
	// peek window so the opening reads as an opening.
	float ghost_dim = mix(0.70, 0.42, openness);
	vec3 ghost_base = tex.rgb * max(shade, 0.5);
	float ghost_grey = dot(ghost_base, vec3(0.299, 0.587, 0.114));
	ghost_base = mix(ghost_base, vec3(ghost_grey), 0.35);
	vec3 ghost_col = mix(fog_color, ghost_base, front_material) * ghost_dim;
	vec3 emit = texture(emission_tex, vec3(UV, v_layer)).rgb
		* v_emit * emission_energy * (1.0 - fade * 0.85);

	ALBEDO = in_front ? ghost_col : col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	AO = in_front ? 1.0 : clamp(COLOR.a, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.45;
	EMISSION = in_front ? vec3(0.0) : emit;
}

