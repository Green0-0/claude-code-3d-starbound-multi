shader_type canvas_item;

// Final HD-2D grade: gentle chromatic aberration, filmic vignette, subtle grain
// and a warm/cool split tone. Applied by a full-rect ColorRect over the 3D view.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float aberration = 0.0018;
uniform float vignette = 0.55;
uniform float vignette_soft = 0.62;
uniform float grain = 0.028;
uniform float saturation = 1.10;
uniform float contrast = 1.06;
uniform vec3 shadow_tint : source_color = vec3(0.42, 0.44, 0.62);
uniform vec3 highlight_tint : source_color = vec3(1.06, 0.99, 0.90);
uniform float split_strength : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	float r2 = dot(c, c);

	// chromatic aberration grows toward the frame edge
	vec2 off = c * aberration * (0.35 + r2 * 2.2);
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// split tone
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	vec3 split = mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.75, lum));
	col = mix(col, col * split, split_strength);

	// contrast + saturation
	col = (col - vec3(0.5)) * contrast + vec3(0.5);
	lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);

	// vignette
	float v = smoothstep(vignette_soft, 0.12, r2);
	col *= mix(1.0 - vignette, 1.0, v);

	// grain
	float n = hash21(FRAGCOORD.xy + vec2(TIME * 41.0, TIME * 27.0));
	col += (n - 0.5) * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
