extends Control

const SAVE_PATH := "user://godforge_save.cfg"
const UPGRADE_NAMES := ["FORGE HAMMER", "SOUL ENGINE", "RUNE OF RUIN", "GODSLAYER EDGE"]
const UPGRADE_DESC := ["More power per strike", "Earn energy while idle", "Increase all production", "Deal more damage to bosses"]
const UPGRADE_BASE_COST := [25.0, 80.0, 180.0, 320.0]
const BOSS_NAMES := ["THE HOLLOW TITAN", "THE ASHEN WYRM", "THE VEIL QUEEN", "THE IRON SAINT"]
const UPGRADE_GLYPHS := ["⚒", "◉", "ᚱ", "✦"]

var rng := RandomNumberGenerator.new()
var stars: Array[Vector3] = []
var pulse := 0.0
var hit_flash := 0.0
var core_recoil := 0.0
var critical_flash := 0.0
var boss_transition_flash := 0.0
var boss_hit_flash := 0.0
var boss_shake := 0.0
var combat_popups: Array[Dictionary] = []
var upgrade_feedback_time := [0.0, 0.0, 0.0, 0.0]
var ember_particles: Array[Vector4] = []
var energy := 0.0
var click_power := 1.0
var idle_rate := 0.0
var multiplier := 1.0
var boss_damage := 1.0
var boss_stage := 1
var boss_hp := 500.0
var boss_max_hp := 500.0
var upgrade_levels := [0, 0, 0, 0]
var playing := false
var ad_boost_time := 0.0
var idle_clock := 0.0
var autosave_clock := 0.0
var ui_labels: Dictionary = {}
var boss_bar: ProgressBar
var core_button: Button
var boost_button: Button

func _ready() -> void:
	rng.randomize()
	for i in range(100):
		stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))
	_load_game()
	set_process(true)
	_show_splash()
	await get_tree().create_timer(2.4).timeout
	if is_inside_tree() and not playing:
		_show_title()

func _process(delta: float) -> void:
	pulse += delta
	hit_flash = maxf(0.0, hit_flash - delta * 2.8)
	core_recoil = move_toward(core_recoil, 0.0, delta * 4.5)
	critical_flash = maxf(0.0, critical_flash - delta * 2.2)
	boss_transition_flash = maxf(0.0, boss_transition_flash - delta * 1.35)
	boss_hit_flash = maxf(0.0, boss_hit_flash - delta * 3.2)
	boss_shake = move_toward(boss_shake, 0.0, delta * 4.8)
	if boss_bar != null and is_instance_valid(boss_bar):
		boss_bar.modulate = Color(1.0, 1.0 + boss_hit_flash * 0.24, 1.0 + boss_hit_flash * 0.10, 1.0)
	for popup_index in range(combat_popups.size() - 1, -1, -1):
		var popup: Dictionary = combat_popups[popup_index]
		popup["life"] = float(popup["life"]) - delta
		var popup_position: Vector2 = popup["position"]
		popup["position"] = popup_position + Vector2(0.0, -42.0 * delta)
		combat_popups[popup_index] = popup
		if float(popup["life"]) <= 0.0:
			combat_popups.remove_at(popup_index)
	for i in range(ember_particles.size() - 1, -1, -1):
		var ember := ember_particles[i]
		ember.x += ember.z * delta
		ember.y += ember.w * delta
		ember.z *= 0.985
		ember.w -= 22.0 * delta
		ember_particles[i] = ember
		if ember.y < -10.0 or ember.w < -140.0:
			ember_particles.remove_at(i)
	if playing and rng.randf() < delta * 12.0:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(80.0, 140.0)
		var ember_center := Vector2(640.0, 345.0)
		var point := ember_center + Vector2(cos(angle), sin(angle)) * radius
		ember_particles.append(Vector4(point.x, point.y, rng.randf_range(-22.0, 22.0), rng.randf_range(-45.0, -12.0)))
	idle_clock += delta
	autosave_clock += delta
	if idle_clock >= 1.0:
		idle_clock = 0.0
		if playing and idle_rate > 0.0:
			energy += idle_rate * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)
			_refresh_ui()
	for i in range(4):
		if upgrade_feedback_time[i] > 0.0:
			upgrade_feedback_time[i] = maxf(0.0, upgrade_feedback_time[i] - delta)
			if upgrade_feedback_time[i] <= 0.0 and playing:
				_refresh_ui()
	if ad_boost_time > 0.0:
		ad_boost_time = maxf(0.0, ad_boost_time - delta)
		if boost_button != null and is_instance_valid(boost_button):
			boost_button.text = "AD BONUS x2  %02d s" % int(ceil(ad_boost_time)) if ad_boost_time > 0.0 else "REWARDED AD x2  (DEMO)"
	if autosave_clock >= 15.0:
		autosave_clock = 0.0
		_save_game()
	queue_redraw()

