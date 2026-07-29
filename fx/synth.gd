## Runtime DSP toolkit — every sample the game plays is built here.
##
## Planeshift ships with no binary audio assets, so `FxSoundBank`, `FxMusic` and
## `FxAmbience` all synthesise their material through these helpers and hand the
## result to `AudioStreamWAV`. The style is deliberately old-school: oscillators,
## envelopes, one-pole and biquad filters, and a couple of cheap feedback
## effects. Everything is a `static func` over `PackedFloat32Array` buffers of
## normalised samples in -1..1.
##
## Packed arrays are passed by reference in Godot 4, so the processing helpers
## work in place — but they *also* return the buffer, so the idiomatic call is
## `buf = FxSynth.lowpass1(buf, 800.0)` and the code is correct either way.
class_name FxSynth
extends RefCounted

## Sample rate for one-shot effects. 22 kHz is plenty for percussive noise and
## halves both the build cost and the resident memory of the bank.
const SR := 22050
## Sample rate for long musical / ambient loops, where bandwidth matters less
## than the cost of generating a hundred thousand samples in GDScript.
const SR_LOOP := 16000

const TWO_PI := TAU

enum Wave {
	SINE,
	SAW,
	SQUARE,
	TRIANGLE,
	NOISE,
	PINK,
}

enum Filter {
	LOWPASS,
	HIGHPASS,
	BANDPASS,
	NOTCH,
	PEAK,
}


# =============================================================== construction
## An all-zero buffer `dur` seconds long.
static func buffer(dur: float, sr: int = SR) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(1, int(dur * float(sr))))
	return out


## Sample count for a duration.
static func samples(dur: float, sr: int = SR) -> int:
	return maxi(1, int(dur * float(sr)))


## Deterministic RNG for a (sound id, take) pair. The same id always yields the
## same family of takes, so a sound has recognisable identity while still never
## repeating exactly twice in a row.
static func seeded(id: StringName, take: int = 0) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (hash(String(id)) * 2654435761) ^ (take * 40503 + 0x9E3779B9)
	return rng


## Multiplicative jitter around `base`; `amount` is a fraction (0.05 = +/-5%).
static func vary(rng: RandomNumberGenerator, base: float, amount: float) -> float:
	if rng == null or amount <= 0.0:
		return base
	return base * (1.0 + rng.randf_range(-amount, amount))


## MIDI note number to frequency (A4 = 69 = 440 Hz).
static func note_hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


