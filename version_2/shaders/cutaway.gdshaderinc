// The camera-obstruction predicate, shared by every pass that draws terrain.
//
// This file is a line-for-line transcription of scripts/cutaway.gd. The CPU
// builds the cross-section caps from that version and the GPU discards from
// this one, so if the two ever disagree you get caps floating in front of
// blocks that were never removed. Change them together.

global uniform vec3 cut_cam_pos;
global uniform vec3 cut_target_pos;
global uniform float cut_radius;
global uniform float cut_target_padding;
global uniform float cut_enabled;
global uniform float cut_mode;            // 0 cylinder, 1 fill, 2 planar
global uniform float cut_keep_radius;
global uniform float cut_keep_bias;
global uniform float cut_opacity;
global uniform float cut_fade;
global uniform float cut_planar_depth;
global uniform float cut_planar_width;
global uniform float cut_planar_below;
global uniform float cut_planar_above;
global uniform float cut_occluded;
global uniform vec3 cut_anchor;      // the player's block, in whole voxels
global uniform vec3 cut_toward;      // unit step from the player toward the lens
global uniform vec3 cut_lateral;     // unit step across the screen
global uniform float cut_fill_empty; // 1 when the flood found no enclosed space

// The flood-filled volume, packed as a grid of z-slices. Set per material by
// VoxelWorld rather than as a global, because global sampler uniforms cannot be
// swapped as cheaply as this one needs to be.
uniform sampler2D cut_fill_tex : filter_nearest, repeat_disable;
uniform vec3 cut_fill_origin = vec3(0.0);
uniform vec3 cut_fill_size = vec3(0.0);
uniform float cut_fill_cols = 1.0;

const float CUT_BAYER[16] = float[](
	0.0625, 0.5625, 0.1875, 0.6875,
	0.8125, 0.3125, 0.9375, 0.4375,
	0.2500, 0.7500, 0.1250, 0.6250,
	1.0000, 0.5000, 0.8750, 0.3750
);


// The keep shell: never cut what is under your feet or beside you, only what
// lies toward the lens.
bool cut_is_protected(vec3 bc) {
	vec3 d = bc - cut_target_pos;
	float dist_sq = dot(d, d);
	if (dist_sq > cut_keep_radius * cut_keep_radius) {
		return false;
	}
	if (dist_sq < 0.0001) {
		return true;
	}
	vec3 toward_cam = cut_cam_pos - cut_target_pos;
	float len_sq = dot(toward_cam, toward_cam);
	if (len_sq < 0.0001) {
		return true;
	}
	return dot(d, toward_cam) * inversesqrt(dist_sq * len_sq) < cut_keep_bias;
}


bool cut_in_cylinder(vec3 bc) {
	vec3 seg = cut_target_pos - cut_cam_pos;
	vec3 rel = bc - cut_cam_pos;
	float len_sq = dot(seg, seg);
	if (len_sq < 0.001) {
		float rr = cut_radius + cut_target_padding;
		return dot(rel, rel) <= rr * rr;
	}
	float t = dot(rel, seg) / len_sq;
	vec3 closest;
	float er = cut_radius;
	if (t <= 0.0) {
		closest = cut_cam_pos;
	} else if (t >= 1.0) {
		closest = cut_target_pos;
		er += cut_target_padding;
	} else {
		closest = cut_cam_pos + seg * t;
	}
	vec3 d = bc - closest;
	return dot(d, d) <= er * er;
}


bool cut_in_fill(vec3 bc) {
	if (cut_fill_size.x < 1.0) {
		return false;
	}
	vec3 rel = floor(bc) - cut_fill_origin;
	if (any(lessThan(rel, vec3(0.0))) || any(greaterThanEqual(rel, cut_fill_size))) {
		return false;
	}
	float col = mod(rel.z, cut_fill_cols);
	float row = floor(rel.z / cut_fill_cols);
	vec2 px = vec2(col * cut_fill_size.x + rel.x, row * cut_fill_size.y + rel.y) + 0.5;
	vec2 uv = px / vec2(textureSize(cut_fill_tex, 0));
	return texture(cut_fill_tex, uv).r > 0.5;
}


// An axis-aligned box of whole blocks. `bc` is a block centre, so flooring it
// and subtracting the anchor recovers the integer offset exactly.
bool cut_in_slab(vec3 bc) {
	vec3 d = floor(bc) - cut_anchor;
	float toward = dot(d, cut_toward);
	if (toward < 1.0 || toward > cut_planar_depth) {
		return false;
	}
	float lat = dot(d, cut_lateral);
	if (lat < -cut_planar_width || lat > cut_planar_width) {
		return false;
	}
	return d.y >= -cut_planar_below && d.y <= cut_planar_above;
}


bool cut_is_cut(vec3 bc) {
	if (cut_enabled < 0.5) {
		return false;
	}
	if (cut_mode > 1.5) {
		// The slab only removes what lies toward the lens, so the keep shell has
		// nothing left to protect, and the cut stays a clean solid box.
		return cut_occluded > 0.5 && cut_in_slab(bc);
	}
	if (cut_is_protected(bc)) {
		return false;
	}
	if (cut_mode > 0.5 && cut_fill_empty < 0.5) {
		return cut_in_fill(bc);
	}
	return cut_in_cylinder(bc);
}


// How solid a cut block still is. Zero means "delete it"; anything higher is a
// ghost that thins out with distance from the player, the way distant props
// fade in Don't Starve.
float cut_ghost_alpha(vec3 bc) {
	if (cut_opacity <= 0.0) {
		return 0.0;
	}
	float d = distance(bc, cut_target_pos);
	return clamp(cut_opacity * (1.0 - d / max(cut_fade, 0.001)), 0.0, 1.0);
}


// Screen-door transparency: an ordered dither in the opaque pass, so ghosts
// need no sorting and no second draw. Called with FRAGCOORD.xy.
bool cut_should_discard(vec3 bc, vec2 frag, out float ghost) {
	ghost = 0.0;
	if (!cut_is_cut(bc)) {
		return false;
	}
	float a = cut_ghost_alpha(bc);
	if (a <= 0.002) {
		return true;
	}
	ghost = a;
	ivec2 c = ivec2(mod(frag, 4.0));
	return CUT_BAYER[c.y * 4 + c.x] > a;
}