func _draw() -> void:
	var size := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07060c"))
	for y in range(0, int(size.y), 3):
		var t := float(y) / maxf(size.y, 1.0)
		draw_rect(Rect2(0, y, size.x, 3), Color(0.15, 0.045, 0.065, 0.018 + t * 0.025))
	_draw_sanctum_architecture(size)
	# Distant ruined cathedral ribs and stained-glass glow.
	for side in [-1.0, 1.0]:
		var x: float = size.x * (0.5 + float(side) * 0.31)
		draw_line(Vector2(x, 0), Vector2(x + side * 58.0, size.y * 0.34), Color(0.35, 0.15, 0.17, 0.18), 3.0, true)
		draw_line(Vector2(x + side * 58.0, size.y * 0.34), Vector2(x + side * 90.0, size.y * 0.78), Color(0.55, 0.22, 0.16, 0.12), 2.0, true)
		draw_arc(Vector2(x, size.y * 0.34), 95.0, PI if side < 0.0 else 0.0, TAU if side < 0.0 else PI, 48, Color(0.55, 0.24, 0.19, 0.13), 2.0, true)
	for i in range(100):
		var star := stars[i]
		var p := Vector2(star.x * size.x, star.y * size.y)
		var twinkle := 0.18 + 0.34 * absf(sin(pulse * star.z + star.x * 20.0))
		draw_circle(p, 0.6 + star.z * 1.1, Color(1.0, 0.64, 0.34, twinkle))
	var center := Vector2(size.x * 0.5, size.y * 0.48 + core_recoil * 9.0)
	var core_size := 1.0 + 0.035 * sin(pulse * 2.2) + hit_flash * 0.12
	# Wide atmospheric bloom.
	for i in range(12, 0, -1):
		var radius := (52.0 + i * 11.0) * core_size
		draw_circle(center, radius, Color(0.9, 0.19 + hit_flash * 0.4, 0.055, 0.012 + float(12 - i) * 0.0025))
	# Broken outer rune circles.
	draw_arc(center, 155.0 * core_size, pulse * 0.08, pulse * 0.08 + TAU * 0.72, 120, Color(0.55, 0.24, 0.2, 0.26), 2.0, true)
	draw_arc(center, 139.0 * core_size, -pulse * 0.12, -pulse * 0.12 + TAU * 0.58, 120, Color(0.96, 0.57, 0.25, 0.44), 1.4, true)
	draw_arc(center, 112.0 * core_size, pulse * 0.2, pulse * 0.2 + TAU * 0.82, 120, Color(0.75, 0.31, 0.2, 0.55), 2.0, true)
	for i in range(16):
		var a := TAU * float(i) / 16.0 + pulse * 0.12
		var inner := center + Vector2(cos(a), sin(a)) * 119.0
		var outer := center + Vector2(cos(a), sin(a)) * (135.0 + 4.0 * sin(pulse * 2.0 + a))
		draw_line(inner, outer, Color(0.88, 0.48, 0.23, 0.72), 2.0, true)
		if i % 2 == 0:
			var rune := center + Vector2(cos(a), sin(a)) * 151.0
			draw_line(rune + Vector2(-4, -4), rune + Vector2(4, 4), Color(0.75, 0.35, 0.24, 0.4), 1.4, true)
			draw_line(rune + Vector2(-4, 4), rune + Vector2(4, -4), Color(0.75, 0.35, 0.24, 0.4), 1.4, true)
	# Forged heart with layered metallic shell.
	draw_circle(center, 61.0 * core_size, Color(1.0, 0.22, 0.04, 0.16 + hit_flash * 0.25))
	draw_circle(center, 48.0 * core_size, Color(0.22, 0.075, 0.085, 0.98))
	draw_arc(center, 46.0 * core_size, pulse * 0.3, pulse * 0.3 + TAU * 0.9, 64, Color(0.75, 0.39, 0.23, 0.9), 3.0, true)
	draw_circle(center, 36.0 * core_size, Color("#35151b"))
	draw_circle(center, 27.0 * core_size, Color("#a53620"))
	draw_circle(center, 19.0 * core_size, Color("#f17a2e"))
	draw_circle(center, 12.0 * core_size, Color("#ffc36a"))
	draw_circle(center, 6.0 * core_size, Color("#fff4d2"))
	for i in range(12):
		var a := TAU * float(i) / 12.0 - pulse * 0.3
		var p := center + Vector2(cos(a), sin(a)) * (76.0 + 8.0 * sin(pulse + a))
		draw_circle(p, 2.0 + hit_flash, Color(1.0, 0.58, 0.24, 0.8))
	# Keep the realm boss in the open channel between the core and the right HUD; placing it under the opaque panel hid it completely.
	_draw_boss_portrait(Vector2(size.x * 0.674, size.y * 0.445), boss_stage)
	for popup in combat_popups:
		var popup_life: float = clampf(float(popup["life"]), 0.0, 1.0)
		var popup_position: Vector2 = popup["position"]
		var popup_color: Color = popup["color"]
		popup_color.a *= minf(1.0, popup_life * 2.2)
		draw_string(ThemeDB.fallback_font, Vector2(popup_position.x - 90.0, popup_position.y), str(popup["text"]), HORIZONTAL_ALIGNMENT_CENTER, 180.0, int(popup["size"]), popup_color)
	for ember in ember_particles:
		draw_circle(Vector2(ember.x, ember.y), 1.4 + hit_flash, Color(1.0, 0.49, 0.16, 0.72))
	# Critical strikes create a bright expanding rune shockwave.
	if critical_flash > 0.0:
		var crit_alpha: float = clampf(critical_flash, 0.0, 1.0)
		draw_arc(center, 185.0 + (1.0 - crit_alpha) * 45.0, pulse * 0.8, pulse * 0.8 + TAU, 96, Color(1.0, 0.82, 0.35, crit_alpha * 0.9), 4.0, true)
		for i in range(12):
			var crit_angle: float = TAU * float(i) / 12.0 + pulse * 0.35
			var crit_inner: Vector2 = center + Vector2(cos(crit_angle), sin(crit_angle)) * 165.0
			var crit_outer: Vector2 = center + Vector2(cos(crit_angle), sin(crit_angle)) * 205.0
			draw_line(crit_inner, crit_outer, Color(1.0, 0.76, 0.31, crit_alpha * 0.85), 3.0, true)
	# Realm transition blooms through the ruined sanctum when a boss falls.
	if boss_transition_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.48, 0.18, boss_transition_flash * 0.24))
	# Deep vignette and forged horizon.
	draw_rect(Rect2(0, size.y - 145.0, size.x, 2), Color(0.75, 0.32, 0.19, 0.26))
	draw_rect(Rect2(0, 87, size.x, 1), Color(0.75, 0.34, 0.19, 0.26))
	for i in range(6):
		var inset := float(i) * 7.0
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), Color(0.22, 0.08, 0.1, 0.045), false, 1.0)

