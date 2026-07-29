## The full-screen presentation of a 90 degree world flip.
##
## A single `ColorRect` on a `CanvasLayer` this node creates and owns, running a
## procedurally generated shader: a soft radial wipe that sweeps out from the
## centre, a chromatic shear tangential to the rotation, and optional motion
## blur streaks along the same direction. Everything peaks at `flip_t == 0.5`
## and is gone by `flip_t == 1`.
##
## Design constraints:
## * It sits on layer -1, so it distorts the 3D world but never the HUD.
## * `mouse_filter = IGNORE` and no `_input` handlers: it cannot eat input.
## * Hidden whenever a flip is not running, so the screen-texture backbuffer
##   copy costs nothing at rest.
## * Fully skippable: `CamSettings.flip_transition_enabled = false` (or
##   `CamSettings.reduce_motion = true`) disables it with no other side effects.
class_name CamFlipTransition
extends CanvasLayer

## Draw order. Negative keeps the effect under every HUD/menu CanvasLayer.
@export var canvas_layer := -1
## Overall strength multiplier for the distortion.
@export var strength := 1.0
## Motion-blur streak weight, 0 disables the extra texture taps.
@export var streak_strength := 0.6
## Colour bloomed into the wipe front.
@export var wipe_tint := Color(0.55, 0.72, 1.0)

const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float spin = 1.0;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.6;
uniform float aspect = 1.777;
uniform vec3 tint : source_color = vec3(0.55, 0.72, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - vec2(0.5);
	vec2 cc = vec2(c.x * aspect, c.y);
	float r = length(cc) * 1.42;

	float env = sin(progress * PI);
	env = env * env * (3.0 - 2.0 * env);
	float amt = clamp(env * intensity, 0.0, 1.5);

	// Soft expanding ring: the wipe front sweeps out from the centre, which is
	// where the player is pinned, so the eye is led outward into the new plane.
	float front = progress * 1.25;
	float band = 1.0 - smoothstep(0.0, 0.42, abs(r - front));

	// Tangential (rotation) direction, in UV space.
	vec2 tang = normalize(vec2(-cc.y, cc.x) + vec2(0.0001, 0.0001)) * spin;
	tang.x /= aspect;

	float shear = (0.010 + 0.020 * band) * amt * min(r, 1.2);
	vec3 col;
	col.r = texture(screen_tex, uv + tang * shear).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - tang * shear).b;

	if (streaks > 0.001) {
		vec3 acc = vec3(0.0);
		for (int i = 1; i <= 4; i++) {
			float f = float(i) * 0.25;
			vec2 o = tang * (f * 0.05 * amt * streaks * (0.25 + r));
			acc += texture(screen_tex, uv + o).rgb;
			acc += texture(screen_tex, uv - o).rgb;
		}
		col = mix(col, acc * 0.125, clamp(amt * streaks * 0.8, 0.0, 0.8));
	}

	col += tint * (band * amt * 0.16);
	col *= 1.0 - amt * 0.18 * smoothstep(0.35, 1.15, r);
	COLOR = vec4(col, 1.0);
}
"""

var _rect: ColorRect = null
var _copy: BackBufferCopy = null
var _mat: ShaderMaterial = null
var _spin := 1.0


func _ready() -> void:
	process_priority = 11
	layer = canvas_layer
	follow_viewport_enabled = false
	_build()
	_rect.visible = false


func _build() -> void:
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("tint", Vector3(wipe_tint.r, wipe_tint.g, wipe_tint.b))

	# `hint_screen_texture` in a canvas_item shader reads the back buffer, and
	# Godot only fills it where a BackBufferCopy has run. Without this the
	# uniform set is null and every draw call of the overlay errors out.
	_copy = BackBufferCopy.new()
	_copy.name = "FlipBackBuffer"
	_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_copy)

	_rect = ColorRect.new()
	_rect.name = "FlipOverlay"
	_rect.material = _mat
	_rect.color = Color(1, 1, 1, 1)
	# Never, ever intercept a click.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.anchor_right = 1.0
	_rect.anchor_bottom = 1.0
	_rect.offset_right = 0.0
	_rect.offset_bottom = 0.0
	add_child(_rect)


func _process(_delta: float) -> void:
	if _rect == null:
		return
	if not View.flipping or not _is_enabled():
		if _rect.visible:
			_rect.visible = false
			if _copy != null:
				_copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	_rect.visible = true
	if _copy != null and _copy.copy_mode != BackBufferCopy.COPY_MODE_VIEWPORT:
		_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	var vp := get_viewport()
	var a := 16.0 / 9.0
	if vp != null:
		var s := vp.get_visible_rect().size
		if s.y > 0.0:
			a = s.x / s.y
	_mat.set_shader_parameter("progress", View.flip_t)
	_mat.set_shader_parameter("spin", _spin)
	_mat.set_shader_parameter("aspect", a)
	_mat.set_shader_parameter("intensity", maxf(0.0, strength) * CamSettings.flip_transition_strength)
	_mat.set_shader_parameter("streaks",
		clampf(streak_strength, 0.0, 1.0) if CamSettings.flip_streaks_enabled else 0.0)


func _is_enabled() -> bool:
	return CamSettings.flip_transition_enabled and not CamSettings.reduce_motion


## Called by `CamRig` when a flip starts. `dir` is -1 or +1 and sets which way
## the shear and the streaks lean.
func play(dir: int) -> void:
	_spin = -1.0 if dir < 0 else 1.0
	if _rect != null and _is_enabled():
		_rect.visible = true


## Hide immediately (used by cutscenes / instant view changes).
func stop() -> void:
	if _rect != null:
		_rect.visible = false