# ================================================================ oscillators
## One oscillator voice. `f1 < 0` means "no sweep". Sweeps are exponential by
## default, which is what makes a pitch drop sound musical rather than linear.
static func osc(wave: int, dur: float, f0: float, f1: float = -1.0,
		amp: float = 1.0, sr: int = SR, rng: RandomNumberGenerator = null,
		duty: float = 0.5, expo: bool = true) -> PackedFloat32Array:
	var n := samples(dur, sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var f_end := f0 if f1 < 0.0 else f1
	var sweeping := absf(f_end - f0) > 0.01
	var inv := 1.0 / float(maxi(1, n - 1))
	var isr := 1.0 / float(sr)
	var phase := 0.0
	# Pink-noise state (Paul Kellett's economy filter).
	var p0 := 0.0
	var p1 := 0.0
	var p2 := 0.0
	var ratio := (f_end / f0) if (f0 > 0.001 and f_end > 0.001) else 1.0
	for i in n:
		var t := float(i) * inv
		var f := f0
		if sweeping:
			f = f0 * pow(ratio, t) if (expo and f0 > 0.001 and f_end > 0.001) else lerpf(f0, f_end, t)
		phase += f * isr
		if phase >= 1.0:
			phase -= floorf(phase)
		var s := 0.0
		match wave:
			Wave.SINE:
				s = sin(phase * TWO_PI)
			Wave.SAW:
				s = phase * 2.0 - 1.0
			Wave.SQUARE:
				s = 1.0 if phase < duty else -1.0
			Wave.TRIANGLE:
				s = (phase * 4.0 - 1.0) if phase < 0.5 else (3.0 - phase * 4.0)
			Wave.NOISE:
				s = rng.randf_range(-1.0, 1.0) if rng != null else randf_range(-1.0, 1.0)
			Wave.PINK:
				var w := rng.randf_range(-1.0, 1.0) if rng != null else randf_range(-1.0, 1.0)
				p0 = 0.99765 * p0 + w * 0.0990460
				p1 = 0.96300 * p1 + w * 0.2965164
				p2 = 0.57000 * p2 + w * 1.0526913
				s = clampf((p0 + p1 + p2 + w * 0.1848) * 0.35, -1.0, 1.0)
		out[i] = s * amp
	return out


## White noise, the workhorse of every impact in the bank.
static func noise(dur: float, amp: float = 1.0, rng: RandomNumberGenerator = null,
		sr: int = SR) -> PackedFloat32Array:
	return osc(Wave.NOISE, dur, 1.0, -1.0, amp, sr, rng)


## Two-operator FM. Cheap bells, metal and laser tones come from here.
static func fm(dur: float, carrier: float, ratio: float, index: float,
		index_end: float = 0.0, amp: float = 1.0, sr: int = SR,
		carrier_end: float = -1.0) -> PackedFloat32Array:
	var n := samples(dur, sr)
	var out := PackedFloat32Array()
	out.resize(n)
	var isr := 1.0 / float(sr)
	var inv := 1.0 / float(maxi(1, n - 1))
	var cf_end := carrier if carrier_end < 0.0 else carrier_end
	var cphase := 0.0
	var mphase := 0.0
	for i in n:
		var t := float(i) * inv
		var cf := lerpf(carrier, cf_end, t)
		var idx := lerpf(index, index_end, t)
		mphase += cf * ratio * isr
		var m := sin(mphase * TWO_PI) * idx
		cphase += cf * isr
		out[i] = sin((cphase + m) * TWO_PI) * amp
	return out


## A plucked/struck resonant body: noise fed through a very narrow bandpass.
## `decay` is the -60 dB time in seconds.
static func resonator(dur: float, freq: float, decay: float, amp: float = 1.0,
		rng: RandomNumberGenerator = null, sr: int = SR) -> PackedFloat32Array:
	var b := noise(minf(dur, 0.006), 1.0, rng, sr)
	b.resize(samples(dur, sr))
	b = biquad(b, Filter.BANDPASS, freq, 28.0, sr)
	b = decay_env(b, decay, sr)
	return gain(normalize(b, 1.0), amp)


# ================================================================== envelopes
## Classic ADSR. `s` is the sustain level 0..1; the sustain segment fills
## whatever is left between decay and release.
static func adsr(buf: PackedFloat32Array, a: float, d: float, s: float,
		r: float, sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	var na := maxi(1, int(a * float(sr)))
	var nd := maxi(1, int(d * float(sr)))
	var nr := maxi(1, int(r * float(sr)))
	var rel_start := maxi(na + nd, n - nr)
	for i in n:
		var e := 0.0
		if i < na:
			e = float(i) / float(na)
		elif i < na + nd:
			e = lerpf(1.0, s, float(i - na) / float(nd))
		elif i < rel_start:
			e = s
		else:
			e = s * (1.0 - float(i - rel_start) / float(maxi(1, n - rel_start)))
		buf[i] = buf[i] * e
	return buf


## Percussive envelope: near-instant attack, `curve`-shaped fall to silence.
static func perc(buf: PackedFloat32Array, attack: float = 0.002,
		curve: float = 3.0, sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	var na := maxi(1, int(attack * float(sr)))
	var inv := 1.0 / float(maxi(1, n - na))
	for i in n:
		var e := 0.0
		if i < na:
			e = float(i) / float(na)
		else:
			e = pow(1.0 - float(i - na) * inv, curve)
		buf[i] = buf[i] * e
	return buf


## Exponential decay to -60 dB after `decay` seconds (rings past the buffer end
## are simply truncated).
static func decay_env(buf: PackedFloat32Array, decay: float,
		sr: int = SR) -> PackedFloat32Array:
	var k := -6.907755 / maxf(0.001, decay * float(sr))
	for i in buf.size():
		buf[i] = buf[i] * exp(k * float(i))
	return buf


## Piecewise-linear envelope from `[[t0, v0], [t1, v1], ...]` with `t` in 0..1.
static func env_shape(buf: PackedFloat32Array, points: Array) -> PackedFloat32Array:
	if points.size() < 2:
		return buf
	var n := buf.size()
	var inv := 1.0 / float(maxi(1, n - 1))
	var seg := 0
	for i in n:
		var t := float(i) * inv
		while seg < points.size() - 2 and t > float(points[seg + 1][0]):
			seg += 1
		var t0: float = points[seg][0]
		var t1: float = points[seg + 1][0]
		var v0: float = points[seg][1]
		var v1: float = points[seg + 1][1]
		var u := 0.0 if t1 <= t0 else clampf((t - t0) / (t1 - t0), 0.0, 1.0)
		buf[i] = buf[i] * lerpf(v0, v1, u)
	return buf


## Linear fade in / fade out, mostly used to keep loops click-free.
static func fade(buf: PackedFloat32Array, fade_in: float, fade_out: float,
		sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	var ni := mini(n, maxi(1, int(fade_in * float(sr))))
	var no := mini(n, maxi(1, int(fade_out * float(sr))))
	if fade_in > 0.0:
		for i in ni:
			buf[i] = buf[i] * (float(i) / float(ni))
	if fade_out > 0.0:
		for i in no:
			buf[n - 1 - i] = buf[n - 1 - i] * (float(i) / float(no))
	return buf


## Amplitude tremolo; `rate_end < 0` keeps a constant rate.
static func tremolo(buf: PackedFloat32Array, rate: float, depth: float,
		sr: int = SR, rate_end: float = -1.0) -> PackedFloat32Array:
	var n := buf.size()
	var inv := 1.0 / float(maxi(1, n - 1))
	var isr := 1.0 / float(sr)
	var r_end := rate if rate_end < 0.0 else rate_end
	var phase := 0.0
	for i in n:
		var t := float(i) * inv
		phase += lerpf(rate, r_end, t) * isr
		var lfo := 1.0 - depth * (0.5 - 0.5 * cos(phase * TWO_PI))
		buf[i] = buf[i] * lfo
	return buf


# ==================================================================== filters
## One-pole low-pass. Gentle, cheap, and exactly right for "far away" and "under
## a metre of dirt".
static func lowpass1(buf: PackedFloat32Array, cutoff: float,
		sr: int = SR) -> PackedFloat32Array:
	var x := exp(-TWO_PI * clampf(cutoff, 5.0, float(sr) * 0.49) / float(sr))
	var a := 1.0 - x
	var y := 0.0
	for i in buf.size():
		y = y * x + buf[i] * a
		buf[i] = y
	return buf


## One-pole high-pass (DC blocker when the cutoff is tiny).
static func highpass1(buf: PackedFloat32Array, cutoff: float,
		sr: int = SR) -> PackedFloat32Array:
	var x := exp(-TWO_PI * clampf(cutoff, 5.0, float(sr) * 0.49) / float(sr))
	var y := 0.0
	var prev := 0.0
	for i in buf.size():
		var v := buf[i]
		y = x * (y + v - prev)
		prev = v
		buf[i] = y
	return buf


## RBJ biquad, direct form 1. `q` above ~10 rings audibly, which is how the
## metal and glass sounds get their pitch.
static func biquad(buf: PackedFloat32Array, type: int, freq: float, q: float,
		sr: int = SR, gain_db: float = 0.0) -> PackedFloat32Array:
	var c := _biquad_coeffs(type, freq, q, sr, gain_db)
	return _run_biquad(buf, c)


## Biquad whose cutoff glides from `f0` to `f1`; coefficients are refreshed
## every 32 samples, which is inaudible and ~30x cheaper than per-sample.
static func filter_sweep(buf: PackedFloat32Array, type: int, f0: float,
		f1: float, q: float, sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	if n == 0:
		return buf
	const BLOCK := 32
	var inv := 1.0 / float(maxi(1, n - 1))
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var c := _biquad_coeffs(type, f0, q, sr, 0.0)
	var i := 0
	while i < n:
		var t := float(i) * inv
		var f: float = f0 * pow(maxf(0.001, f1 / maxf(0.001, f0)), t)
		c = _biquad_coeffs(type, f, q, sr, 0.0)
		var stop := mini(n, i + BLOCK)
		while i < stop:
			var x0 := buf[i]
			var y0: float = c[0] * x0 + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
			x2 = x1
			x1 = x0
			y2 = y1
			y1 = y0
			buf[i] = y0
			i += 1
	return buf


static func _run_biquad(buf: PackedFloat32Array, c: PackedFloat32Array) -> PackedFloat32Array:
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in buf.size():
		var x0 := buf[i]
		var y0: float = c[0] * x0 + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0
		buf[i] = y0
	return buf


static func _biquad_coeffs(type: int, freq: float, q: float, sr: int,
		gain_db: float) -> PackedFloat32Array:
	var w0 := TWO_PI * clampf(freq, 10.0, float(sr) * 0.45) / float(sr)
	var cw := cos(w0)
	var sw := sin(w0)
	var qq := maxf(0.05, q)
	var alpha := sw / (2.0 * qq)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cw
	var a2 := 1.0 - alpha
	match type:
		Filter.LOWPASS:
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = b0
		Filter.HIGHPASS:
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = b0
		Filter.BANDPASS:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
		Filter.NOTCH:
			b0 = 1.0
			b1 = -2.0 * cw
			b2 = 1.0
		Filter.PEAK:
			var amp := pow(10.0, gain_db / 40.0)
			b0 = 1.0 + alpha * amp
			b1 = -2.0 * cw
			b2 = 1.0 - alpha * amp
			a0 = 1.0 + alpha / amp
			a2 = 1.0 - alpha / amp
	var out := PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0])
	return out


# ==================================================================== effects
## Quantise amplitude and sample rate — instant "alien machinery".
static func bitcrush(buf: PackedFloat32Array, bits: float = 6.0,
		downsample: int = 1) -> PackedFloat32Array:
	var levels := pow(2.0, clampf(bits, 1.0, 16.0)) * 0.5
	var held := 0.0
	var step := maxi(1, downsample)
	for i in buf.size():
		if i % step == 0:
			held = roundf(buf[i] * levels) / levels
		buf[i] = held
	return buf


## Multiply by a sine — inharmonic sidebands, the sound of "not from here".
static func ring_mod(buf: PackedFloat32Array, freq: float, depth: float = 1.0,
		sr: int = SR) -> PackedFloat32Array:
	var isr := 1.0 / float(sr)
	var phase := 0.0
	for i in buf.size():
		phase += freq * isr
		var m := lerpf(1.0, sin(phase * TWO_PI), clampf(depth, 0.0, 1.0))
		buf[i] = buf[i] * m
	return buf


## Soft saturation. `drive` of 1 is transparent, 8 is aggressive.
static func distort(buf: PackedFloat32Array, drive: float = 3.0) -> PackedFloat32Array:
	var d := maxf(0.01, drive)
	var norm := 1.0 / atan(d)
	for i in buf.size():
		buf[i] = atan(buf[i] * d) * norm
	return buf


## Hard-knee clip, used after summing several loud layers.
static func soft_clip(buf: PackedFloat32Array) -> PackedFloat32Array:
	for i in buf.size():
		var v := buf[i]
		buf[i] = clampf(v - (v * v * v) / 3.0, -1.0, 1.0) if absf(v) < 1.5 else signf(v)
	return buf


## Single feedback delay line. Add `pad()` first if you want the tail to fit.
static func delay(buf: PackedFloat32Array, time: float, feedback: float = 0.35,
		mix: float = 0.4, sr: int = SR) -> PackedFloat32Array:
	var d := maxi(1, int(time * float(sr)))
	var n := buf.size()
	if d >= n:
		return buf
	var fb := clampf(feedback, 0.0, 0.92)
	for i in range(d, n):
		buf[i] = buf[i] + buf[i - d] * fb * mix
	return buf


## Compact Schroeder reverb: four feedback combs into two allpasses. Not a
## convolution — it costs six multiply-adds per sample and sounds like a room.
static func reverb(buf: PackedFloat32Array, size: float = 0.5,
		damping: float = 0.4, wet: float = 0.3, sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	if n < 64:
		return buf
	var scale := lerpf(0.5, 1.6, clampf(size, 0.0, 1.0))
	var comb_ms := [29.7, 37.1, 41.1, 43.7]
	var out := PackedFloat32Array()
	out.resize(n)
	var damp := clampf(damping, 0.0, 0.95)
	for c in 4:
		var d := maxi(8, int(float(comb_ms[c]) * 0.001 * scale * float(sr)))
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var lp := 0.0
		var fb := clampf(0.84 - float(c) * 0.02, 0.0, 0.93)
		for i in n:
			var y := line[idx]
			out[i] = out[i] + y * 0.25
			lp = lerpf(y, lp, damp)
			line[idx] = buf[i] + lp * fb
			idx += 1
			if idx >= d:
				idx = 0
	for ap_ms in [5.0, 1.7]:
		var d := maxi(4, int(float(ap_ms) * 0.001 * scale * float(sr)))
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		for i in n:
			var y := line[idx]
			var v := out[i] + y * -0.55
			line[idx] = v
			out[i] = y + v * 0.55
			idx += 1
			if idx >= d:
				idx = 0
	var w := clampf(wet, 0.0, 1.0)
	for i in n:
		buf[i] = buf[i] * (1.0 - w * 0.35) + out[i] * w
	return buf


# ================================================================== buffer ops
## Mix `src` into `dst` at `at` seconds. `dst` is not resized — anything past
## the end is discarded, which is usually what you want.
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array,
		gain_mul: float = 1.0, at: float = 0.0, sr: int = SR) -> PackedFloat32Array:
	var off := maxi(0, int(at * float(sr)))
	var n := mini(src.size(), dst.size() - off)
	for i in n:
		dst[off + i] = dst[off + i] + src[i] * gain_mul
	return dst


static func gain(buf: PackedFloat32Array, g: float) -> PackedFloat32Array:
	for i in buf.size():
		buf[i] = buf[i] * g
	return buf


## Scale so the loudest sample sits at `peak`. Silent buffers are left alone.
static func normalize(buf: PackedFloat32Array, peak: float = 0.9) -> PackedFloat32Array:
	var m := 0.0
	for i in buf.size():
		m = maxf(m, absf(buf[i]))
	if m < 0.00001:
		return buf
	return gain(buf, peak / m)


## Extend with silence so a reverb or delay tail has room to ring out.
static func pad(buf: PackedFloat32Array, extra: float,
		sr: int = SR) -> PackedFloat32Array:
	buf.resize(buf.size() + maxi(0, int(extra * float(sr))))
	return buf


static func reverse(buf: PackedFloat32Array) -> PackedFloat32Array:
	var n := buf.size()
	for i in n / 2:
		var t := buf[i]
		buf[i] = buf[n - 1 - i]
		buf[n - 1 - i] = t
	return buf


## Linear-interpolating resample. `ratio > 1` makes it shorter and higher.
static func resample(buf: PackedFloat32Array, ratio: float) -> PackedFloat32Array:
	var r := maxf(0.05, ratio)
	var n := buf.size()
	var m := maxi(1, int(float(n) / r))
	var out := PackedFloat32Array()
	out.resize(m)
	for i in m:
		var x := float(i) * r
		var i0 := int(x)
		var i1 := mini(n - 1, i0 + 1)
		if i0 >= n:
			break
		out[i] = lerpf(buf[i0], buf[i1], x - float(i0))
	return out


## Turn a buffer into a seamless loop by folding its tail back over its head.
## The result is `xfade` seconds shorter than the input.
static func seamless(buf: PackedFloat32Array, xfade: float = 0.4,
		sr: int = SR) -> PackedFloat32Array:
	var n := buf.size()
	var x := clampi(int(xfade * float(sr)), 1, n / 3)
	var m := n - x
	var out := PackedFloat32Array()
	out.resize(m)
	for i in m:
		out[i] = buf[i]
	for i in x:
		var u := float(i) / float(x)
		out[i] = buf[i] * u + buf[m + i] * (1.0 - u)
	return out


## Split a mono buffer into a stereo pair using a Haas delay plus a mild
## tone difference. Cheap, wide, and mono-safe enough for background beds.
static func stereo_pair(mono: PackedFloat32Array, width: float = 1.0,
		sr: int = SR) -> Array:
	var n := mono.size()
	var l := PackedFloat32Array()
	var r := PackedFloat32Array()
	l.resize(n)
	r.resize(n)
	var d := maxi(1, int(0.011 * width * float(sr)))
	for i in n:
		var v := mono[i]
		var e := mono[(i + n - d) % n]
		l[i] = v * 0.82 + e * 0.28 * width
		r[i] = v * 0.82 - e * 0.28 * width
	return [l, r]


# ================================================================== packaging
## 16-bit little-endian PCM. Two samples are packed per int32 so the conversion
## costs one GDScript iteration per *pair* instead of per sample.
static func to_pcm16(buf: PackedFloat32Array) -> PackedByteArray:
	var n := buf.size()
	var pairs := (n + 1) >> 1
	var ints := PackedInt32Array()
	ints.resize(pairs)
	for i in pairs:
		var j := i << 1
		var a := int(clampf(buf[j], -1.0, 1.0) * 32767.0)
		var b := 0
		if j + 1 < n:
			b = int(clampf(buf[j + 1], -1.0, 1.0) * 32767.0)
		var v := (a & 0xFFFF) | ((b & 0xFFFF) << 16)
		if v >= 0x80000000:
			v -= 0x100000000
		ints[i] = v
	var bytes := ints.to_byte_array()
	if bytes.size() > n * 2:
		bytes.resize(n * 2)
	return bytes


## Mono stream. Pass `loop = true` for beds and music phrases.
static func to_wav(buf: PackedFloat32Array, sr: int = SR,
		loop: bool = false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = false
	w.data = to_pcm16(buf)
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w


## Interleaved stereo stream from a left/right pair.
static func to_wav_stereo(l: PackedFloat32Array, r: PackedFloat32Array,
		sr: int = SR, loop: bool = false) -> AudioStreamWAV:
	var frames := mini(l.size(), r.size())
	var inter := PackedFloat32Array()
	inter.resize(frames * 2)
	for i in frames:
		inter[i * 2] = l[i]
		inter[i * 2 + 1] = r[i]
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = sr
	w.stereo = true
	w.data = to_pcm16(inter)
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = frames
	return w
