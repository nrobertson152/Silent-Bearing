// Breaking in two. A ship that blows up or breaks her back is drawn twice
// from the same mesh, and each copy keeps its own half: cut.x is where she
// broke (model-space z, bow toward -Z), cut.y is +1 to keep the bow half, -1
// the stern half and 0 (the default) to keep everything. Both halves tear
// along the same ragged line, so the edges match.
instance uniform vec2 cut = vec2(0.0, 0.0);

float clip_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// How far (m) the tear wanders fore and aft of the cut at this point.
float clip_tear(vec3 p) {
	vec2 q = p.xy * 0.45;
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(clip_hash(i), clip_hash(i + vec2(1.0, 0.0)), f.x),
		mix(clip_hash(i + vec2(0.0, 1.0)), clip_hash(i + vec2(1.0, 1.0)), f.x), f.y);
	float spikes = clip_hash(floor(p.xy * 1.7) + 17.0);
	return (n - 0.5) * 5.0 + (spikes - 0.5) * 1.4;
}

// Throws away the half this copy doesn't keep. Returns how close (m) the
// fragment is to the torn edge, for scorching it.
float clip_ship(vec3 p) {
	if (cut.y == 0.0) {
		return 1e6;
	}
	float d = (p.z - cut.x + clip_tear(p)) * cut.y;
	if (d > 0.0) {
		discard;
	}
	return -d;
}
