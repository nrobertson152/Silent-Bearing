extends RefCounted
## Graphics settings: which renderer is running, the quality preset, and the
## lighting, shadow and anti-aliasing setup that goes with them.
##
## The game runs on Forward+ (Vulkan or Direct3D 12). On GPUs without Vulkan,
## Godot falls back to the Compatibility renderer (OpenGL 3) by itself; every
## effect here checks advanced() and degrades gracefully there. F9 cycles the
## preset in game, and `-- --gfx low|medium|high` overrides it for one run.

const SETTINGS := "user://settings.cfg"
const NAMES := ["Low", "Medium", "High"]

static var quality := 2
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		quality = clampi(int(cf.get_value("graphics", "quality", 2)), 0, 2)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--gfx")
	if i >= 0 and args.size() > i + 1:
		for q in NAMES.size():
			if NAMES[q].to_lower() == String(args[i + 1]).to_lower():
				quality = q


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("graphics", "quality", quality)
	cf.save(SETTINGS)


static func cycle() -> String:
	quality = (quality + 1) % NAMES.size()
	save_settings()
	return NAMES[quality]


## "forward_plus", "mobile", "gl_compatibility" (or "dummy" when headless).
static func method() -> String:
	return RenderingServer.get_current_rendering_method()


## True where screen-space effects exist (Forward+ and Mobile).
static func advanced() -> bool:
	return method() in ["forward_plus", "mobile"]


static func forward_plus() -> bool:
	return method() == "forward_plus"


## Anti-aliasing and debanding for the main window.
static func apply_viewport(vp: Viewport) -> void:
	vp.use_debanding = true
	match quality:
		0:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		1:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


## Tone mapping, fog, ambient occlusion, reflections, haze and bloom for the
## outside world. `p` is the time-of-day palette from WorldView.
static func setup_env(env: Environment, p: Dictionary, night: bool) -> void:
	var adv := advanced()
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if adv else Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.tonemap_exposure = float(p.get("exposure", 1.0))
	# Distance haze that takes on the colour of the sky behind it.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = p["hor"]
	env.fog_density = p["fog"]
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.55 if adv else 0.0
	env.fog_sun_scatter = 0.25 if not night else 0.0
	env.fog_height = 40.0
	env.fog_height_density = p["fog"] * 4.0
	# Screen-space ambient occlusion grounds the superstructure, guns and deck fittings.
	env.ssao_enabled = adv and quality >= 1
	env.ssao_radius = 2.5
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.1
	env.ssil_enabled = adv and quality >= 2
	env.ssil_radius = 6.0
	env.ssil_intensity = 0.6
	# Ships, smoke and fire reflected in the water.
	env.ssr_enabled = adv and quality >= 1
	env.ssr_max_steps = 64 if quality >= 2 else 32
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 2.0
	# Glow lets fire, flashes, tracers and the sun bloom.
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04 if not night else 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Low volumetric haze so flashes, fires and searchlights light up the air.
	env.volumetric_fog_enabled = forward_plus() and quality >= 2
	env.volumetric_fog_density = 0.0004 if not night else 0.0009
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_gi_inject = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05 if not night else 0.85


## Soft sun shadows with enough reach for a ship's length.
static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [350.0, 600.0, 900.0][quality]
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.16
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = quality >= 2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.light_angular_distance = 0.5 if advanced() and quality >= 2 else 0.0


## The inside of the boat: lamps, ambient occlusion and a little bloom.
static func setup_interior_env(env: Environment) -> void:
	var adv := advanced()
	env.ssao_enabled = adv and quality >= 1
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssil_enabled = adv and quality >= 2
	env.ssil_radius = 1.5
	env.ssil_intensity = 0.8
