## The sky: sun and moon, the colour of the air, and the starfield.
##
## Reads `Game.day_fraction` / `Game.daylight`, folds in the planet palette
## (`LitPlanet`) and the weather (`LitWeather`), and drives:
##
##   * `SunLight` and `FillLight` — the two `DirectionalLight3D`s that already
##     exist in `main.tscn`. Found **by name** from `Game.main`; the scene file
##     is never touched. `FillLight` does double duty: soft sky bounce by day,
##     moonlight by night.
##   * `WorldEnvironment` — ambient colour/energy, fog colour/density, and the
##     `ProceduralSkyMaterial` already in the scene (so sky-derived ambient
##     tracks the palette).
##   * A procedural **sky backdrop**: a quad parented to the live `Camera3D`,
##     sitting at the far end of the orthographic box so ordinary depth testing
##     puts it behind every voxel. Its shader draws the vertical gradient in
##     *world* Y (a side-on camera needs a horizon at sea level, not at the
##     middle of the screen), the sun disc, the moon with real phases, and a
##     hashed starfield that fades in as the sun goes down.
##
## Everything here is presentation. Not one line of it touches `Chunk.light` —
## the only coupling back into the voxel light is `Game.daylight`, which
## `Lighting` multiplies the skylight nibble by.
class_name LitDayNight
extends Node

## Sun arc azimuth, radians. The sun rises along +X by default.
var sun_azimuth := deg_to_rad(20.0)
## How much the *lighting* direction is pulled toward the camera so faces are
## never lit edge-on in a side view. Only affects the DirectionalLight3D, never
## the position the sun is drawn at.
var camera_bias := 0.38
## World Y the horizon line sits at. Overridden per planet from its metadata.
var horizon_y := 96.0
## World units from the horizon to the top of the sky gradient.
var sky_span := 110.0
## View depth at which fog starts in clear weather. The camera stands ~44 blocks
## back, so anything below that would fog the play slab itself.
const FOG_BEGIN_CLEAR := 62.0
## ...and in the worst storm, where haze closing in is the point.
const FOG_BEGIN_STORM := 26.0
## Brightness ceiling for the sky. Deliberately gentle: the `WorldEnvironment`
## derives ambient light *from* the sky (`ambient_light_source = SKY`), so
## clamping this hard dims the entire world. Silhouetting pale terrain against a
## pale sky is the voxel shader's `edge_darken` job, not this one's.
const SKY_MAX_VALUE_TOP := 0.88
const SKY_MAX_VALUE_HORIZON := 0.95
## Minimum saturation for the sky; a grey-white sky reads as fog, not as air.
const SKY_MIN_SATURATION := 0.28
## Days per full lunar cycle.
var moon_cycle_days := 8

# ------------------------------------------------------------------- outputs
var sun_dir := Vector3(-0.4, -0.8, -0.45).normalized()   ## sun -> ground
var moon_dir := Vector3(0.4, -0.8, 0.45).normalized()
var sun_elevation := 0.0        ## -1 .. 1
var ambient_color := Color(0.6, 0.66, 0.78)
var fog_color := Color(0.32, 0.4, 0.55)
var horizon_color := Color(0.62, 0.72, 0.86)
var top_color := Color(0.16, 0.34, 0.68)
var star_amount := 0.0
var moon_illumination := 1.0
var moon_phase_index := 0

# --------------------------------------------------------------------- nodes
var sun: DirectionalLight3D = null
var fill: DirectionalLight3D = null
var world_env: WorldEnvironment = null
var env: Environment = null
var sky_material: ProceduralSkyMaterial = null
var backdrop: MeshInstance3D = null
var backdrop_mesh: QuadMesh = null
var backdrop_mat: ShaderMaterial = null

var _resolve_timer := 0.0
var _globals_ready := false
var _time := 0.0

const PHASE_NAMES := [
	"New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
	"Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
]

const BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled,
	specular_disabled, ambient_light_disabled;

uniform vec3 sky_top_col = vec3(0.16, 0.34, 0.68);
uniform vec3 sky_hor_col = vec3(0.62, 0.72, 0.86);
uniform vec3 sky_low_col = vec3(0.05, 0.05, 0.08);
uniform float cam_y = 100.0;
uniform float horizon_y = 96.0;
uniform float span = 110.0;

