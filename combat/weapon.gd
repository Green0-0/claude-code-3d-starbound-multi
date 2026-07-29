## The behaviour driver for a held weapon.
##
## One `CbtWeapon` instance belongs to one wielder (the player, or a monster
## that uses real weapons). Point it at an [ItemStack] of `Kind.WEAPON` and it
## runs that weapon's whole feel: wind-up, active frames, recovery, combo
## chains, charge shots, energy cost, durability drain and the per-archetype
## logic that makes a hammer read differently from a dagger.
##
## ## Player integration (the API the player agent should call)
##
## ```gdscript
## var weapon := CbtWeapon.new(self)                 # `self` = the wielder
##
## func _physics_process(delta):
##     weapon.equip(inventory.held_stack())          # cheap; ignores no-ops
##     weapon.aim_at(mouse_world_position)           # or weapon.set_aim_dir(v2)
##     if Input.is_action_just_pressed("primary"):   weapon.press_primary()
##     if Input.is_action_just_released("primary"):  weapon.release_primary()
##     if Input.is_action_just_pressed("secondary"): weapon.press_secondary()
##     if Input.is_action_just_released("secondary"):weapon.release_secondary()
##     weapon.update(delta)                          # ALWAYS last
##
## func modify_incoming_damage(amount, element, source) -> float:
##     return weapon.absorb(amount, element, source) # shields / parries
## ```
##
## Read-only state for animation and HUD: [method state_name],
## [method charge_fraction], [method cooldown_fraction], [method combo_index],
## [method is_busy], [method swing_progress].
##
## ## The plane rule
##
## Every melee hitbox this class builds defaults to `CbtDamage.LAYER_SAME`: a
## swing hits only things standing in your own depth layer. A monster one voxel
## behind you is drawn, animated and completely safe from your sword. Weapons
## escape that only if their item data says so — `layer_rule`, `layer_min`,
## `layer_max` are read straight off the [ItemStack], which is how
## `phase_lance`, `depth_charge_launcher` and `revenant_edge` work.
class_name CbtWeapon
extends RefCounted

# ------------------------------------------------------------------ archetypes
const BROADSWORD := &"broadsword"
const SHORTSWORD := &"shortsword"
const SPEAR := &"spear"
const HAMMER := &"hammer"
const DAGGER := &"dagger"
const WHIP := &"whip"
const SHIELD := &"shield"
const BOW := &"bow"
const GUN := &"gun"
const SHOTGUN := &"shotgun"
const ROCKET := &"rocket"
const FLAMETHROWER := &"flamethrower"
const STAFF := &"staff"
const BOOMERANG := &"boomerang"
const GRENADE := &"grenade"
const BEAMDRILL := &"beamdrill"

const ALL_ARCHETYPES := [
	BROADSWORD, SHORTSWORD, SPEAR, HAMMER, DAGGER, WHIP, SHIELD,
	BOW, GUN, SHOTGUN, ROCKET, FLAMETHROWER, STAFF, BOOMERANG, GRENADE, BEAMDRILL,
]

# ----------------------------------------------------------------- the states
enum State { IDLE, WINDUP, ACTIVE, RECOVERY, CHARGING, BLOCKING }

## Fired the instant an attack commits (after the energy check).
signal attack_started(archetype: StringName, combo: int)
## Fired per entity struck.
signal attack_landed(entity: VoxelEntity, damage: float)
## Fired when the recovery frames end and the weapon is usable again.
signal attack_finished(archetype: StringName)
## Fired when durability hits zero.
signal weapon_broke(stack: ItemStack)
## A charge attack reached full power.
signal charge_ready()
## A shield parry succeeded against `attacker`.
signal parried(attacker: Node)
## An attack was refused for lack of energy.
signal out_of_energy(needed: float)