func _draw_sanctum_architecture(size: Vector2) -> void:
	# Tall broken pillars and narrow stained-glass windows frame the forge without covering the HUD.
	for side in [-1.0, 1.0]:
		var pillar_x: float = size.x * (0.5 + side * 0.405)
		var pillar_color := Color(0.075, 0.045, 0.06, 0.9)
		draw_colored_polygon(PackedVector2Array([
			Vector2(pillar_x - 16.0, 0.0), Vector2(pillar_x + 16.0, 0.0),
			Vector2(pillar_x + 10.0, size.y * 0.72), Vector2(pillar_x - 11.0, size.y * 0.72)
		]), pillar_color)
		draw_line(Vector2(pillar_x - 11.0, 0.0), Vector2(pillar_x - 8.0, size.y * 0.72), Color(0.58, 0.27, 0.2, 0.22), 2.0, true)
		draw_line(Vector2(pillar_x + 12.0, 0.0), Vector2(pillar_x + 9.0, size.y * 0.72), Color(0.22, 0.13, 0.16, 0.7), 3.0, true)
		var glass_x: float = size.x * (0.5 + side * 0.265)
		var glass_alpha: float = 0.035 + 0.018 * absf(sin(pulse * 0.55 + side))
		draw_colored_polygon(PackedVector2Array([
			Vector2(glass_x, 32.0), Vector2(glass_x + side * 35.0, 74.0),
			Vector2(glass_x + side * 27.0, size.y * 0.32), Vector2(glass_x, size.y * 0.39),
			Vector2(glass_x - side * 27.0, size.y * 0.32), Vector2(glass_x - side * 35.0, 74.0)
		]), Color(0.5, 0.12, 0.16, glass_alpha))
		draw_line(Vector2(glass_x, 42.0), Vector2(glass_x, size.y * 0.36), Color(0.82, 0.39, 0.24, 0.13), 1.5, true)
		draw_line(Vector2(glass_x - 24.0, size.y * 0.2), Vector2(glass_x + 24.0, size.y * 0.2), Color(0.82, 0.39, 0.24, 0.1), 1.0, true)
	# Perspective seams and a rune-etched dais ground the core in a physical chamber.
	var horizon_y: float = size.y * 0.68
	for i in range(9):
		var floor_x: float = size.x * float(i) / 8.0
		draw_line(Vector2(size.x * 0.5, horizon_y), Vector2(floor_x, size.y), Color(0.42, 0.2, 0.17, 0.085), 1.0, true)
	for i in range(5):
		var depth: float = float(i) / 4.0
		var floor_y: float = lerpf(horizon_y, size.y, depth * depth)
		draw_line(Vector2(0.0, floor_y), Vector2(size.x, floor_y), Color(0.42, 0.2, 0.17, 0.07 + depth * 0.035), 1.0, true)
	var dais_center := Vector2(size.x * 0.5, size.y * 0.79)
	for i in range(4):
		var radius: float = 68.0 + float(i) * 21.0
		draw_arc(dais_center, radius, PI * 1.08, PI * 1.92, 64, Color(0.76, 0.34, 0.19, 0.17 - float(i) * 0.025), 1.5, true)
	for i in range(13):
		var a: float = PI * 1.08 + PI * 0.84 * float(i) / 12.0
		var inner := dais_center + Vector2(cos(a), sin(a)) * 74.0
		var outer := dais_center + Vector2(cos(a), sin(a)) * 128.0
		draw_line(inner, outer, Color(0.86, 0.43, 0.22, 0.19), 1.2, true)

