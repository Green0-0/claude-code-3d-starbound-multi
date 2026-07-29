## Deterministic hashing helpers shared by every structure generator.
##
## Structure placement must be a pure function of (world seed, coarse cell
## coordinate) because `StructPlacer.populate()` can be called for chunks in any
## order, and a structure larger than one chunk is rebuilt independently by every
## chunk it touches. Nothing here ever touches global RNG state.
class_name StructRng
extends RefCounted

## splitmix64 constants, written as signed 64-bit because GDScript ints are i64.
const M1 := -49064778989728563      ## 0xff51afd7ed558ccd
const M2 := -4265267296055464877    ## 0xc4ceb9fe1a85ec53
const GOLDEN := -7046029254386353131 ## 0x9e3779b97f4a7c15


## Logical (zero-filling) shift right. GDScript's `>>` is *arithmetic* on ints,
## which would drag the sign bit through splitmix's xor-shifts and leave bit 63
## permanently clear — halving the output range. Everything here shifts through
## this instead.
static func lsr(x: int, n: int) -> int:
	if n <= 0:
		return x
	if n >= 63:
		return (x >> 63) & 1
	return (x >> n) & ((1 << (64 - n)) - 1)


## Avalanche a single 64-bit value.
static func mix(x: int) -> int:
	x ^= lsr(x, 33)
	x *= M1
	x ^= lsr(x, 29)
	x *= M2
	x ^= lsr(x, 32)
	return x


## Fold an arbitrary number of ints into one hash. Order matters.
static func hash_ints(values: Array) -> int:
	var h := GOLDEN
	for v: int in values:
		h = mix(h ^ (v * -1640531527))
	return h


static func hash2(a: int, b: int) -> int:
	return mix(mix(a * -1640531527) ^ (b * 1099511628211))


static func hash3(a: int, b: int, c: int) -> int:
	return mix(hash2(a, b) ^ (c * -3750763034362895579))


static func hash4(a: int, b: int, c: int, d: int) -> int:
	return mix(hash3(a, b, c) ^ (d * 1099511628211))


## 0..1 float derived from a hash. Takes the low 53 bits — splitmix avalanches
## them fully, and they carry no sign so the result is genuinely uniform.
static func to_unit(h: int) -> float:
	return float(h & 0x1FFFFFFFFFFFFF) / 9007199254740992.0


## Integer in [lo, hi] inclusive derived from a hash.
static func to_range(h: int, lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(absi(h) % (hi - lo + 1))


## A seeded RandomNumberGenerator. Two calls with the same inputs always give
## the same stream, so generators may consume it freely.
static func rng(a: int, b: int = 0, c: int = 0, d: int = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash4(a, b, c, d)
	return r


## Pick an entry from `weighted` = [[value, weight], ...] using `h`.
static func weighted_pick(h: int, weighted: Array) -> Variant:
	var total := 0.0
	for e: Array in weighted:
		total += maxf(0.0, float(e[1]))
	if total <= 0.0:
		return null
	var roll := to_unit(h) * total
	for e: Array in weighted:
		roll -= maxf(0.0, float(e[1]))
		if roll <= 0.0:
			return e[0]
	return weighted[weighted.size() - 1][0]


## Shuffle a copy of `arr` deterministically.
static func shuffled(arr: Array, r: RandomNumberGenerator) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = out[i]
		out[i] = out[j]
		out[j] = t
	return out