## Per-archetype tuning. Times are in seconds at attack_speed 1.0.
##
## `windup`/`active`/`recovery` are the three phases. `reach` is plane-space
## blocks. `arc` is the total sweep in degrees, `arc_offset` where it starts
## relative to the aim. `combo` is the number of chained swings.
const ARCHETYPES := {
	BROADSWORD: {
		"windup": 0.16, "active": 0.14, "recovery": 0.22, "reach": 3.0,
		"arc": 130.0, "arc_offset": 62.0, "combo": 2, "energy": 0.0,
		"knockback_mult": 1.35, "damage_mult": 1.0, "hitstop": 0.5,
		"durability": 1, "inner": 0.35, "max_hits": 0, "two_handed": true,
		"desc": "A wide overhead arc. Hits everything in the fan, once each.",
	},
	SHORTSWORD: {
		"windup": 0.07, "active": 0.09, "recovery": 0.1, "reach": 2.2,
		"arc": 85.0, "arc_offset": 40.0, "combo": 3, "energy": 0.0,
		"knockback_mult": 0.8, "damage_mult": 0.72, "hitstop": 0.22,
		"durability": 1, "inner": 0.2, "max_hits": 0,
		"desc": "Three-hit chain; the finisher launches.",
	},
	SPEAR: {
		"windup": 0.18, "active": 0.12, "recovery": 0.26, "reach": 4.6,
		"arc": 0.0, "arc_offset": 0.0, "combo": 2, "energy": 0.0,
		"knockback_mult": 1.1, "damage_mult": 1.05, "hitstop": 0.35,
		"durability": 1, "thickness": 0.45, "thrust": true, "pierce_entities": 3,
		"desc": "A long thrust that skewers everything on the line.",
	},
	HAMMER: {
		"windup": 0.38, "active": 0.16, "recovery": 0.42, "reach": 2.9,
		"arc": 150.0, "arc_offset": 80.0, "combo": 1, "energy": 0.0,
		"knockback_mult": 2.6, "damage_mult": 1.75, "hitstop": 1.0,
		"durability": 2, "inner": 0.0, "breaks_blocks": 2, "shockwave": 3.2,
		"desc": "Slow, enormous, and it smashes the terrain it lands on.",
	},
	DAGGER: {
		"windup": 0.05, "active": 0.07, "recovery": 0.08, "reach": 1.7,
		"arc": 55.0, "arc_offset": 26.0, "combo": 4, "energy": 0.0,
		"knockback_mult": 0.4, "damage_mult": 0.5, "hitstop": 0.15,
		"durability": 1, "backstab": 2.6, "crit_bonus": 0.15,
		"desc": "Fast four-hit flurry. Massive bonus from behind.",
	},
	WHIP: {
		"windup": 0.14, "active": 0.26, "recovery": 0.2, "reach": 5.4,
		"arc": 110.0, "arc_offset": 55.0, "combo": 2, "energy": 0.0,
		"knockback_mult": 1.6, "damage_mult": 0.6, "hitstop": 0.2,
		"durability": 1, "thickness": 0.35, "multi_hit": 0.09, "extends": true,
		"desc": "Cracks outward over the whole active window, hitting repeatedly.",
	},
	SHIELD: {
		"windup": 0.06, "active": 0.1, "recovery": 0.18, "reach": 1.6,
		"arc": 70.0, "arc_offset": 34.0, "combo": 1, "energy": 0.0,
		"knockback_mult": 2.2, "damage_mult": 0.35, "hitstop": 0.4,
		"durability": 1, "block_ratio": 0.72, "parry_window": 0.22,
		"parry_stagger": 1.4, "block_drain": 0.35,
		"desc": "Hold to block. Release-time parry reflects and staggers.",
	},

	# --------------------------------------------------------------- ranged
	BOW: {
		"windup": 0.0, "active": 0.05, "recovery": 0.2, "reach": 0.0,
		"combo": 1, "energy": 0.0, "damage_mult": 1.0, "hitstop": 0.2,
		"durability": 1, "ranged": true, "projectile": &"arrow",
		"charge": true, "charge_min": 0.16, "charge_max": 0.85,
		"charge_damage": 2.6, "charge_speed": 1.9, "two_handed": true,
		"desc": "Draw to full for a flat, fast, hard-hitting shot.",
	},
	GUN: {
		"windup": 0.0, "active": 0.03, "recovery": 0.14, "reach": 0.0,
		"combo": 1, "energy": 2.0, "damage_mult": 0.85, "hitstop": 0.14,
		"durability": 1, "ranged": true, "projectile": &"bullet",
		"auto": true, "spread": 3.0, "recoil": 1.6,
		"desc": "Fast, flat, cheap. The shot crosses the screen almost instantly.",
	},
	SHOTGUN: {
		"windup": 0.04, "active": 0.05, "recovery": 0.46, "reach": 0.0,
		"combo": 1, "energy": 5.0, "damage_mult": 0.42, "hitstop": 0.6,
		"durability": 1, "ranged": true, "projectile": &"pellet",
		"shots": 7, "spread": 26.0, "recoil": 7.0, "two_handed": true,
		"desc": "Seven pellets. Devastating in your face, useless at range.",
	},
	ROCKET: {
		"windup": 0.1, "active": 0.06, "recovery": 0.75, "reach": 0.0,
		"combo": 1, "energy": 18.0, "damage_mult": 1.0, "hitstop": 0.8,
		"durability": 2, "ranged": true, "projectile": &"rocket",
		"recoil": 9.0, "two_handed": true, "self_damage": 0.35,
		"desc": "Explodes on contact, carves the terrain, and hurts you too.",
	},
	FLAMETHROWER: {
		"windup": 0.08, "active": 0.1, "recovery": 0.04, "reach": 6.0,
		"combo": 1, "energy": 1.1, "damage_mult": 0.3, "hitstop": 0.0,
		"durability": 0, "ranged": true, "projectile": &"flame_gout",
		"auto": true, "cone": 22.0, "shots": 2, "spread": 20.0,
		"multi_hit": 0.12, "two_handed": true,
		"desc": "A continuous cone. Damage is small per tick and relentless.",
	},
	STAFF: {
		"windup": 0.12, "active": 0.05, "recovery": 0.34, "reach": 0.0,
		"combo": 1, "energy": 9.0, "damage_mult": 0.85, "hitstop": 0.2,
		"durability": 0, "ranged": true, "projectile": &"star_bolt",
		"shots": 3, "spread": 34.0, "charge": true, "charge_min": 0.0,
		"charge_max": 0.6, "charge_damage": 1.5, "two_handed": true,
		"desc": "Fires a spray of bolts that hunt down whatever you looked at.",
	},
	BOOMERANG: {
		"windup": 0.08, "active": 0.05, "recovery": 0.3, "reach": 0.0,
		"combo": 1, "energy": 0.0, "damage_mult": 0.8, "hitstop": 0.25,
		"durability": 1, "ranged": true, "projectile": &"boomerang",
		"one_at_a_time": true,
		"desc": "Comes back. Hits on the way out and on the way home.",
	},
	GRENADE: {
		"windup": 0.14, "active": 0.05, "recovery": 0.4, "reach": 0.0,
		"combo": 1, "energy": 6.0, "damage_mult": 1.0, "hitstop": 0.5,
		"durability": 1, "ranged": true, "projectile": &"grenade",
		"charge": true, "charge_min": 0.0, "charge_max": 0.7,
		"charge_speed": 2.0, "lob": true, "self_damage": 0.5,
		"desc": "Hold to throw further. Cooks on a fuse, not on contact.",
	},
	BEAMDRILL: {
		"windup": 0.05, "active": 0.08, "recovery": 0.03, "reach": 5.0,
		"combo": 1, "energy": 1.6, "damage_mult": 0.34, "hitstop": 0.0,
		"durability": 0, "ranged": true, "projectile": &"drill_beam",
		"auto": true, "mines": true, "mine_tier": 4, "multi_hit": 0.1,
		"desc": "A mining beam that is perfectly happy to be pointed at people.",
	},
}

# ------------------------------------------------------------------ live state
var wielder: Node3D = null
var state: State = State.IDLE
## Aim direction in plane space (lateral, up). Normalised.
var aim: Vector2 = Vector2.RIGHT
## Set false to make the weapon inert (cutscenes, menus, stun).
var enabled: bool = true