func _draw_boss_portrait(center: Vector2, stage: int) -> void:
	var bob: float = sin(pulse * 1.35 + float(stage)) * 4.0
	var c: Color
	var eye_color := Color("#ff5938")
	match posmod(stage - 1, 4):
		0:
			c = Color("#b64b37")
			eye_color = Color("#ff5938")
		1:
			c = Color("#a6aebc")
			eye_color = Color("#bceaff")
		2:
			c = Color("#9a6ad0")
			eye_color = Color("#e7a8ff")
		3:
			c = Color("#d19b4d")
			eye_color = Color("#ffe19a")
	center.y += bob
	center.x += sin(pulse * 54.0) * boss_shake * 7.0
	var hp_ratio: float = clampf(boss_hp / maxf(boss_max_hp, 1.0), 0.0, 1.0)
	var danger_pulse: float = (1.0 - hp_ratio) * 0.06 * (0.5 + 0.5 * sin(pulse * 5.0))
	var aura: float = 0.08 + 0.025 * sin(pulse * 1.8) + boss_hit_flash * 0.22 + danger_pulse
	# A layered, stage-tinted halo separates the gatekeeper from the cathedral.
	draw_circle(center, 99.0 + sin(pulse * 1.8) * 4.0, Color(c.r, c.g, c.b, aura))
	draw_arc(center, 88.0, pulse * 0.12, pulse * 0.12 + TAU * 0.72, 72, Color(c.r, c.g, c.b, 0.42), 2.0, true)
	draw_arc(center, 76.0, -pulse * 0.17, -pulse * 0.17 + TAU * 0.58, 64, Color(0.92, 0.63, 0.35, 0.28), 1.3, true)
	for i in range(8):
		var a: float = TAU * float(i) / 8.0 - pulse * 0.12
		var p: Vector2 = center + Vector2(cos(a), sin(a)) * 84.0
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(4, 0), p + Vector2(0, 5), p + Vector2(-4, 0)]), Color(c.r, c.g, c.b, 0.8))
	# Back horns and crown silhouette.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-31, -40), center + Vector2(-73, -91), center + Vector2(-62, -30),
		center + Vector2(-42, -13), center + Vector2(42, -13), center + Vector2(62, -30),
		center + Vector2(73, -91), center + Vector2(31, -40), center + Vector2(18, -58),
		center + Vector2(-18, -58)
	]), Color("#08070d"))
	draw_line(center + Vector2(-68, -78), center + Vector2(-54, -35), Color(c.r, c.g, c.b, 0.78), 2.0, true)
	draw_line(center + Vector2(68, -78), center + Vector2(54, -35), Color(c.r, c.g, c.b, 0.78), 2.0, true)
	# Broad pauldrons, engraved plates and a tapered breastplate.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-24, -12), center + Vector2(-74, 0), center + Vector2(-96, 25),
		center + Vector2(-68, 43), center + Vector2(-40, 34), center + Vector2(-30, 48),
		center + Vector2(30, 48), center + Vector2(40, 34), center + Vector2(68, 43),
		center + Vector2(96, 25), center + Vector2(74, 0), center + Vector2(24, -12)
	]), Color("#171019"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-68, 8), center + Vector2(-88, 25), center + Vector2(-66, 36),
		center + Vector2(-49, 27), center + Vector2(-55, 16)
	]), Color(c.r * 0.55, c.g * 0.45, c.b * 0.48, 0.95))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(68, 8), center + Vector2(88, 25), center + Vector2(66, 36),
		center + Vector2(49, 27), center + Vector2(55, 16)
	]), Color(c.r * 0.55, c.g * 0.45, c.b * 0.48, 0.95))
	draw_line(center + Vector2(-74, 14), center + Vector2(-60, 29), Color(c.r, c.g, c.b, 0.8), 2.0, true)
	draw_line(center + Vector2(74, 14), center + Vector2(60, 29), Color(c.r, c.g, c.b, 0.8), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-37, 22), center + Vector2(-27, 65), center + Vector2(0, 82),
		center + Vector2(27, 65), center + Vector2(37, 22), center + Vector2(0, 7)
	]), Color("#09070d"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-25, 27), center + Vector2(0, 17), center + Vector2(25, 27),
		center + Vector2(18, 54), center + Vector2(0, 67), center + Vector2(-18, 54)
	]), Color(c.r * 0.44, c.g * 0.35, c.b * 0.42, 0.95))
	draw_line(center + Vector2(0, 22), center + Vector2(0, 61), Color(1.0, 0.65, 0.32, 0.7), 1.5, true)
	for i in range(3):
		var rib_y: float = 38.0 + float(i) * 8.0
		draw_line(center + Vector2(-19 + float(i) * 3.0, rib_y), center + Vector2(19 - float(i) * 3.0, rib_y), Color(c.r, c.g, c.b, 0.48), 1.5, true)
	# Face, brow ridge and a narrow glowing visor make the portrait readable at phone scale.
	draw_circle(center + Vector2(0, -25), 35.0, Color("#09070d"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-26, -43), center + Vector2(-17, -57), center + Vector2(0, -62),
		center + Vector2(17, -57), center + Vector2(26, -43), center + Vector2(23, -13),
		center + Vector2(0, 3), center + Vector2(-23, -13)
	]), Color("#21131b"))
	draw_line(center + Vector2(-28, -43), center + Vector2(-15, -51), Color(c.r, c.g, c.b, 0.9), 2.0, true)
	draw_line(center + Vector2(28, -43), center + Vector2(15, -51), Color(c.r, c.g, c.b, 0.9), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-23, -32), center + Vector2(-4, -28), center + Vector2(-11, -20),
		center + Vector2(-23, -23)
	]), eye_color)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(23, -32), center + Vector2(4, -28), center + Vector2(11, -20),
		center + Vector2(23, -23)
	]), eye_color)
	draw_circle(center + Vector2(-13, -25), 2.0, Color("#fff4d2"))
	draw_circle(center + Vector2(13, -25), 2.0, Color("#fff4d2"))
	draw_line(center + Vector2(-15, 2), center + Vector2(0, 20), Color(c.r, c.g, c.b, 0.95), 2.0, true)
	draw_line(center + Vector2(15, 2), center + Vector2(0, 20), Color(c.r, c.g, c.b, 0.95), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-9, 14), center + Vector2(0, 9), center + Vector2(9, 14),
		center + Vector2(0, 28)
	]), Color(0.98, 0.55, 0.26, 0.88))
	# Fine sparks orbit the portrait in the same palette as the active realm.
	for i in range(5):
		var a: float = pulse * 0.4 + TAU * float(i) / 5.0
		var spark: Vector2 = center + Vector2(cos(a), sin(a)) * (99.0 + 5.0 * sin(pulse * 2.0 + a))
		draw_circle(spark, 1.5 + 0.6 * absf(sin(pulse * 2.0 + a)), Color(1.0, 0.68, 0.36, 0.78))

func _boss_name(stage: int) -> String:
	return BOSS_NAMES[posmod(stage - 1, BOSS_NAMES.size())]