uniform vec2 sun_pos = vec2(0.0, 0.0);
uniform vec3 sun_col = vec3(1.0, 0.95, 0.85);
uniform float sun_radius = 1.2;
uniform float sun_amt = 1.0;

uniform vec2 moon_pos = vec2(0.0, 0.0);
uniform vec3 moon_col = vec3(0.9, 0.92, 1.0);
uniform float moon_radius = 1.0;
uniform float moon_amt = 0.0;
uniform float moon_shadow = 0.0;

uniform vec3 star_col = vec3(1.0);
uniform float star_amt = 0.0;
uniform float star_density = 1.0;
uniform float star_pan = 0.0;
uniform float t = 0.0;

varying vec3 vpos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// Quad-local coordinates: the quad is a child of the camera and sized to
	// the orthographic box, so VERTEX.y is a direct offset from the camera's
	// world Y. That is what lets the gradient key off world height.
	vpos = VERTEX;
}

void fragment() {
	float wy = cam_y + vpos.y;
	float h = (wy - horizon_y) / max(1.0, span);
	vec3 col;
	if (h >= 0.0) {
		col = mix(sky_hor_col, sky_top_col, pow(clamp(h, 0.0, 1.0), 0.6));
	} else {
		col = mix(sky_hor_col, sky_low_col, clamp(-h * 4.0, 0.0, 1.0));
	}

	if (star_amt > 0.002 && h > -0.02) {
		vec2 sp = vec2(vpos.x + star_pan, wy) * (0.5 * star_density);
		vec2 cell = floor(sp);
		float r = hash21(cell);
		if (r > 0.945) {
			vec2 c = vec2(hash21(cell + vec2(11.3, 4.1)), hash21(cell + vec2(27.7, 9.6)));
			float d = length(fract(sp) - c);
			float tw = 0.6 + 0.4 * sin(t * 1.9 + r * 63.0);
			float s = smoothstep(0.17, 0.0, d) * tw * (0.35 + 0.65 * fract(r * 17.0));
			col += star_col * s * star_amt * clamp(h * 5.0, 0.0, 1.0);
		}
	}

	if (sun_amt > 0.002) {
		float d = length(vpos.xy - sun_pos);
		float disc = smoothstep(sun_radius, sun_radius * 0.7, d);
		float glow = pow(clamp(1.0 - d / (sun_radius * 10.0), 0.0, 1.0), 3.0);
		col += sun_col * (disc * 1.7 + glow * 0.5) * sun_amt;
	}

	if (moon_amt > 0.002) {
		vec2 mp = vpos.xy - moon_pos;
		float d = length(mp);
		float disc = smoothstep(moon_radius, moon_radius * 0.86, d);
		// The dark limb is a second disc slid across the first.
		float sd = length(mp - vec2(moon_shadow, 0.0));
		float lit_face = disc * smoothstep(moon_radius * 0.96, moon_radius * 1.04, sd);
		float halo = pow(clamp(1.0 - d / (moon_radius * 7.0), 0.0, 1.0), 3.0);
		col += moon_col * (lit_face * 1.25 + halo * 0.22) * moon_amt;
	}

	ALBEDO = col;
}
"""


func _ready() -> void:
	process_priority = 60   # after the camera rig (10) so the quad tracks cleanly
	Events.world_ready.connect(func(_id: String) -> void: _read_planet_meta())
	Events.travel_finished.connect(func(_id: String) -> void: _read_planet_meta())
	_register_globals()


func _process(delta: float) -> void:
	_time += delta
	_resolve_timer -= delta
	if _resolve_timer <= 0.0:
		_resolve_timer = 0.5
		_resolve_nodes()
	_update_sky(delta)


# ------------------------------------------------------------------- resolving
func _resolve_nodes() -> void:
	var main: Node = Game.main
	if main == null:
		return
	if sun == null or not is_instance_valid(sun):
		sun = main.get_node_or_null(^"SunLight") as DirectionalLight3D
	if fill == null or not is_instance_valid(fill):
		fill = main.get_node_or_null(^"FillLight") as DirectionalLight3D
	if world_env == null or not is_instance_valid(world_env):
		world_env = main.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
		if world_env != null:
			env = world_env.environment
			if env != null and env.sky != null:
				sky_material = env.sky.sky_material as ProceduralSkyMaterial
	_ensure_backdrop()


## Clamp a sky colour's brightness and lift its saturation, preserving hue.
static func _skyfloor(c: Color, max_value: float) -> Color:
	var v: float = maxf(c.v, 0.0001)
	var out := c
	if v > max_value:
		out = Color.from_hsv(c.h, c.s, max_value, c.a)
	if out.s < SKY_MIN_SATURATION:
		out = Color.from_hsv(out.h, SKY_MIN_SATURATION, out.v, out.a)
	return out


func _read_planet_meta() -> void:
	var meta: Dictionary = World.planet
	horizon_y = float(meta.get("sea_level", meta.get("surface_y", 96.0)))


## The live camera, wherever the camera agent put it.
func _camera() -> Camera3D:
	var rig: Node = Game.camera_rig
	if rig == null:
		return null
	var c: Variant = rig.get("camera")
	if c is Camera3D and is_instance_valid(c):
		return c
	return rig.get_node_or_null(^"Camera3D") as Camera3D


func _ensure_backdrop() -> void:
	var cam := _camera()
	if cam == null:
		return
	if backdrop != null and is_instance_valid(backdrop):
		if backdrop.get_parent() == cam:
			return
		backdrop.queue_free()
		backdrop = null
	var found := cam.get_node_or_null(^"LitSkyBackdrop")
	if found is MeshInstance3D:
		backdrop = found
	else:
		backdrop = MeshInstance3D.new()
		backdrop.name = "LitSkyBackdrop"
		cam.add_child(backdrop)
	backdrop_mesh = QuadMesh.new()
	backdrop_mesh.size = Vector2(200.0, 120.0)
	var sh := Shader.new()
	sh.code = BACKDROP_SHADER
	backdrop_mat = ShaderMaterial.new()
	backdrop_mat.shader = sh
	backdrop_mesh.material = backdrop_mat
	backdrop.mesh = backdrop_mesh
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	backdrop.extra_cull_margin = 16384.0
	backdrop.layers = Const.RL_WORLD | Const.RL_ENTITIES | Const.RL_EFFECTS


# ------------------------------------------------------------------- the sky
func _update_sky(delta: float) -> void:
	var pal: LitPlanet.Palette = Lighting.planet.palette() if Lighting.planet != null else null
	if pal == null:
		return
	var wx: LitWeather = Lighting.weather

	var raw: float = Game.daylight
	var day: float = Lighting.daylight()          # planet + weather shaped
	var frac: float = Game.day_fraction

	# ---- geometry --------------------------------------------------------
	var angle := (frac - 0.25) * TAU
	var east := Vector3(cos(sun_azimuth), 0.0, sin(sun_azimuth))
	var sun_pos_dir := (east * cos(angle) + Vector3.UP * sin(angle)).normalized()
	sun_elevation = sun_pos_dir.y
	var moon_pos_dir := -sun_pos_dir

	# The lighting direction leans toward the camera so a side-on view always
	# gets a lit face and a shaded face. The *drawn* sun keeps the true arc.
	var cam := _camera()
	var to_cam := Vector3.ZERO
	if cam != null:
		to_cam = cam.global_transform.basis.z    # +Z points back toward the camera
	sun_dir = -((sun_pos_dir + to_cam * camera_bias).normalized())
	moon_dir = -((moon_pos_dir + to_cam * camera_bias).normalized())

	# ---- moon phase ------------------------------------------------------
	var cyc: float = fposmod(float(Game.day) / float(maxi(1, moon_cycle_days)), 1.0)
	moon_phase_index = int(round(cyc * 8.0)) % 8
	moon_illumination = 1.0 - absf(cyc * 2.0 - 1.0)

	# ---- colours ---------------------------------------------------------
	var night := 1.0 - clampf(raw * 1.4, 0.0, 1.0)
	var dawn := clampf(1.0 - absf(sun_elevation) * 5.0, 0.0, 1.0) * clampf(raw * 3.0, 0.0, 1.0)
	top_color = pal.sky_top.lerp(pal.night_top, night)
	horizon_color = pal.sky_horizon.lerp(pal.night_horizon, night)
	horizon_color = horizon_color.lerp(pal.dawn_color, dawn * 0.55)
	ambient_color = pal.ambient_day.lerp(pal.ambient_night, night)
	fog_color = pal.fog_day.lerp(pal.fog_night, night)
	if wx != null:
		top_color = top_color.lerp(wx.tint, wx.tint_amount * 0.8)
		horizon_color = horizon_color.lerp(wx.tint, wx.tint_amount)
		ambient_color = ambient_color.lerp(wx.tint, wx.tint_amount * 0.7)
		fog_color = fog_color.lerp(wx.tint, wx.tint_amount)
	# Playability floor on sky contrast. Terrain has to silhouette against the
	# sky on *every* world, and the pale palettes (snow, desert, moon) drift so
	# close to the value of the blocks in front of them that the player appears
	# to stand on nothing. Cap how bright the sky may get and keep it saturated,
	# so blocks always read as blocks. Deliberately applied after the weather
	# tint, which would otherwise wash the cap straight back out.
	top_color = _skyfloor(top_color, SKY_MAX_VALUE_TOP)
	horizon_color = _skyfloor(horizon_color, SKY_MAX_VALUE_HORIZON)

	# Stars: atmospheric planets wash them out by day; airless ones never do.
	var atmospheric := clampf(1.0 - raw * 2.1, 0.0, 1.0)
	star_amount = lerpf(atmospheric, 1.0, pal.hardness) * pal.star_alpha
	if wx != null:
		star_amount *= wx.star_visibility

	_apply_lights(pal, wx, day, dawn, night, delta)
	_apply_environment(pal, wx, day, night)
	_apply_backdrop(pal, cam, sun_pos_dir, moon_pos_dir)
	_publish_globals(day)


func _apply_lights(pal: LitPlanet.Palette, wx: LitWeather, day: float,
		dawn: float, night: float, _delta: float) -> void:
	# `day` already carries the weather's `light_scale` (Lighting folds it in),
	# so only terms derived from `night` may apply it a second time.
	var weather_scale := wx.light_scale if wx != null else 1.0
	if sun != null:
		var above := clampf(sun_elevation * 6.0, 0.0, 1.0)
		var col := pal.sun_color.lerp(pal.dawn_color, dawn * 0.8)
		if wx != null:
			col = col.lerp(wx.tint, wx.tint_amount * 0.6)
		sun.light_color = col
		sun.light_energy = pal.sun_energy * day * above
		sun.visible = sun.light_energy > 0.005
		if sun.visible:
			_aim(sun, sun_dir)
		# Airless worlds: pitch-black shadows and a razor terminator.
		sun.shadow_enabled = true
		sun.light_angular_distance = lerpf(1.2, 0.05, pal.hardness)
		sun.shadow_blur = lerpf(1.0, 0.1, pal.hardness)
		sun.light_specular = lerpf(0.1, 0.35, pal.hardness)

	if fill != null:
		# By day: soft sky bounce from the opposite side. By night: the moon.
		var moon_energy := pal.moon_energy * (0.35 + 0.65 * moon_illumination) * night * weather_scale
		var day_energy := pal.fill_energy * (1.0 - pal.hardness) * day
		var use_moon := moon_energy > day_energy
		var e := maxf(moon_energy, day_energy)
		fill.light_energy = e
		fill.visible = e > 0.004
		fill.light_color = pal.moon_color if use_moon else pal.fill_color
		if fill.visible:
			if use_moon:
				_aim(fill, moon_dir)
			else:
				_aim(fill, Vector3(sun_dir.x * -0.6, -0.75, sun_dir.z * -0.6).normalized())
		fill.shadow_enabled = false


func _aim(light: DirectionalLight3D, dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	var d := dir.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.995:
		up = Vector3.FORWARD
	# A DirectionalLight3D shines down its local -Z.
	light.look_at_from_position(light.global_position, light.global_position + d, up)


func _apply_environment(pal: LitPlanet.Palette, wx: LitWeather, day: float, night: float) -> void:
	if env == null:
		return
	var amb_energy := pal.ambient_energy * lerpf(0.30, 1.0, day)
	var fog_d := pal.fog_density
	if wx != null:
		amb_energy *= wx.ambient_scale
		fog_d = fog_d * wx.fog_scale + wx.fog_add
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = maxf(0.02, amb_energy)
	# Depth-mode fog that only starts *beyond* the play slab.
	#
	# The camera is orthographic and sits a fixed ~44 blocks back, so every voxel
	# the player can see is at almost exactly the same view depth. Exponential
	# density fog therefore applies as a flat grey veil over the whole world and
	# communicates nothing. Ramping from just past the slab outward keeps the
	# playable layers crisp — the slab shader owns depth cueing — while distant
	# scenery and weather still haze over. Heavy weather drags the near edge in.
	env.fog_enabled = fog_d > 0.00005
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fog_color
	env.fog_depth_begin = lerpf(FOG_BEGIN_CLEAR, FOG_BEGIN_STORM,
		clampf(fog_d / 0.02, 0.0, 1.0))
	env.fog_depth_end = env.fog_depth_begin + 90.0
	env.fog_depth_curve = 1.0
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.background_energy_multiplier = lerpf(0.25, 1.0, clampf(day + 0.15, 0.0, 1.0))
	if sky_material != null:
		sky_material.sky_top_color = top_color
		sky_material.sky_horizon_color = horizon_color
		sky_material.ground_horizon_color = horizon_color.darkened(0.4)
		sky_material.ground_bottom_color = pal.sky_low
		sky_material.sun_angle_max = lerpf(14.0, 2.0, pal.hardness)
	# Glow gives emissive blocks (lava, crystals) a halo; pull it back at noon
	# so the surface does not bloom out.
	env.glow_enabled = true
	env.glow_intensity = lerpf(0.55, 0.28, day)


func _apply_backdrop(pal: LitPlanet.Palette, cam: Camera3D,
		sun_pos_dir: Vector3, moon_pos_dir: Vector3) -> void:
	if backdrop == null or not is_instance_valid(backdrop) or cam == null:
		return
	if backdrop_mat == null:
		return
	# Fit the quad to the orthographic box and park it at the far plane, where
	# ordinary depth testing keeps it behind every voxel.
	var vp := cam.get_viewport()
	var aspect := 1.777
	if vp != null:
		var vs := vp.get_visible_rect().size
		if vs.y > 0.0:
			aspect = vs.x / vs.y
	var half_h: float = cam.size * 0.5
	var half_w: float = half_h * aspect
	var want := Vector2(half_w * 2.1, half_h * 2.1)
	if backdrop_mesh.size.distance_to(want) > 0.05:
		backdrop_mesh.size = want
	backdrop.position = Vector3(0.0, 0.0, -maxf(1.0, cam.far * 0.94))

	var basis := cam.global_transform.basis
	var right := basis.x
	var forward := -basis.z
	var cam_y := cam.global_position.y

	backdrop_mat.set_shader_parameter(&"sky_top_col", _v3(top_color))
	backdrop_mat.set_shader_parameter(&"sky_hor_col", _v3(horizon_color))
	backdrop_mat.set_shader_parameter(&"sky_low_col", _v3(pal.sky_low))
	backdrop_mat.set_shader_parameter(&"cam_y", cam_y)
	backdrop_mat.set_shader_parameter(&"horizon_y", horizon_y)
	backdrop_mat.set_shader_parameter(&"span", sky_span)
	backdrop_mat.set_shader_parameter(&"t", _time)

	var sun_uv := _project(sun_pos_dir, right, forward, half_w, half_h, cam_y)
	var sun_face: float = clampf(sun_pos_dir.dot(forward), 0.0, 1.0)
	backdrop_mat.set_shader_parameter(&"sun_pos", sun_uv)
	backdrop_mat.set_shader_parameter(&"sun_col", _v3(pal.sun_color.lerp(pal.dawn_color, clampf(1.0 - absf(sun_elevation) * 4.0, 0.0, 1.0) * 0.7)))
	backdrop_mat.set_shader_parameter(&"sun_radius", maxf(0.4, half_h * 0.052))
	backdrop_mat.set_shader_parameter(&"sun_amt",
		clampf(sun_elevation * 8.0 + 0.35, 0.0, 1.0) * smoothstep(0.0, 0.3, sun_face))

	var moon_uv := _project(moon_pos_dir, right, forward, half_w, half_h, cam_y)
	var moon_face: float = clampf(moon_pos_dir.dot(forward), 0.0, 1.0)
	var moon_r: float = maxf(0.3, half_h * pal.moon_size)
	var waxing := 1.0 if fposmod(float(Game.day) / float(maxi(1, moon_cycle_days)), 1.0) < 0.5 else -1.0
	backdrop_mat.set_shader_parameter(&"moon_pos", moon_uv)
	backdrop_mat.set_shader_parameter(&"moon_col", _v3(pal.moon_tint))
	backdrop_mat.set_shader_parameter(&"moon_radius", moon_r)
	backdrop_mat.set_shader_parameter(&"moon_shadow", moon_illumination * 2.0 * moon_r * waxing)
	var moon_amt := 0.0
	if pal.moon_visible:
		moon_amt = clampf(moon_pos_dir.y * 8.0 + 0.3, 0.0, 1.0) \
			* smoothstep(0.0, 0.3, moon_face) * clampf(1.0 - Game.daylight * 1.6, 0.0, 1.0)
	backdrop_mat.set_shader_parameter(&"moon_amt", moon_amt)

	backdrop_mat.set_shader_parameter(&"star_col", _v3(pal.star_color))
	backdrop_mat.set_shader_parameter(&"star_amt", clampf(star_amount, 0.0, 1.5))
	backdrop_mat.set_shader_parameter(&"star_density", pal.star_density)
	# Pan the star field with the camera so flipping the view genuinely turns
	# the sky, instead of dragging the same stars around with you.
	backdrop_mat.set_shader_parameter(&"star_pan",
		View.current_yaw() * 37.0 + cam.global_position.x * 0.05 + cam.global_position.z * 0.05)


## Direction -> quad-local position, with the horizon anchored to world Y.
func _project(dir: Vector3, right: Vector3, forward: Vector3,
		half_w: float, half_h: float, cam_y: float) -> Vector2:
	var lateral := dir.dot(right)
	var depth := dir.dot(forward)
	# Spread the arc across the screen even when the sun is nearly edge-on.
	var u: float = clampf(lateral, -1.0, 1.0) * half_w * 0.72
	var horizon_local := clampf(horizon_y - cam_y, -half_h * 0.9, half_h * 0.9)
	var v: float = horizon_local + dir.y * half_h * 0.85
	return Vector2(u, clampf(v, -half_h * 0.98, half_h * 0.98))


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func moon_phase_name() -> String:
	return PHASE_NAMES[moon_phase_index % 8]


# --------------------------------------------------------------- shader globals
## Publish the sky state as `lit_*` global shader uniforms. Any shader in the
## project can declare `global uniform vec3 lit_ambient_color;` and pick these
## up — in particular the voxel slab shader, which should tint far layers
## *toward* `lit_fog_color`, not toward black. That is what makes distance read
## as distance. Prefixed so no other agent's uniform can collide.
func _register_globals() -> void:
	if _globals_ready:
		return
	_globals_ready = true
	_add_global(&"lit_sun_dir", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.DOWN)
	_add_global(&"lit_sun_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color.WHITE)
	_add_global(&"lit_ambient_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.6, 0.66, 0.78))
	_add_global(&"lit_fog_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.32, 0.4, 0.55))
	_add_global(&"lit_sky_color", RenderingServer.GLOBAL_VAR_TYPE_COLOR, Color(0.62, 0.72, 0.86))
	_add_global(&"lit_daylight", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 1.0)
	## Reference strength for the renderer's depth cueing, 0..1. Weather and
	## planet mood raise it (a foggy world buries the back layers faster).
	_add_global(&"lit_depth_strength", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.72)


## Names this module has already registered. Both `global_shader_parameter_get`
## and `..._get_list` are editor-only and log a performance error at runtime, so
## membership is tracked here instead of asking the rendering server.
static var _registered_globals: Dictionary = {}


func _add_global(n: StringName, type: int, value: Variant) -> void:
	if _registered_globals.has(n):
		return
	_registered_globals[n] = true
	RenderingServer.global_shader_parameter_add(n, type, value)


func _publish_globals(day: float) -> void:
	RenderingServer.global_shader_parameter_set(&"lit_sun_dir", sun_dir)
	RenderingServer.global_shader_parameter_set(&"lit_sun_color",
		sun.light_color if sun != null else Color.WHITE)
	RenderingServer.global_shader_parameter_set(&"lit_ambient_color", ambient_color)
	RenderingServer.global_shader_parameter_set(&"lit_fog_color", fog_color)
	RenderingServer.global_shader_parameter_set(&"lit_sky_color", horizon_color)
	RenderingServer.global_shader_parameter_set(&"lit_daylight", day)
	var extra := 0.0
	if Lighting.weather != null:
		extra = Lighting.weather.depth_boost
	RenderingServer.global_shader_parameter_set(&"lit_depth_strength", clampf(0.72 + extra, 0.0, 0.95))