var _stack: ItemStack = null
var _arch: StringName = BROADSWORD
var _cfg: Dictionary = ARCHETYPES[BROADSWORD]
var _phase_t: float = 0.0
var _phase_len: float = 0.0
var _combo: int = 0
var _combo_timer: float = 0.0
var _charge: float = 0.0
var _charged_release: float = 0.0
var _primary_held: bool = false
var _secondary_held: bool = false
var _auto_timer: float = 0.0
var _hitbox: CbtHitbox = null
var _swing_from: float = 0.0
var _swing_to: float = 0.0
var _block_time: float = 0.0
var _block_energy: float = 0.0
var _live_boomerang: CbtProjectile = null
var _fx_origin: Vector2 = Vector2.ZERO
var _rng := RandomNumberGenerator.new()

const COMBO_WINDOW := 0.55


func _init(p_wielder: Node3D = null) -> void:
	wielder = p_wielder
	_rng.randomize()


# =============================================================== equip / query
## Point the driver at a stack. Passing the same stack again is a no-op, so it
## is safe (and intended) to call this every frame from the player.
func equip(new_stack: ItemStack) -> void:
	if new_stack == _stack:
		return
	if _stack != null and new_stack != null and not _stack.is_empty() \
			and _stack.id == new_stack.id and _stack.data == new_stack.data:
		_stack = new_stack
		return
	cancel()
	_stack = new_stack
	_arch = archetype_of(new_stack)
	_cfg = ARCHETYPES.get(_arch, ARCHETYPES[BROADSWORD])
	_combo = 0
	_charge = 0.0


func stack() -> ItemStack:
	return _stack


## The archetype currently driving behaviour.
func archetype() -> StringName:
	return _arch


## Resolve an item's archetype: explicit `data.archetype`, then the item type's
## `weapon_archetype` flag, then a guess from the id's suffix, then the item's
## tags. Falls back to [constant BROADSWORD].
static func archetype_of(s: ItemStack) -> StringName:
	if s == null or s.is_empty():
		return BROADSWORD
	var a: Variant = s.stat("archetype", &"")
	if a != null and StringName(a) != &"" and ARCHETYPES.has(StringName(a)):
		return StringName(a)
	var t := s.type()
	if t != null:
		for tag: StringName in t.tags:
			if ARCHETYPES.has(tag):
				return tag
	var id := String(s.id)
	for k: StringName in ALL_ARCHETYPES:
		if id.ends_with("_" + String(k)) or id == String(k):
			return k
	# Common English names that are not the archetype key.
	if id.ends_with("_sword") or id.ends_with("_blade"):
		return BROADSWORD
	if id.ends_with("_axe") or id.ends_with("_maul") or id.ends_with("_mace"):
		return HAMMER
	if id.ends_with("_knife") or id.ends_with("_shiv"):
		return DAGGER
	if id.ends_with("_pistol") or id.ends_with("_rifle") or id.ends_with("_smg"):
		return GUN
	if id.ends_with("_launcher") or id.ends_with("_bazooka"):
		return ROCKET
	if id.ends_with("_wand") or id.ends_with("_scepter"):
		return STAFF
	if id.ends_with("_lance") or id.ends_with("_pike") or id.ends_with("_trident"):
		return SPEAR
	return BROADSWORD


## Tuning dictionary for an archetype, merged with nothing — read-only.
static func config_of(a: StringName) -> Dictionary:
	return ARCHETYPES.get(a, ARCHETYPES[BROADSWORD])


## Hand-authored uniques declare their special with a `&"special_<id>"` tag,
## since [ItemType] has no field for one. Generated weapons use `data.special`.
static func special_from_tags(s: ItemStack) -> StringName:
	if s == null or s.is_empty():
		return &""
	var t := s.type()
	if t == null:
		return &""
	for tag: StringName in t.tags:
		var st := String(tag)
		if st.begins_with("special_"):
			return StringName(st.substr(8))
	return &""


func is_busy() -> bool:
	return state != State.IDLE and state != State.BLOCKING


func can_attack() -> bool:
	return enabled and state == State.IDLE and _stack != null and not _stack.is_empty()


func is_ranged() -> bool:
	return bool(_cfg.get("ranged", false))


func is_blocking() -> bool:
	return state == State.BLOCKING


## 0..1 through the current phase; 1.0 when idle.
func cooldown_fraction() -> float:
	if state == State.IDLE:
		return 1.0
	return clampf(_phase_t / maxf(0.0001, _phase_len), 0.0, 1.0)


## 0..1 charge level for bows, staves and grenades.
func charge_fraction() -> float:
	var cmax := float(_cfg.get("charge_max", 1.0))
	return clampf(_charge / maxf(0.0001, cmax), 0.0, 1.0)


## Which link of the combo chain the next swing will be (0-based).
func combo_index() -> int:
	return _combo


## 0..1 through the active frames — drives the arm animation.
func swing_progress() -> float:
	if state != State.ACTIVE:
		return 0.0
	return clampf(_phase_t / maxf(0.0001, _phase_len), 0.0, 1.0)


func state_name() -> String:
	match state:
		State.WINDUP: return "windup"
		State.ACTIVE: return "active"
		State.RECOVERY: return "recovery"
		State.CHARGING: return "charging"
		State.BLOCKING: return "blocking"
	return "idle"


## Attacks per second at the current attack_speed, for the HUD.
func attacks_per_second() -> float:
	var total := (float(_cfg.get("windup", 0.1)) + float(_cfg.get("active", 0.1))
		+ float(_cfg.get("recovery", 0.2))) / maxf(0.05, _speed())
	return 1.0 / maxf(0.01, total)


# ======================================================================= aiming
## Aim at a world position (the mouse cursor projected into the world).
func aim_at(world_pos: Vector3) -> void:
	if wielder == null:
		return
	var d := View.to_plane(world_pos) - _origin()
	if d.length_squared() > 0.0004:
		aim = d.normalized()
		_face_aim()