func _show_splash() -> void:
	_clear_ui()
	var logo := _label("✦", Vector2(0, 108), Vector2(1280, 70), 44, Color("#f2b75d"))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label("CLICKER: GODFORGE", Vector2(0, 190), Vector2(1280, 76), 42, Color("#f6e4c4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label("FORGE POWER  •  BREAK THE GODS", Vector2(0, 265), Vector2(1280, 34), 16, Color("#c17a55"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var loading := _label("AWAKENING THE ANCIENT CORE...", Vector2(0, 535), Vector2(1280, 28), 13, Color("#9c8b8a"))
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar := ProgressBar.new()
	bar.position = Vector2(490, 575)
	bar.size = Vector2(300, 8)
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	bar.show_percentage = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e69a49")
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", style)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#30202a")
	track.corner_radius_top_left = 4
	track.corner_radius_top_right = 4
	track.corner_radius_bottom_left = 4
	track.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", track)
	add_child(bar)
	var tween := create_tween()
	tween.tween_property(bar, "value", 100.0, 2.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _show_title() -> void:
	_clear_ui()
	var eyebrow := _label("AN ANCIENT POWER STIRS", Vector2(0, 110), Vector2(1280, 28), 13, Color("#d58b4c"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label("CLICKER: GODFORGE", Vector2(0, 155), Vector2(1280, 72), 40, Color("#f6e4c4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("Every strike feeds the fire. Every fire breaks a world.", Vector2(0, 230), Vector2(1280, 34), 17, Color("#c5a69a"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label("DARK FANTASY  •  IDLE PROGRESSION  •  TITAN BOSSES", Vector2(0, 475), Vector2(1280, 30), 13, Color("#b36d4b"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var begin := _button("BEGIN ASCENSION", Vector2(465, 535), Vector2(350, 66), true)
	begin.add_theme_font_size_override("font_size", 20)
	begin.pressed.connect(_start_game)
	var hint := _label("TAP THE CORE  •  BUILD YOUR FORGE  •  SLAY THE TITANS", Vector2(0, 620), Vector2(1280, 24), 11, Color("#786b75"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _start_game() -> void:
	playing = true
	_build_game_ui()
	_refresh_ui()

func _build_game_ui() -> void:
	_clear_ui()
	var logo := _label("✦  GODFORGE", Vector2(32, 18), Vector2(300, 44), 24, Color("#f2d6ac"))
	_label("THE ASHEN SANCTUM  /  WORLD %02d" % boss_stage, Vector2(34, 61), Vector2(380, 22), 11, Color("#a97b66"))
	ui_labels["energy"] = _label("ENERGY  0", Vector2(820, 22), Vector2(210, 34), 20, Color("#f5c16e"))
	ui_labels["rate"] = _label("0 / SEC", Vector2(820, 55), Vector2(190, 22), 12, Color("#c08b65"))
	ui_labels["stage"] = _label("REALM  01", Vector2(1050, 22), Vector2(190, 28), 17, Color("#f1dfc5"))
	ui_labels["shards"] = _label("GODSHARDS  0", Vector2(1050, 53), Vector2(190, 22), 11, Color("#a99ce2"))
	_panel(Vector2(30, 118), Vector2(255, 340))
	_label("FORGE STATUS", Vector2(52, 136), Vector2(210, 26), 16, Color("#e7c9a5"))
	ui_labels["power"] = _label("STRIKE POWER\n1", Vector2(52, 180), Vector2(210, 52), 18, Color("#f2b75d"))
	ui_labels["crit"] = _label("CRITICAL CHANCE\n5%", Vector2(52, 250), Vector2(210, 48), 14, Color("#d98a69"))
	ui_labels["dps"] = _label("IDLE OUTPUT\n0 / sec", Vector2(52, 316), Vector2(210, 48), 14, Color("#c7a7a0"))
	_label("THE CORE RESPONDS TO EVERY STRIKE", Vector2(310, 118), Vector2(660, 24), 12, Color("#b98a72")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	core_button = _button("", Vector2(505, 215), Vector2(270, 220), false)
	var core_normal := StyleBoxFlat.new()
	core_normal.bg_color = Color(0, 0, 0, 0)
	core_normal.border_color = Color(0, 0, 0, 0)
	core_normal.set_border_width_all(0)
	var core_hover := core_normal.duplicate() as StyleBoxFlat
	core_hover.bg_color = Color(0.85, 0.28, 0.08, 0.06)
	var core_pressed := core_normal.duplicate() as StyleBoxFlat
	core_pressed.bg_color = Color(1.0, 0.55, 0.18, 0.12)
	core_button.add_theme_stylebox_override("normal", core_normal)
	core_button.add_theme_stylebox_override("hover", core_hover)
	core_button.add_theme_stylebox_override("pressed", core_pressed)
	core_button.pressed.connect(_strike_core)
	ui_labels["hit"] = _label("TAP TO STRIKE", Vector2(510, 420), Vector2(260, 25), 12, Color("#d58b4c"))
	ui_labels["hit"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel(Vector2(945, 118), Vector2(305, 340))
	_label("REALM GATEKEEPER", Vector2(968, 136), Vector2(250, 24), 15, Color("#dfb89e"))
	ui_labels["boss"] = _label(_boss_name(boss_stage), Vector2(968, 168), Vector2(250, 24), 13, Color("#f0d9c2"))
	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(968, 208)
	boss_bar.size = Vector2(255, 18)
	boss_bar.min_value = 0
	boss_bar.max_value = boss_max_hp
	boss_bar.value = boss_hp
	boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#c44738")
	fill.corner_radius_top_left = 5
	fill.corner_radius_top_right = 5
	fill.corner_radius_bottom_left = 5
	fill.corner_radius_bottom_right = 5
	boss_bar.add_theme_stylebox_override("fill", fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#321c25")
	bg.corner_radius_top_left = 5
	bg.corner_radius_top_right = 5
	bg.corner_radius_bottom_left = 5
	bg.corner_radius_bottom_right = 5
	boss_bar.add_theme_stylebox_override("background", bg)
	add_child(boss_bar)
	ui_labels["boss_fill_style"] = fill
	for marker_index in range(1, 4):
		var hp_marker := ColorRect.new()
		hp_marker.position = Vector2(968.0 + 255.0 * float(marker_index) / 4.0 - 1.0, 208.0)
		hp_marker.size = Vector2(2.0, 18.0)
		hp_marker.color = Color("#512832")
		hp_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hp_marker)
	ui_labels["boss_hp"] = _label("500 / 500 HP", Vector2(968, 232), Vector2(255, 22), 12, Color("#d8b9a8"))
	ui_labels["boss_threat"] = _label("THREAT: STABLE", Vector2(968, 253), Vector2(255, 18), 10, Color("#d5a77a"))
	ui_labels["boss_threat"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui_labels["boss_hint"] = _label("Break the Titan to claim\na Godshard.", Vector2(968, 277), Vector2(255, 48), 13, Color("#aa8b87"))
	boost_button = _button("REWARDED AD x2  (DEMO)", Vector2(968, 365), Vector2(255, 52), true)
	boost_button.add_theme_font_size_override("font_size", 13)
	boost_button.pressed.connect(_activate_ad_demo)
	_label("BONUS SIMULATION — NO AD SDK YET", Vector2(968, 423), Vector2(255, 20), 9, Color("#8c777b"))
	_label("FORGE UPGRADES", Vector2(32, 486), Vector2(300, 25), 16, Color("#e7c9a5"))
	var card_x := [32.0, 340.0, 648.0, 956.0]
	for i in range(4):
		_build_upgrade_card(i, Vector2(card_x[i], 520))
	_label("CLICK  •  COLLECT  •  ASCEND", Vector2(0, 690), Vector2(1280, 20), 10, Color("#77646b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_upgrade_card(index: int, pos: Vector2) -> void:
	var card := _button("", pos, Vector2(290, 154), false)
	card.pivot_offset = card.size * 0.5
	card.add_theme_font_size_override("font_size", 12)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.add_theme_color_override("font_color", Color("#f4dfc5"))
	card.add_theme_color_override("font_hover_color", Color("#fff0c9"))
	card.add_theme_color_override("font_disabled_color", Color("#8b7779"))
	card.pressed.connect(func(): _buy_upgrade(index))
	ui_labels["upgrade_%d" % index] = card

	var accent := ColorRect.new()
	accent.position = pos + Vector2(12, 2)
	accent.size = Vector2(266, 2)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	accent.color = Color("#e6a45d")
	add_child(accent)
	ui_labels["upgrade_accent_%d" % index] = accent

	var medallion := Panel.new()
	medallion.position = pos + Vector2(14, 14)
	medallion.size = Vector2(48, 48)
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var medallion_style := StyleBoxFlat.new()
	medallion_style.bg_color = Color("#120c13")
	medallion_style.border_color = Color("#b87949")
	medallion_style.set_border_width_all(1)
	medallion_style.set_corner_radius_all(8)
	medallion.add_theme_stylebox_override("panel", medallion_style)
	add_child(medallion)

	var glyph := _label(UPGRADE_GLYPHS[index], pos + Vector2(14, 12), Vector2(48, 50), 27, Color("#f1b96f"))
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_icon_%d" % index] = glyph

	var title := _label(UPGRADE_NAMES[index], pos + Vector2(72, 11), Vector2(205, 24), 13, Color("#f5dfc4"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_name_%d" % index] = title

	var desc := _label(UPGRADE_DESC[index], pos + Vector2(16, 66), Vector2(258, 27), 11, Color("#bda39d"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_desc_%d" % index] = desc

	var level_label := _label("LEVEL  00", pos + Vector2(16, 98), Vector2(92, 20), 11, Color("#e5c8a2"))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_level_%d" % index] = level_label

	var state_label := _label("READY TO FORGE", pos + Vector2(104, 98), Vector2(172, 20), 9, Color("#f2bb70"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_state_%d" % index] = state_label

	var cost_label := _label("✦  25 ENERGY", pos + Vector2(16, 122), Vector2(258, 22), 13, Color("#f3bd70"))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_cost_%d" % index] = cost_label


func _strike_core() -> void:
	hit_flash = 1.0
	core_recoil = 1.0
	for i in range(22):
		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(55.0, 210.0)
		var origin := Vector2(640.0, 345.0) + Vector2(cos(angle), sin(angle)) * rng.randf_range(24.0, 48.0)
		ember_particles.append(Vector4(origin.x, origin.y, cos(angle) * speed, sin(angle) * speed))
	var damage := click_power * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)
	var critical := rng.randf() < 0.08
	if critical:
		damage *= 5.0
		critical_flash = 1.0
	energy += damage
	var boss_hit_damage := damage * boss_damage
	boss_hp -= boss_hit_damage
	boss_hit_flash = 1.0
	boss_shake = 1.0
	combat_popups.append({"text": ("CRITICAL  -" if critical else "-") + _format_number(boss_hit_damage), "position": Vector2(862.0 + rng.randf_range(-24.0, 24.0), 286.0), "life": 1.0, "size": 23 if critical else 18, "color": Color("#ffe28b") if critical else Color("#ff8c72")})
	combat_popups.append({"text": "+" + _format_number(damage) + " ENERGY", "position": Vector2(640.0 + rng.randf_range(-20.0, 20.0), 284.0), "life": 0.82, "size": 15, "color": Color("#ffc879")})
	if ui_labels.has("hit"):
		ui_labels["hit"].text = ("CRITICAL HIT!  +" if critical else "CORE STRUCK  +") + _format_number(damage)
		ui_labels["hit"].add_theme_color_override("font_color", Color("#fff0a3") if critical else Color("#d58b4c"))
	if boss_hp <= 0.0:
		boss_stage += 1
		energy += 250.0 * boss_stage
		boss_max_hp *= 1.72
		boss_hp = boss_max_hp
		multiplier *= 1.08
		boss_transition_flash = 1.0
		critical_flash = 0.0
		boss_hit_flash = 0.0
		boss_shake = 0.0
		combat_popups.append({"text": "GATEKEEPER SHATTERED", "position": Vector2(862.0, 230.0), "life": 1.35, "size": 20, "color": Color("#ffe6a0")})
		if ui_labels.has("boss_hint"):
			ui_labels["boss_hint"].text = "GATEKEEPER SLAIN!\n+1 GODSHARD  •  POWER +8%"
	_refresh_ui()

func _buy_upgrade(index: int) -> void:
	var cost := _upgrade_cost(index)
	if energy < cost:
		if ui_labels.has("power"):
			ui_labels["power"].text = "NOT ENOUGH ENERGY"
		return
	energy -= cost
	upgrade_levels[index] += 1
	upgrade_feedback_time[index] = 0.9
	match index:
		0:
			click_power *= 1.55
		1:
			idle_rate += 1.0 * pow(1.32, upgrade_levels[index] - 1)
		2:
			multiplier *= 1.18
		3:
			boss_damage *= 1.45
	_refresh_ui()
	var purchased_card: Button = ui_labels["upgrade_%d" % index]
	var feedback_tween := create_tween()
	feedback_tween.tween_property(purchased_card, "scale", Vector2(1.045, 1.06), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	feedback_tween.tween_property(purchased_card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _upgrade_cost(index: int) -> float:
	return UPGRADE_BASE_COST[index] * pow(1.72, upgrade_levels[index])

func _activate_ad_demo() -> void:
	ad_boost_time = 60.0
	energy += 50.0 * multiplier
	if boost_button != null:
		boost_button.text = "AD BONUS x2  60 s"
	_refresh_ui()

func _refresh_ui() -> void:
	if not playing:
		return
	if ui_labels.has("energy"):
		ui_labels["energy"].text = "ENERGY  " + _format_number(energy)
		ui_labels["rate"].text = _format_number(idle_rate * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)) + " / SEC"
		ui_labels["stage"].text = "REALM  %02d" % boss_stage
		ui_labels["shards"].text = "GODSHARDS  %d" % (boss_stage - 1)
		ui_labels["power"].text = "STRIKE POWER\n" + _format_number(click_power * multiplier)
		ui_labels["crit"].text = "CRITICAL CHANCE\n8%  •  x5 DAMAGE"
		ui_labels["dps"].text = "IDLE OUTPUT\n" + _format_number(idle_rate * multiplier) + " / sec"
		ui_labels["boss"].text = _boss_name(boss_stage) + "  •  %02d" % boss_stage
		ui_labels["boss_hp"].text = _format_number(maxf(0.0, boss_hp)) + " / " + _format_number(boss_max_hp) + " HP"
		var hp_ratio: float = clampf(boss_hp / maxf(boss_max_hp, 1.0), 0.0, 1.0)
		var threat_label: Label = ui_labels["boss_threat"]
		if hp_ratio <= 0.2:
			threat_label.text = "THREAT: CRITICAL"
			threat_label.add_theme_color_override("font_color", Color("#ff715c"))
		elif hp_ratio <= 0.5:
			threat_label.text = "THREAT: ELEVATED"
			threat_label.add_theme_color_override("font_color", Color("#e6a45d"))
		else:
			threat_label.text = "THREAT: STABLE"
			threat_label.add_theme_color_override("font_color", Color("#d5a77a"))
		var fill_style: StyleBoxFlat = ui_labels["boss_fill_style"]
		fill_style.bg_color = Color("#ff573f") if hp_ratio <= 0.2 else (Color("#d47746") if hp_ratio <= 0.5 else Color("#c44738"))
	if boss_bar != null and is_instance_valid(boss_bar):
		boss_bar.max_value = boss_max_hp
		boss_bar.value = maxf(0.0, boss_hp)
	for i in range(4):
		var cost := _upgrade_cost(i)
		var can_afford := energy >= cost
		var level := int(upgrade_levels[i])
		var card: Button = ui_labels["upgrade_%d" % i]
		var state_label: Label = ui_labels["upgrade_state_%d" % i]
		var cost_label: Label = ui_labels["upgrade_cost_%d" % i]
		var level_label: Label = ui_labels["upgrade_level_%d" % i]
		var accent: ColorRect = ui_labels["upgrade_accent_%d" % i]
		card.disabled = not can_afford
		card.modulate = Color.WHITE
		level_label.text = "LEVEL  %02d" % level
		cost_label.text = "✦  %s ENERGY" % _format_number(cost)
		if upgrade_feedback_time[i] > 0.0:
			state_label.text = "FORGED!  +1 LEVEL"
			state_label.add_theme_color_override("font_color", Color("#ffe6a0"))
		elif can_afford and level == 0:
			state_label.text = "READY TO FORGE"
			state_label.add_theme_color_override("font_color", Color("#f2bb70"))
		elif can_afford:
			state_label.text = "UPGRADE READY"
			state_label.add_theme_color_override("font_color", Color("#e5b56f"))
		elif level > 0:
			state_label.text = "FORGED • NEED ENERGY"
			state_label.add_theme_color_override("font_color", Color("#a88a83"))
		else:
			state_label.text = "NEED ENERGY"
			state_label.add_theme_color_override("font_color", Color("#907b82"))
		accent.color = Color("#e6a45d") if can_afford else Color("#513541")
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("#21151b") if can_afford else Color("#100d14")
		normal.border_color = Color("#a96b3d") if can_afford else Color("#44303a")
		normal.set_border_width_all(2 if can_afford else 1)
		normal.set_corner_radius_all(12)
		normal.shadow_color = Color(0.0, 0.0, 0.0, 0.52)
		normal.shadow_size = 9
		normal.content_margin_left = 14
		normal.content_margin_right = 14
		normal.content_margin_top = 12
		normal.content_margin_bottom = 12
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("#38221e") if can_afford else Color("#18121a")
		hover.border_color = Color("#ffd080") if can_afford else Color("#72505a")
		hover.set_border_width_all(2)
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("#110a10")
		pressed.border_color = Color("#d47746")
		var disabled_style := normal.duplicate() as StyleBoxFlat
		disabled_style.bg_color = Color("#100d14")
		disabled_style.border_color = Color("#44303a")
		card.add_theme_stylebox_override("normal", normal)
		card.add_theme_stylebox_override("hover", hover)
		card.add_theme_stylebox_override("pressed", pressed)
		card.add_theme_stylebox_override("disabled", disabled_style)

func _format_number(value: float) -> String:
	if value >= 1.0e12:
		return "%.2fT" % (value / 1.0e12)
	if value >= 1.0e9:
		return "%.2fB" % (value / 1.0e9)
	if value >= 1.0e6:
		return "%.2fM" % (value / 1.0e6)
	if value >= 1.0e3:
		return "%.2fK" % (value / 1.0e3)
	return str(int(value))

func _panel(pos: Vector2, size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.022, 0.042, 0.94)
	style.border_color = Color(0.62, 0.29, 0.18, 0.92)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0.58)
	style.shadow_size = 16
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	# A restrained inner keyline and a warm top edge make each HUD slab feel forged.
	var inner := Panel.new()
	inner.position = Vector2(4, 4)
	inner.size = size - Vector2(8, 8)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0, 0, 0, 0)
	inner_style.border_color = Color(0.82, 0.48, 0.27, 0.18)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(7)
	inner.add_theme_stylebox_override("panel", inner_style)
	panel.add_child(inner)
	var top_edge := ColorRect.new()
	top_edge.position = Vector2(14, 1)
	top_edge.size = Vector2(size.x - 28, 1)
	top_edge.color = Color(0.94, 0.57, 0.31, 0.48)
	panel.add_child(top_edge)
	add_child(panel)
	return panel

func _button(text_value: String, pos: Vector2, size: Vector2, gold: bool) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("#f5e5d2"))
	button.add_theme_color_override("font_hover_color", Color("#fff4d8"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#4c281f") if gold else Color(0.045, 0.028, 0.05, 0.93)
	normal.border_color = Color("#d58b4c") if gold else Color("#6e3c32")
	normal.set_border_width_all(2 if gold else 1)
	normal.set_corner_radius_all(9)
	normal.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	normal.shadow_size = 5
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#6b3825") if gold else Color("#281721")
	hover.border_color = Color("#ffd080")
	hover.set_border_width_all(2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#26131a")
	pressed.border_color = Color("#b75a3b")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", normal)
	add_child(button)
	return button

func _label(value: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = pos
	label.size = size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	add_child(label)
	return label

func _clear_ui() -> void:
	for child in get_children():
		child.queue_free()
	ui_labels.clear()
	boss_bar = null
	core_button = null
	boost_button = null

func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "energy", energy)
	cfg.set_value("progress", "idle_rate", idle_rate)
	cfg.set_value("progress", "click_power", click_power)
	cfg.set_value("progress", "multiplier", multiplier)
	cfg.set_value("progress", "boss_damage", boss_damage)
	cfg.set_value("progress", "boss_stage", boss_stage)
	cfg.set_value("progress", "boss_hp", boss_hp)
	cfg.set_value("progress", "boss_max_hp", boss_max_hp)
	cfg.set_value("progress", "upgrade_levels", upgrade_levels)
	cfg.set_value("progress", "last_time", int(Time.get_unix_time_from_system()))
	cfg.save(SAVE_PATH)

func _load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	energy = float(cfg.get_value("progress", "energy", 0.0))
	idle_rate = float(cfg.get_value("progress", "idle_rate", 0.0))
	click_power = float(cfg.get_value("progress", "click_power", 1.0))
	multiplier = float(cfg.get_value("progress", "multiplier", 1.0))
	boss_damage = float(cfg.get_value("progress", "boss_damage", 1.0))
	boss_stage = int(cfg.get_value("progress", "boss_stage", 1))
	boss_hp = float(cfg.get_value("progress", "boss_hp", 500.0))
	boss_max_hp = float(cfg.get_value("progress", "boss_max_hp", 500.0))
	upgrade_levels = cfg.get_value("progress", "upgrade_levels", [0, 0, 0, 0])
	var last_time := int(cfg.get_value("progress", "last_time", int(Time.get_unix_time_from_system())))
	var elapsed := clampf(float(Time.get_unix_time_from_system() - last_time), 0.0, 28800.0)
	energy += idle_rate * multiplier * elapsed * 0.5

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