## Aim with an explicit plane-space direction.
func set_aim_dir(dir: Vector2) -> void:
	if dir.length_squared() > 0.0004:
		aim = dir.normalized()
		_face_aim()


func _face_aim() -> void:
	var ve := wielder as VoxelEntity
	if ve != null and absf(aim.x) > 0.15 and not is_busy():
		ve.facing = 1 if aim.x > 0.0 else -1


# ======================================================================= input
## Begin the primary action. Returns true when something actually started.
func press_primary() -> bool:
	_primary_held = true
	if not enabled or _stack == null or _stack.is_empty():
		return false
	if bool(_cfg.get("charge", false)):
		if state != State.IDLE:
			return false
		state = State.CHARGING
		_charge = 0.0
		Events.play_sound.emit(&"charge_start", _world_origin())
		return true
	return _try_begin_attack()


## Release the primary action. Fires charge weapons.
func release_primary() -> void:
	_primary_held = false
	if state == State.CHARGING:
		_charged_release = _charge
		var cmin := float(_cfg.get("charge_min", 0.0))
		if _charge < cmin:
			# Released too early: the shot is aborted, not weakened to nothing.
			state = State.IDLE
			_charge = 0.0
			return
		state = State.IDLE
		_try_begin_attack()
		_charge = 0.0


## Secondary: raise a shield, or fire the weapon's special.
func press_secondary() -> bool:
	_secondary_held = true
	if not enabled or _stack == null or _stack.is_empty():
		return false
	if _arch == SHIELD or bool(_stack.stat("can_block", false)):
		if state != State.IDLE:
			return false
		state = State.BLOCKING
		_block_time = 0.0
		Events.play_sound.emit(&"block_raise", _world_origin())
		return true
	return use_special()


func release_secondary() -> void:
	_secondary_held = false
	if state == State.BLOCKING:
		state = State.IDLE
		_block_time = 0.0


## Abort whatever is happening. Called on death, flip, stun, weapon swap.
func cancel() -> void:
	state = State.IDLE
	_phase_t = 0.0
	_charge = 0.0
	_primary_held = false
	_secondary_held = false
	if _hitbox != null:
		_hitbox.active = false
		_hitbox = null


# ======================================================================= update
## Drive the state machine. Call once per physics frame, after setting the aim.
func update(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
	if _stack == null or _stack.is_empty() or not enabled:
		if state != State.IDLE:
			cancel()
		return

	match state:
		State.CHARGING:
			var was := charge_fraction()
			_charge += delta
			if was < 1.0 and charge_fraction() >= 1.0:
				charge_ready.emit()
				Events.play_sound.emit(&"charge_full", _world_origin())
		State.BLOCKING:
			_block_time += delta
			_tick_block(delta)
		State.WINDUP:
			_phase_t += delta
			if _phase_t >= _phase_len:
				_enter_active()
		State.ACTIVE:
			_phase_t += delta
			_tick_active(delta)
			if _phase_t >= _phase_len:
				_enter_recovery()
		State.RECOVERY:
			_phase_t += delta
			if _phase_t >= _phase_len:
				state = State.IDLE
				_phase_t = 0.0
				attack_finished.emit(_arch)
		State.IDLE:
			if _primary_held and bool(_cfg.get("auto", false)):
				_auto_timer -= delta
				if _auto_timer <= 0.0:
					_try_begin_attack()


# ================================================================ attack start
func _try_begin_attack() -> bool:
	if state != State.IDLE or _stack == null or _stack.is_empty():
		return false
	if bool(_cfg.get("one_at_a_time", false)) and _live_boomerang != null \
			and is_instance_valid(_live_boomerang) and _live_boomerang.alive:
		return false
	var cost := energy_cost()
	if not _spend_energy(cost):
		out_of_energy.emit(cost)
		Events.play_sound.emit(&"denied", _world_origin())
		return false
	_phase_len = maxf(0.0001, float(_cfg.get("windup", 0.1)) / _speed())
	_phase_t = 0.0
	state = State.WINDUP
	_fx_origin = _origin()
	_prepare_swing()
	attack_started.emit(_arch, _combo)
	Events.play_sound.emit(&"swing_windup", _world_origin())
	if _phase_len <= 0.001:
		_enter_active()
	return true


## The energy this attack will cost, after charge and status modifiers.
func energy_cost() -> float:
	var base := float(_cfg.get("energy", 0.0))
	base = float(_stack.stat("energy_cost", base)) if _stack != null else base
	if bool(_cfg.get("charge", false)):
		base *= 0.6 + 0.8 * clampf(_charged_release / maxf(0.001, float(_cfg.get("charge_max", 1.0))), 0.0, 1.0)
	# The `energy_cost` status/tech modifier is applied by the wielder's own
	# `spend_energy`, so it deliberately is NOT applied again here.
	return maxf(0.0, base)


func _prepare_swing() -> void:
	var base := rad_to_deg(atan2(aim.y, aim.x))
	var arc := float(_cfg.get("arc", 0.0))
	var off := float(_cfg.get("arc_offset", arc * 0.5))
	# Alternate the swing direction each combo step so a chain reads as a chain.
	var down := (_combo % 2) == 0
	if down:
		_swing_from = base + off
		_swing_to = base - (arc - off)
	else:
		_swing_from = base - (arc - off)
		_swing_to = base + off


func _enter_active() -> void:
	state = State.ACTIVE
	_phase_t = 0.0
	_phase_len = maxf(0.0001, float(_cfg.get("active", 0.1)) / _speed())
	_fx_origin = _origin()
	if is_ranged():
		_fire_ranged()
	else:
		_open_melee_hitbox()
	Events.play_sound.emit(_swing_sound(), _world_origin())


func _enter_recovery() -> void:
	if _hitbox != null:
		_hitbox.active = false
		_hitbox = null
	state = State.RECOVERY
	_phase_t = 0.0
	_phase_len = maxf(0.0001, float(_cfg.get("recovery", 0.2)) / _speed())
	_combo = (_combo + 1) % maxi(1, int(_cfg.get("combo", 1)))
	_combo_timer = COMBO_WINDOW
	_auto_timer = 0.0
	_drain_durability(int(_cfg.get("durability", 1)))


# ================================================================ melee attacks
func _open_melee_hitbox() -> void:
	var reach := float(_cfg.get("reach", 2.0)) * float(_stack.stat("reach_mult", 1.0))
	var origin := _origin()
	var hb: CbtHitbox
	if bool(_cfg.get("thrust", false)):
		hb = CbtHitbox.capsule_box(origin, origin + aim * reach,
			float(_cfg.get("thickness", 0.4)))
		hb.max_hits = int(_cfg.get("pierce_entities", 0))
	elif bool(_cfg.get("extends", false)):
		# The whip grows outward across its active window.
		hb = CbtHitbox.capsule_box(origin, origin + aim * 0.5,
			float(_cfg.get("thickness", 0.35)))
	else:
		hb = CbtHitbox.arc_box(origin, reach, -6.0, 6.0,
			reach * float(_cfg.get("inner", 0.25)))
		hb.direction = Vector2.RIGHT   # arc_from/arc_to are absolute degrees
	hb.packet = _base_packet()
	hb.owner_node = wielder
	hb.duration = _phase_len
	hb.rehit_interval = float(_cfg.get("multi_hit", 0.0))
	hb.hit.connect(_on_hitbox_hit)
	_hitbox = hb

	# Visuals.
	var col := CbtMeleeFx.element_color(String(_stack.stat("element", Const.ELEM_PHYSICAL)))
	if bool(_cfg.get("thrust", false)):
		CbtMeleeFx.slash(origin, aim, reach, 0.28, col, _phase_len + 0.06)
	elif not bool(_cfg.get("extends", false)):
		CbtMeleeFx.swing_arc(origin, reach, _swing_from, _swing_to, col, _phase_len + 0.1,
			_fx_depth())
	if bool(_cfg.get("breaks_blocks", false)) or int(_cfg.get("breaks_blocks", 0)) > 0:
		_smash_blocks(int(_cfg.get("breaks_blocks", 0)))


func _tick_active(delta: float) -> void:
	if _hitbox == null:
		return
	var f := swing_progress()
	var origin := _origin()
	if bool(_cfg.get("thrust", false)):
		var reach := float(_cfg.get("reach", 2.0)) * float(_stack.stat("reach_mult", 1.0))
		var tip := origin + aim * reach * (0.35 + 0.65 * minf(1.0, f * 1.8))
		_hitbox.origin = origin
		_hitbox.capsule_end = tip
		_hitbox.sweep(delta)
	elif bool(_cfg.get("extends", false)):
		var reach2 := float(_cfg.get("reach", 5.0)) * float(_stack.stat("reach_mult", 1.0))
		# A whip lashes out and snaps back.
		var ext := sin(f * PI) * reach2
		var ang := deg_to_rad(lerpf(_swing_from, _swing_to, f))
		_hitbox.origin = origin
		_hitbox.capsule_end = origin + Vector2(cos(ang), sin(ang)) * maxf(0.4, ext)
		_hitbox.sweep(delta)
		if int(f * 40.0) % 3 == 0:
			CbtMeleeFx.slash(origin, Vector2(cos(ang), sin(ang)), ext, 0.14,
				CbtMeleeFx.element_color(String(_stack.stat("element", Const.ELEM_PHYSICAL))), 0.1)
	else:
		# A narrow blade window travels along the swing: a real swept hitbox,
		# so a fast monster cannot slip between two frames of the arc.
		var a := lerpf(_swing_from, _swing_to, maxf(0.0, f - 0.18))
		var b := lerpf(_swing_from, _swing_to, minf(1.0, f + 0.18))
		_hitbox.arc_from = minf(a, b)
		_hitbox.arc_to = maxf(a, b)
		_hitbox.origin = origin
		_hitbox.sweep(delta)


func _smash_blocks(tier: int) -> void:
	if tier <= 0 or wielder == null:
		return
	var reach := float(_cfg.get("reach", 2.5))
	var from := _world_origin()
	var dir := View.plane_dir_to_world(aim)
	var hit := World.raycast(from, dir, reach)
	if not bool(hit.get("hit", false)):
		return
	var pos: Vector3i = hit.get("pos", Vector3i.ZERO)
	World.break_block(pos, tier, true)
	Game.bump_stat("blocks_mined", 1.0)
	var shock := float(_cfg.get("shockwave", 0.0))
	if shock > 0.0:
		var at := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
		CbtMeleeFx.ring(at, shock, Color(0.9, 0.8, 0.6), 0.28)
		var p := _base_packet()
		p["amount"] = float(p.get("amount", 1.0)) * 0.4
		p["knockback"] = float(p.get("knockback", 0.0)) * 0.6
		p["can_crit"] = false
		CbtDamage.apply_radial(at, shock, p, wielder)


func _on_hitbox_hit(entity: VoxelEntity, damage: float) -> void:
	attack_landed.emit(entity, damage)
	var element := String(_stack.stat("element", Const.ELEM_PHYSICAL)) if _stack != null \
		else Const.ELEM_PHYSICAL
	CbtMeleeFx.hit_feedback(entity.aabb_center(), element,
		float(_cfg.get("hitstop", 0.3)), false)
	# The dagger's whole identity: hitting something that is not looking at you.
	var lifesteal := float(_stack.stat("lifesteal", 0.0)) if _stack != null else 0.0
	if lifesteal > 0.0 and wielder != null and wielder.has_method(&"heal"):
		wielder.call(&"heal", damage * lifesteal)


# =============================================================== ranged attacks
func _fire_ranged() -> void:
	var proj := StringName(_stack.stat("projectile", _cfg.get("projectile", &"bullet")))
	if not CbtProjectileTypes.has(proj):
		proj = StringName(_cfg.get("projectile", &"bullet"))
	var charge_f := 0.0
	if bool(_cfg.get("charge", false)):
		charge_f = clampf(_charged_release / maxf(0.001, float(_cfg.get("charge_max", 1.0))), 0.0, 1.0)

	var ov := _projectile_overrides(charge_f)
	var origin := _muzzle_world()
	var dir := aim
	if bool(_cfg.get("lob", false)):
		dir = _lob_dir(charge_f)
	var spread := float(_cfg.get("spread", 0.0))
	var shots := int(_cfg.get("shots", 1))

	if _arch == FLAMETHROWER:
		_fire_flame(origin, ov)
	elif shots > 1:
		CbtProjectile.spawn_spread(proj, origin, dir, shots, spread, wielder, ov)
	else:
		if spread > 0.0:
			var a := deg_to_rad(rad_to_deg(atan2(dir.y, dir.x)) + _rng.randf_range(-spread, spread) * 0.5)
			dir = Vector2(cos(a), sin(a))
		var p := CbtProjectile.spawn(proj, origin, dir, wielder, ov)
		if _arch == BOOMERANG:
			_live_boomerang = p
		if _arch == STAFF and p != null:
			p.homing = maxf(p.homing, 4.0)

	if bool(_cfg.get("mines", false)):
		_drill_mine()

	CbtMeleeFx.muzzle(_origin(), dir, 0.5 + 0.5 * charge_f,
		CbtMeleeFx.element_color(String(_stack.stat("element", Const.ELEM_PHYSICAL))))
	_apply_recoil(charge_f)
	_self_damage_check(origin)


func _projectile_overrides(charge_f: float) -> Dictionary:
	var dmg := float(_stack.stat("damage", 8.0)) * float(_cfg.get("damage_mult", 1.0))
	var speed_mult := 1.0
	if bool(_cfg.get("charge", false)):
		dmg *= lerpf(1.0, float(_cfg.get("charge_damage", 1.0)), charge_f)
		speed_mult = lerpf(0.62, float(_cfg.get("charge_speed", 1.0)), charge_f)
	var ov := {
		"damage": dmg,
		"weapon": _stack,
		"crit_chance": float(_stack.stat("crit_chance", 0.05)),
		"crit_mult": float(_stack.stat("crit_mult", 1.75)),
		"armor_pierce": float(_stack.stat("armor_pierce", 0.0)),
		"knockback": float(_stack.stat("knockback", 3.0)) * float(_cfg.get("knockback_mult", 1.0)),
		"origin_layer": _layer(),
	}
	var elem := String(_stack.stat("element", ""))
	if elem != "":
		ov["element"] = elem
	# Item data or planar tags may override the depth rule — this is how a phase
	# lance, a depth charge and an echo dart differ from an ordinary gun.
	var planar := CbtDamage.planar_rule(_stack)
	for k: String in planar:
		ov[k] = planar[k]
	var st: Variant = _stack.stat("status_on_hit", null)
	if st is Array and not (st as Array).is_empty():
		ov["status_on_hit"] = (st as Array).duplicate(true)
	if speed_mult != 1.0:
		ov["speed"] = float(CbtProjectileTypes.get_def(
			StringName(_stack.stat("projectile", _cfg.get("projectile", &"bullet"))))
			.get("speed", 22.0)) * speed_mult
	return ov


func _fire_flame(origin: Vector3, ov: Dictionary) -> void:
	var cone := float(_cfg.get("cone", 22.0))
	CbtProjectile.spawn_spread(&"flame_gout", origin, aim,
		int(_cfg.get("shots", 2)), float(_cfg.get("spread", 18.0)), wielder, ov)
	# The gouts are visual and incidental; the reliable damage is the cone.
	var hb := CbtHitbox.cone_box(_origin(), aim, float(_cfg.get("reach", 6.0)), cone)
	hb.packet = _base_packet()
	hb.owner_node = wielder
	hb.duration = _phase_len
	hb.rehit_interval = float(_cfg.get("multi_hit", 0.12))
	hb.hit.connect(_on_hitbox_hit)
	hb.resolve()


func _drill_mine() -> void:
	var tier := int(_stack.stat("mine_tier", _cfg.get("mine_tier", 3)))
	var reach := float(_cfg.get("reach", 5.0)) * float(_stack.stat("reach_mult", 1.0))
	var hit := World.raycast(_world_origin(), View.plane_dir_to_world(aim), reach)
	if not bool(hit.get("hit", false)):
		return
	var pos: Vector3i = hit.get("pos", Vector3i.ZERO)
	World.break_block(pos, tier, true)
	Game.bump_stat("blocks_mined", 1.0)
	Events.spawn_particles.emit(&"drill_sparks", Vector3(pos) + Vector3(0.5, 0.5, 0.5), 4)


func _lob_dir(charge_f: float) -> Vector2:
	# Throwing arcs upward; more charge means a flatter, longer throw.
	var lift := lerpf(0.55, 0.22, charge_f)
	return Vector2(aim.x, aim.y + lift).normalized()


func _apply_recoil(charge_f: float) -> void:
	var r := float(_cfg.get("recoil", 0.0))
	if r <= 0.0:
		return
	var ve := wielder as VoxelEntity
	if ve == null:
		return
	var push := -aim * r * (0.6 + 0.4 * charge_f)
	ve.velocity += View.plane_dir_to_world(push)
	if r >= 5.0:
		CbtMeleeFx.hit_stop(clampf(r / 12.0, 0.0, 0.6))


func _self_damage_check(origin: Vector3) -> void:
	var sd := float(_cfg.get("self_damage", 0.0))
	if sd <= 0.0 or wielder == null:
		return
	# Firing a rocket at a wall two blocks away is your own problem.
	var hit := World.raycast(origin, View.plane_dir_to_world(aim), 2.2)
	if not bool(hit.get("hit", false)):
		return
	var ve := wielder as VoxelEntity
	if ve == null:
		return
	CbtDamage.apply(ve, CbtDamage.packet(
		float(_stack.stat("damage", 10.0)) * sd, Const.ELEM_FIRE, wielder,
		{"can_crit": false, "knockback": 4.0, "tag": "self_blast"}))


# ============================================================= shield / parry
## Call from the wielder's `modify_incoming_damage`. Returns the damage that
## should get through. A perfect parry inside `parry_window` returns 0 and
## staggers the attacker.
##
## Blocking only works against attacks arriving from the side you are facing —
## and, like everything else in this game, only against attacks that reached
## your depth layer at all.
func absorb(amount: float, element: String, source: Node) -> float:
	if state != State.BLOCKING or _stack == null or _stack.is_empty():
		return amount
	if source is Node3D and wielder != null:
		var d := View.to_plane((source as Node3D).global_position) - _origin()
		var ve := wielder as VoxelEntity
		if ve != null and absf(d.x) > 0.2 and signf(d.x) != signf(float(ve.facing)):
			return amount   # hit from behind: the shield is on the wrong side
	var ratio := float(_stack.stat("block_ratio", _cfg.get("block_ratio", 0.6)))
	if _block_time <= float(_cfg.get("parry_window", 0.2)):
		_do_parry(source, amount)
		return 0.0
	var blocked := amount * clampf(ratio, 0.0, 0.95)
	_block_energy += blocked * float(_cfg.get("block_drain", 0.3))
	if not _spend_energy(blocked * float(_cfg.get("block_drain", 0.3))):
		# Guard broken: the shield drops and the whole hit lands.
		state = State.IDLE
		Events.play_sound.emit(&"guard_break", _world_origin())
		CbtMeleeFx.hit_stop(0.7)
		return amount
	_drain_durability(1)
	Events.play_sound.emit(&"block_hit", _world_origin())
	CbtMeleeFx.impact(_world_origin() + View.plane_dir_to_world(Vector2(float(_facing()), 0.4)),
		0.6, Color(0.7, 0.85, 1.0), 0.14)
	Events.spawn_particles.emit(&"block_spark", _world_origin(), 6)
	return maxf(0.0, amount - blocked)


func _do_parry(source: Node, amount: float) -> void:
	parried.emit(source)
	Events.play_sound.emit(&"parry", _world_origin())
	CbtMeleeFx.ring(_world_origin() + Vector3(0, 0.8, 0), 1.8, Color(1.0, 0.95, 0.7), 0.26)
	CbtMeleeFx.hit_stop(0.9, 0.5)
	var sv := source as VoxelEntity
	if sv != null:
		var away := View.to_plane(sv.aabb_center()) - _origin()
		sv.knockback(View.plane_dir_to_world(Vector2(signf(away.x), 0.5).normalized()),
			float(_cfg.get("parry_stagger", 1.2)) * 8.0)
		CbtStatusHooks.apply(CbtStatusHooks.SHOCKED, sv, 1.2, 1, wielder)
		# Riposte: a parry throws the blow back.
		CbtDamage.apply(sv, CbtDamage.packet(amount * 0.6, Const.ELEM_PHYSICAL, wielder,
			{"can_crit": true, "crit_chance": 0.5, "knockback": 2.0, "tag": "riposte"}))


func _tick_block(delta: float) -> void:
	var drain := float(_cfg.get("block_drain", 0.0)) * 1.2 * delta
	if drain > 0.0 and not _spend_energy(drain):
		state = State.IDLE


# ==================================================================== specials
## Fire the weapon's `special` ability (the second mouse button on anything
## that is not a shield). Specials are rolled by [CbtWeaponGen] and stored in
## `ItemStack.data.special`.
func use_special() -> bool:
	if _stack == null or _stack.is_empty() or state != State.IDLE:
		return false
	var sp := StringName(_stack.stat("special", &""))
	if sp == &"":
		sp = special_from_tags(_stack)
	if sp == &"":
		return false
	var cost := float(_stack.stat("special_cost", 15.0))
	if not _spend_energy(cost):
		out_of_energy.emit(cost)
		return false
	var origin := _muzzle_world()
	var elem := String(_stack.stat("element", Const.ELEM_PHYSICAL))
	match sp:
		&"spin_slash":
			var hb := CbtHitbox.circle_box(_origin(), 3.4)
			hb.packet = _base_packet()
			hb.packet["amount"] = float(hb.packet.get("amount", 1.0)) * 1.4
			hb.packet["knockback"] = float(hb.packet.get("knockback", 0.0)) * 1.8
			hb.owner_node = wielder
			hb.hit.connect(_on_hitbox_hit)
			hb.resolve()
			CbtMeleeFx.ring(_world_origin() + Vector3(0, 0.9, 0), 3.4,
				CbtMeleeFx.element_color(elem), 0.3)
		&"dash_strike":
			var ve := wielder as VoxelEntity
			if ve != null:
				ve.velocity += View.plane_dir_to_world(aim * 16.0)
			var hb2 := CbtHitbox.capsule_box(_origin(), _origin() + aim * 4.0, 0.6)
			hb2.packet = _base_packet()
			hb2.packet["amount"] = float(hb2.packet.get("amount", 1.0)) * 1.25
			hb2.owner_node = wielder
			hb2.hit.connect(_on_hitbox_hit)
			hb2.resolve()
			CbtMeleeFx.slash(_origin(), aim, 4.0, 0.4, CbtMeleeFx.element_color(elem), 0.2)
		&"phase_pierce":
			# The signature perspective special: one shot, every layer.
			var p := CbtProjectile.spawn(&"phase_lance", origin, aim, wielder, {
				"damage": float(_stack.stat("damage", 10.0)) * 1.1,
				"weapon": _stack, "origin_layer": _layer(),
			})
			if p != null:
				CbtMeleeFx.beam(_origin(), _origin() + aim * 24.0, 0.22,
					Color(0.75, 0.5, 1.0), 0.22, NAN, float(Const.SLAB_BEHIND))
		&"depth_bomb":
			CbtProjectile.spawn(&"depth_charge", origin, _lob_dir(0.5), wielder, {
				"damage": float(_stack.stat("damage", 10.0)) * 1.6,
				"weapon": _stack, "origin_layer": _layer(),
			})
		&"volley":
			CbtProjectile.spawn_spread(
				StringName(_stack.stat("projectile", &"arrow")), origin, aim, 5, 30.0,
				wielder, _projectile_overrides(0.5))
		&"shockwave":
			var hb3 := CbtHitbox.cone_box(_origin(), aim, 7.0, 30.0)
			hb3.packet = _base_packet()
			hb3.packet["knockback"] = 14.0
			hb3.owner_node = wielder
			hb3.hit.connect(_on_hitbox_hit)
			hb3.resolve()
			CbtProjectile.spawn(&"sonic_wave", origin, aim, wielder,
				{"weapon": _stack, "origin_layer": _layer()})
		&"chain_bolt":
			CbtProjectile.spawn(&"lightning_arc", origin, aim, wielder,
				_projectile_overrides(0.0))
		&"nova":
			var p2 := _base_packet()
			p2["amount"] = float(p2.get("amount", 1.0)) * 1.8
			p2["knockback"] = 12.0
			CbtDamage.apply_radial(_world_origin() + Vector3(0, 0.9, 0), 5.0, p2, wielder)
			CbtMeleeFx.ring(_world_origin() + Vector3(0, 0.9, 0), 5.0,
				CbtMeleeFx.element_color(elem), 0.4)
		_:
			return false
	Events.play_sound.emit(&"special", _world_origin())
	_phase_len = 0.35
	_phase_t = 0.0
	state = State.RECOVERY
	return true


# ==================================================================== packets
## The damage packet this weapon would produce right now. Public so AI and
## tooltips can preview it.
func build_packet() -> Dictionary:
	return _base_packet()


func _base_packet() -> Dictionary:
	var p := CbtDamage.packet_from_weapon(_stack, wielder)
	p["amount"] = float(p.get("amount", 1.0)) * float(_cfg.get("damage_mult", 1.0))
	p["knockback"] = float(p.get("knockback", 4.0)) * float(_cfg.get("knockback_mult", 1.0))
	p["origin_layer"] = _layer()
	p["shake"] = float(_cfg.get("hitstop", 0.3)) * 0.4
	p["crit_chance"] = float(p.get("crit_chance", 0.05)) + float(_cfg.get("crit_bonus", 0.0))
	if _combo > 0 and int(_cfg.get("combo", 1)) > 1:
		# Later links of a combo hit harder; the finisher launches.
		var last := _combo == int(_cfg.get("combo", 1)) - 1
		p["amount"] = float(p["amount"]) * (1.0 + 0.16 * float(_combo))
		if last:
			p["knockback"] = float(p["knockback"]) * 2.0
	if _arch == DAGGER:
		p["backstab_mult"] = float(_cfg.get("backstab", 2.0))
	# Elemental weapons inflict their element's status unless told otherwise.
	var arr: Variant = p.get("status_on_hit", [])
	if arr is Array and (arr as Array).is_empty():
		p["status_on_hit"] = CbtStatusHooks.rolls_for_element(
			String(p.get("element", Const.ELEM_PHYSICAL)),
			float(_stack.stat("tier", 1)) if _stack != null else 1.0)
	return p


# ==================================================================== helpers
func _speed() -> float:
	var s := 1.0
	if _stack != null and not _stack.is_empty():
		s = float(_stack.stat("attack_speed", 1.0))
	if wielder != null and Status != null and Status.has_method(&"modifier"):
		var m := float(Status.modifier("attack_speed", wielder))
		if m > 0.0:
			s *= m
	return clampf(s, 0.15, 6.0)


func _facing() -> int:
	var ve := wielder as VoxelEntity
	return ve.facing if ve != null else 1


func _layer() -> int:
	if wielder == null:
		return View.layer
	return floori(View.depth_of(wielder.global_position))


func _origin() -> Vector2:
	if wielder == null:
		return Vector2.ZERO
	var ve := wielder as VoxelEntity
	var p := View.to_plane(wielder.global_position)
	if ve != null:
		p.y += ve.get_aabb_size().y * 0.6
	return p


func _world_origin() -> Vector3:
	if wielder == null:
		return Vector3.ZERO
	var ve := wielder as VoxelEntity
	return ve.aabb_center() if ve != null else wielder.global_position


func _muzzle_world() -> Vector3:
	var o := _origin() + aim * 0.7
	return View.to_world(o, View.depth_of(_world_origin()))


func _fx_depth() -> float:
	return View.depth_of(_world_origin())


func _swing_sound() -> StringName:
	match _arch:
		HAMMER: return &"swing_heavy"
		DAGGER, SHORTSWORD: return &"swing_light"
		BOW: return &"bow_release"
		GUN, SHOTGUN: return &"gunshot"
		ROCKET: return &"rocket_launch"
		FLAMETHROWER: return &"flame_loop"
		STAFF: return &"cast"
		BEAMDRILL: return &"drill_loop"
	return &"swing"


## Guarded energy spend. `PlayerActor.spend_energy` is the real one; the other
## names are accepted so a monster or an NPC can use the same driver.
func _spend_energy(amount: float) -> bool:
	if amount <= 0.0 or wielder == null:
		return true
	if wielder.has_method(&"spend_energy"):
		return bool(wielder.call(&"spend_energy", amount))
	if wielder.has_method(&"consume_energy"):
		return bool(wielder.call(&"consume_energy", amount))
	if wielder.has_method(&"use_energy"):
		return bool(wielder.call(&"use_energy", amount))
	var e: Variant = wielder.get(&"energy")
	if e != null and (e is float or e is int):
		if float(e) < amount:
			return false
		wielder.set(&"energy", float(e) - amount)
		Events.stat_changed.emit("energy", float(e) - amount,
			float(wielder.get(&"max_energy") if wielder.get(&"max_energy") != null else 100.0))
		return true
	return true


func _drain_durability(n: int) -> void:
	if n <= 0 or _stack == null or _stack.is_empty():
		return
	if _stack.durability() < 0:
		return
	if _stack.damage_durability(n):
		weapon_broke.emit(_stack)
		Events.toast("%s broke!" % _stack.display_name(), "warn")
		Events.play_sound.emit(&"item_break", _world_origin())
		cancel()
