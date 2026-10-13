extends Control

const SAVE_PATH := "user://godforge_save.cfg"
const UPGRADE_NAMES := ["МОЛОТ КУЗНИ", "ДВИГАТЕЛЬ ДУШ", "РУНА РАЗРУШЕНИЯ", "ГРАНЬ БОГОУБИЙЦЫ"]
const UPGRADE_DESC := ["Больше силы с каждого удара", "Получай энергию в простое", "Увеличивает всё производство", "Больше урона боссам"]
const UPGRADE_BASE_COST := [25.0, 80.0, 180.0, 320.0]
const BOSS_NAMES := ["ПОЛЫЙ ТИТАН", "ПЕПЕЛЬНЫЙ ЗМЕЙ", "КОРОЛЕВА ПЕЛЕНЫ", "ЖЕЛЕЗНЫЙ СВЯТОЙ"]
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
var boss_slash_flash := 0.0
var boss_slash_angle := 0.0
var boss_slash_critical := false
var combo_count := 0
var combo_time := 0.0
var combat_popups: Array[Dictionary] = []
var upgrade_feedback_time := [0.0, 0.0, 0.0, 0.0]
var energy_flash := 0.0
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
var journal_button: Button
var journal_overlay: Control
var total_clicks := 0
var total_upgrades := 0
var boss_victories := 0
var last_boss_reward := 0.0
var victory_banner_time := 0.0
var victory_banner_text := ""
var achievement_popup_time := 0.0
var achievement_popup_text := ""
var achievement_popup_queue: Array[String] = []
var claimed_achievements: Array[String] = []
var boss_history: Array[Dictionary] = []
var lifetime_energy_earned := 0.0
var session_started_at := 0
var total_play_seconds := 0
var boss_stage_start_clicks := 0
var victory_summary: Control

func _ready() -> void:
	rng.randomize()
	for i in range(100):
		stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))
	_load_game()
	session_started_at = int(Time.get_unix_time_from_system())
	set_process(true)
	_show_splash()
	await get_tree().create_timer(2.4).timeout
	if is_inside_tree() and not playing:
		_show_title()

func _process(delta: float) -> void:
	pulse += delta
	hit_flash = maxf(0.0, hit_flash - delta * 2.8)
	energy_flash = maxf(0.0, energy_flash - delta * 2.4)
	core_recoil = move_toward(core_recoil, 0.0, delta * 4.5)
	critical_flash = maxf(0.0, critical_flash - delta * 2.2)
	boss_transition_flash = maxf(0.0, boss_transition_flash - delta * 1.35)
	victory_banner_time = maxf(0.0, victory_banner_time - delta)
	achievement_popup_time = maxf(0.0, achievement_popup_time - delta)
	if achievement_popup_time <= 0.0 and not achievement_popup_queue.is_empty():
		achievement_popup_text = achievement_popup_queue.pop_front()
		achievement_popup_time = 3.0
	boss_hit_flash = maxf(0.0, boss_hit_flash - delta * 3.2)
	boss_shake = move_toward(boss_shake, 0.0, delta * 4.8)
	boss_slash_flash = maxf(0.0, boss_slash_flash - delta * (2.6 if boss_slash_critical else 3.8))
	if combo_time > 0.0:
		combo_time = maxf(0.0, combo_time - delta)
		if combo_time <= 0.0:
			combo_count = 0
			if playing and ui_labels.has("combo"):
				ui_labels["combo"].text = "СЕРИЯ УДАРОВ: —"
				ui_labels["combo"].add_theme_color_override("font_color", Color("#8c777b"))
	if ui_labels.has("combo_timer_fill"):
		var combo_fill: ColorRect = ui_labels["combo_timer_fill"]
		combo_fill.size.x = 250.0 * clampf(combo_time / 1.5, 0.0, 1.0)
		combo_fill.color = Color("#ff795f") if combo_count >= 100 else (Color("#ffb56b") if combo_count >= 25 else Color("#e6a45d"))
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
			var passive_gain: float = idle_rate * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)
			energy += passive_gain
			lifetime_energy_earned += passive_gain
			_refresh_ui()
	for i in range(4):
		if upgrade_feedback_time[i] > 0.0:
			upgrade_feedback_time[i] = maxf(0.0, upgrade_feedback_time[i] - delta)
			if upgrade_feedback_time[i] <= 0.0 and playing:
				_refresh_ui()
	if ad_boost_time > 0.0:
		ad_boost_time = maxf(0.0, ad_boost_time - delta)
		if boost_button != null and is_instance_valid(boost_button):
			boost_button.text = "БОНУС x2  %02d с" % int(ceil(ad_boost_time)) if ad_boost_time > 0.0 else "БОНУС x2  (ДЕМО)"
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
	_draw_boss_impact(size)
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
	if achievement_popup_time > 0.0:
		var achievement_alpha: float = clampf(achievement_popup_time / 0.45, 0.0, 1.0)
		var achievement_rect := Rect2(Vector2(400, 158), Vector2(480, 48))
		draw_rect(achievement_rect, Color(0.055, 0.025, 0.035, 0.94 * achievement_alpha), true)
		draw_rect(achievement_rect, Color(0.95, 0.68, 0.31, 0.92 * achievement_alpha), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, 187), achievement_popup_text, HORIZONTAL_ALIGNMENT_CENTER, 1280, 15, Color(1.0, 0.84, 0.55, achievement_alpha))
	if victory_banner_time > 0.0:
		var banner_alpha: float = clampf(victory_banner_time / 1.4, 0.0, 1.0)
		var banner_rect := Rect2(Vector2(365, 80), Vector2(550, 72))
		draw_rect(banner_rect, Color(0.035, 0.012, 0.018, 0.9 * banner_alpha), true)
		draw_rect(banner_rect, Color(0.88, 0.49, 0.24, 0.9 * banner_alpha), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(0, 122), victory_banner_text, HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1.0, 0.82, 0.53, banner_alpha))
		draw_string(ThemeDB.fallback_font, Vector2(0, 144), "НАГРАДА ЗА ПОБЕДУ  •  СЛЕДУЮЩИЙ СТРАЖ СТАЛ СИЛЬНЕЕ", HORIZONTAL_ALIGNMENT_CENTER, 1280, 10, Color(0.84, 0.64, 0.54, banner_alpha))
	if boss_transition_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.48, 0.18, boss_transition_flash * 0.24))
	# Deep vignette and forged horizon.
	draw_rect(Rect2(0, size.y - 145.0, size.x, 2), Color(0.75, 0.32, 0.19, 0.26))
	draw_rect(Rect2(0, 87, size.x, 1), Color(0.75, 0.34, 0.19, 0.26))
	for i in range(6):
		var inset := float(i) * 7.0
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), Color(0.22, 0.08, 0.1, 0.045), false, 1.0)

func _draw_boss_impact(size: Vector2) -> void:
	if boss_slash_flash <= 0.0:
		return
	var center := Vector2(size.x * 0.674, size.y * 0.445 + sin(pulse * 1.35 + float(boss_stage)) * 4.0)
	var progress: float = 1.0 - clampf(boss_slash_flash, 0.0, 1.0)
	var radius: float = 38.0 + progress * 72.0
	var alpha: float = clampf(boss_slash_flash, 0.0, 1.0)
	var slash_color := Color("#fff0a3") if boss_slash_critical else Color("#ff9270")
	var slash_width: float = 4.0 if boss_slash_critical else 2.6
	# A fast curved blade trail gives every tap a readable impact on the boss itself.
	draw_arc(center, radius, boss_slash_angle - 0.62, boss_slash_angle + 0.62, 28, Color(slash_color.r, slash_color.g, slash_color.b, alpha * 0.92), slash_width, true)
	draw_arc(center, radius + 11.0, boss_slash_angle - 0.42, boss_slash_angle + 0.42, 24, Color(1.0, 0.56, 0.31, alpha * 0.62), 1.4, true)
	for i in range(3 if boss_slash_critical else 2):
		var ray_angle: float = boss_slash_angle + (float(i) - 1.0) * 0.34
		var inner: Vector2 = center + Vector2(cos(ray_angle), sin(ray_angle)) * (radius - 9.0)
		var outer: Vector2 = center + Vector2(cos(ray_angle), sin(ray_angle)) * (radius + 9.0 + (8.0 if boss_slash_critical else 0.0))
		draw_line(inner, outer, Color(1.0, 0.78, 0.43, alpha * 0.82), 2.0 if boss_slash_critical else 1.2, true)


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
	var subtitle := _label("КУЙ СИЛУ  •  СОКРУШАЙ БОГОВ", Vector2(0, 265), Vector2(1280, 34), 16, Color("#c17a55"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var loading := _label("ПРОБУЖДЕНИЕ ДРЕВНЕГО ЯДРА...", Vector2(0, 535), Vector2(1280, 28), 13, Color("#9c8b8a"))
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
	var eyebrow := _label("ДРЕВНЯЯ СИЛА ПРОБУЖДАЕТСЯ", Vector2(0, 110), Vector2(1280, 28), 13, Color("#d58b4c"))
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label("CLICKER: GODFORGE", Vector2(0, 155), Vector2(1280, 72), 40, Color("#f6e4c4"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label("Каждый удар разжигает пламя. Каждое пламя рушит миры.", Vector2(0, 230), Vector2(1280, 34), 17, Color("#c5a69a"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label("ТЁМНОЕ ФЭНТЕЗИ  •  РАЗВИТИЕ В ПРОСТОЕ  •  БОССЫ-ТИТАНЫ", Vector2(0, 475), Vector2(1280, 30), 13, Color("#b36d4b"))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var begin := _button("НАЧАТЬ ВОСХОЖДЕНИЕ", Vector2(465, 535), Vector2(350, 66), true)
	begin.add_theme_font_size_override("font_size", 20)
	begin.pressed.connect(_start_game)
	var hint := _label("БЕЙ ПО ЯДРУ  •  УЛУЧШАЙ КУЗНЮ  •  ПОБЕЖДАЙ ТИТАНОВ", Vector2(0, 620), Vector2(1280, 24), 11, Color("#786b75"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _start_game() -> void:
	playing = true
	_build_game_ui()
	_refresh_ui()

func _build_game_ui() -> void:
	_clear_ui()
	var logo := _label("✦  КУЗНЯ БОГОВ", Vector2(32, 18), Vector2(300, 44), 24, Color("#f2d6ac"))
	_label("ПЕПЕЛЬНОЕ СВЯТИЛИЩЕ  /  МИР %02d" % boss_stage, Vector2(34, 61), Vector2(380, 22), 11, Color("#a97b66"))
	ui_labels["energy"] = _label("ЭНЕРГИЯ  0", Vector2(820, 22), Vector2(210, 34), 20, Color("#f5c16e"))
	ui_labels["rate"] = _label("0 / СЕК", Vector2(820, 55), Vector2(190, 22), 12, Color("#c08b65"))
	ui_labels["stage"] = _label("МИР  01", Vector2(1050, 22), Vector2(190, 28), 17, Color("#f1dfc5"))
	ui_labels["shards"] = _label("ОСКОЛКИ БОГА  0", Vector2(1050, 53), Vector2(190, 22), 11, Color("#a99ce2"))
	journal_button = _button("ЛЕТОПИСЬ  0/9", Vector2(565, 22), Vector2(190, 42), false)
	journal_button.add_theme_font_size_override("font_size", 13)
	journal_button.pressed.connect(_open_journal)
	var history_button := _button("ИСТОРИЯ", Vector2(565, 68), Vector2(190, 30), false)
	history_button.add_theme_font_size_override("font_size", 11)
	history_button.pressed.connect(_open_victory_summary)
	_panel(Vector2(30, 118), Vector2(255, 340))
	_label("СОСТОЯНИЕ КУЗНИ", Vector2(52, 136), Vector2(210, 26), 16, Color("#e7c9a5"))
	ui_labels["power"] = _label("СИЛА УДАРА\n1", Vector2(52, 180), Vector2(210, 52), 18, Color("#f2b75d"))
	ui_labels["crit"] = _label("ШАНС КРИТА\n5%", Vector2(52, 250), Vector2(210, 48), 14, Color("#d98a69"))
	ui_labels["dps"] = _label("ДОХОД В ПРОСТОЕ\n0 / сек", Vector2(52, 316), Vector2(210, 48), 14, Color("#c7a7a0"))
	ui_labels["lifetime"] = _label("ВСЕГО ПОЛУЧЕНО  0", Vector2(52, 366), Vector2(210, 22), 11, Color("#d8b68c"))
	ui_labels["clicks"] = _label("УДАРОВ ПО ЯДРУ  0", Vector2(52, 389), Vector2(210, 20), 11, Color("#b99b9d"))
	ui_labels["milestone"] = _label("ПУТЬ К МИРУ 10", Vector2(52, 415), Vector2(210, 18), 10, Color("#e5bd7e"))
	var milestone_track := ColorRect.new()
	milestone_track.position = Vector2(52, 440)
	milestone_track.size = Vector2(210, 5)
	milestone_track.color = Color("#39232d")
	milestone_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(milestone_track)
	var milestone_fill := ColorRect.new()
	milestone_fill.position = milestone_track.position
	milestone_fill.size = Vector2(0, 5)
	milestone_fill.color = Color("#e6a45d")
	milestone_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(milestone_fill)
	ui_labels["milestone_fill"] = milestone_fill
	_label("ЯДРО ОТЗЫВАЕТСЯ НА КАЖДЫЙ УДАР", Vector2(310, 118), Vector2(660, 24), 12, Color("#b98a72")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	ui_labels["hit"] = _label("КОСНИСЬ, ЧТОБЫ УДАРИТЬ", Vector2(510, 420), Vector2(260, 25), 12, Color("#d58b4c"))
	ui_labels["hit"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_labels["combo"] = _label("СЕРИЯ УДАРОВ: —", Vector2(510, 445), Vector2(260, 22), 11, Color("#8c777b"))
	ui_labels["combo"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var combo_timer_track := ColorRect.new()
	combo_timer_track.position = Vector2(515, 469)
	combo_timer_track.size = Vector2(250, 4)
	combo_timer_track.color = Color("#39232d")
	combo_timer_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combo_timer_track)
	var combo_timer_fill := ColorRect.new()
	combo_timer_fill.position = combo_timer_track.position
	combo_timer_fill.size = Vector2.ZERO
	combo_timer_fill.color = Color("#e6a45d")
	combo_timer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combo_timer_fill)
	ui_labels["combo_timer_fill"] = combo_timer_fill
	_panel(Vector2(945, 118), Vector2(305, 340))
	_label("СТРАЖ ВРАТ МИРА", Vector2(968, 136), Vector2(250, 24), 15, Color("#dfb89e"))
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
	var phase_markers: Array[ColorRect] = []
	for marker_index in range(1, 4):
		var hp_marker := ColorRect.new()
		hp_marker.position = Vector2(968.0 + 255.0 * float(marker_index) / 4.0 - 1.0, 208.0)
		hp_marker.size = Vector2(2.0, 18.0)
		hp_marker.color = Color("#512832")
		hp_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(hp_marker)
		phase_markers.append(hp_marker)
	ui_labels["boss_phase_markers"] = phase_markers
	ui_labels["boss_hp"] = _label("500 / 500 ОЗ", Vector2(968, 232), Vector2(255, 22), 12, Color("#d8b9a8"))
	ui_labels["boss_phase"] = _label("ФАЗА I  •  100% ОСТАЛОСЬ", Vector2(968, 253), Vector2(255, 18), 10, Color("#d5a77a"))
	ui_labels["boss_threat"] = _label("УГРОЗА: НИЗКАЯ", Vector2(968, 273), Vector2(255, 18), 10, Color("#d5a77a"))
	ui_labels["boss_threat"].horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ui_labels["boss_hint"] = _label("Сокруши титана, чтобы получить\nосколок бога.", Vector2(968, 296), Vector2(255, 43), 12, Color("#aa8b87"))
	ui_labels["boss_reward"] = _label("НАГРАДА: +500 ЭНЕРГИИ", Vector2(968, 341), Vector2(255, 18), 10, Color("#f2c27b"))
	boost_button = _button("БОНУС x2  (ДЕМО)", Vector2(968, 365), Vector2(255, 52), true)
	boost_button.add_theme_font_size_override("font_size", 13)
	boost_button.pressed.connect(_activate_ad_demo)
	_label("ИМИТАЦИЯ БОНУСА — РЕКЛАМЫ ПОКА НЕТ", Vector2(968, 423), Vector2(255, 20), 9, Color("#8c777b"))
	_label("УЛУЧШЕНИЯ КУЗНИ", Vector2(32, 486), Vector2(300, 25), 16, Color("#e7c9a5"))
	var card_x := [32.0, 340.0, 648.0, 956.0]
	for i in range(4):
		_build_upgrade_card(i, Vector2(card_x[i], 520))
	_label("ЖМИ  •  СОБИРАЙ  •  ВОСХОДИ", Vector2(0, 690), Vector2(1280, 20), 10, Color("#77646b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


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

	var desc := _label(UPGRADE_DESC[index], pos + Vector2(16, 64), Vector2(258, 22), 11, Color("#bda39d"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_desc_%d" % index] = desc

	var level_label := _label("УРОВЕНЬ  00", pos + Vector2(16, 101), Vector2(92, 18), 11, Color("#e5c8a2"))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_level_%d" % index] = level_label

	var state_label := _label("ГОТОВО К КОВКЕ", pos + Vector2(104, 101), Vector2(172, 18), 9, Color("#f2bb70"))
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_state_%d" % index] = state_label

	var preview_label := _label("", pos + Vector2(16, 86), Vector2(258, 14), 10, Color("#c99b76"))
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_preview_%d" % index] = preview_label

	var cost_label := _label("✦  25 ЭНЕРГИИ", pos + Vector2(16, 122), Vector2(258, 22), 13, Color("#f3bd70"))
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_labels["upgrade_cost_%d" % index] = cost_label

	var progress_track := ColorRect.new()
	progress_track.position = pos + Vector2(16, 147)
	progress_track.size = Vector2(258, 4)
	progress_track.color = Color("#39232d")
	progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress_track)
	var progress_fill := ColorRect.new()
	progress_fill.position = progress_track.position
	progress_fill.size = Vector2(0, 4)
	progress_fill.color = Color("#e6a45d")
	progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress_fill)
	ui_labels["upgrade_progress_%d" % index] = progress_fill



func _achievement_data() -> Array[Dictionary]:
	var total_levels := 0
	for level in upgrade_levels:
		total_levels += int(level)
	return [
		{"name": "ПЕРВОЕ ПЛАМЯ", "desc": "Нанеси первый удар по ядру", "value": total_clicks, "target": 1},
		{"name": "СОТНЯ УДАРОВ", "desc": "Нанеси 100 ударов по ядру", "value": total_clicks, "target": 100},
		{"name": "ТЫСЯЧА УДАРОВ", "desc": "Нанеси 1 000 ударов по ядру", "value": total_clicks, "target": 1000},
		{"name": "КУЗНЕЦ", "desc": "Купи 10 улучшений кузни", "value": total_upgrades, "target": 10},
		{"name": "МАСТЕР КОВКИ", "desc": "Купи 50 улучшений кузни", "value": total_upgrades, "target": 50},
		{"name": "ДВИГАТЕЛЬ ДУШ", "desc": "Прокачай двигатель душ до уровня 10", "value": int(upgrade_levels[1]), "target": 10},
		{"name": "ПЕРВЫЙ СТРАЖ", "desc": "Победи первого стража мира", "value": maxi(boss_stage - 1, 0), "target": 1},
		{"name": "РАЗРУШИТЕЛЬ МИРОВ", "desc": "Доберись до мира 10", "value": boss_stage, "target": 10},
		{"name": "УБИЙЦА БОГОВ", "desc": "Доберись до мира 25", "value": boss_stage, "target": 25}
	]


func _unlocked_achievement_count() -> int:
	var unlocked := 0
	for achievement in _achievement_data():
		if int(achievement["value"]) >= int(achievement["target"]):
			unlocked += 1
	return unlocked


func _check_achievements() -> void:
	for achievement in _achievement_data():
		var achievement_name := str(achievement["name"])
		if int(achievement["value"]) >= int(achievement["target"]) and not claimed_achievements.has(achievement_name):
			claimed_achievements.append(achievement_name)
			achievement_popup_queue.append("ДОСТИЖЕНИЕ ОТКРЫТО  •  " + achievement_name)
	if journal_button != null and is_instance_valid(journal_button):
		journal_button.text = "ЛЕТОПИСЬ  %d/9" % _unlocked_achievement_count()


func _open_journal() -> void:
	if journal_overlay != null and is_instance_valid(journal_overlay):
		return
	journal_overlay = Control.new()
	journal_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	journal_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	journal_overlay.z_index = 100
	add_child(journal_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.008, 0.02, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	journal_overlay.add_child(dim)

	var frame := Panel.new()
	frame.position = Vector2(315, 54)
	frame.size = Vector2(650, 612)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("#100b13")
	frame_style.border_color = Color("#b87949")
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(14)
	frame_style.shadow_color = Color(0, 0, 0, 0.7)
	frame_style.shadow_size = 20
	frame.add_theme_stylebox_override("panel", frame_style)
	journal_overlay.add_child(frame)

	var title := Label.new()
	title.position = Vector2(342, 70)
	title.size = Vector2(480, 40)
	title.text = "ЛЕТОПИСЬ КУЗНИ"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("#f2d6ac"))
	journal_overlay.add_child(title)

	var summary := Label.new()
	summary.position = Vector2(344, 108)
	summary.size = Vector2(500, 28)
	summary.text = "ОТКРЫТО: %d ИЗ 9  •  УДАРОВ: %s  •  УЛУЧШЕНИЙ: %s" % [_unlocked_achievement_count(), _format_number(total_clicks), _format_number(total_upgrades)]
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", Color("#c49b80"))
	journal_overlay.add_child(summary)

	var close := Button.new()
	close.position = Vector2(880, 66)
	close.size = Vector2(58, 42)
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.add_theme_color_override("font_color", Color("#f2d6ac"))
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color("#321b20")
	close_style.border_color = Color("#9d5b42")
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(8)
	close.add_theme_stylebox_override("normal", close_style)
	close.add_theme_stylebox_override("hover", close_style)
	close.pressed.connect(_close_journal)
	journal_overlay.add_child(close)

	var achievements := _achievement_data()
	for i in range(achievements.size()):
		var achievement: Dictionary = achievements[i]
		var unlocked := int(achievement["value"]) >= int(achievement["target"])
		var row := Panel.new()
		row.position = Vector2(337, 151 + i * 54)
		row.size = Vector2(606, 47)
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color("#21151b") if unlocked else Color("#151019")
		row_style.border_color = Color("#d58b4c") if unlocked else Color("#49313a")
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(7)
		row.add_theme_stylebox_override("panel", row_style)
		journal_overlay.add_child(row)

		var name_label := Label.new()
		name_label.position = Vector2(350, 153 + i * 54)
		name_label.size = Vector2(360, 21)
		name_label.text = ("✦  " if unlocked else "◇  ") + str(achievement["name"])
		name_label.add_theme_font_size_override("font_size", 13)
		name_label.add_theme_color_override("font_color", Color("#f2c27b") if unlocked else Color("#a58b91"))
		journal_overlay.add_child(name_label)

		var desc_label := Label.new()
		desc_label.position = Vector2(351, 175 + i * 54)
		desc_label.size = Vector2(430, 18)
		desc_label.text = str(achievement["desc"])
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", Color("#bca29c"))
		journal_overlay.add_child(desc_label)

		var progress_label := Label.new()
		progress_label.position = Vector2(785, 162 + i * 54)
		progress_label.size = Vector2(143, 24)
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		progress_label.text = "ОТКРЫТО" if unlocked else "%s / %s" % [_format_number(mini(int(achievement["value"]), int(achievement["target"]))), _format_number(int(achievement["target"]))]
		progress_label.add_theme_font_size_override("font_size", 11)
		progress_label.add_theme_color_override("font_color", Color("#f2c27b") if unlocked else Color("#927982"))
		journal_overlay.add_child(progress_label)


func _open_victory_summary() -> void:
	if victory_summary != null and is_instance_valid(victory_summary):
		return
	victory_summary = Control.new()
	victory_summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	victory_summary.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_summary.z_index = 110
	add_child(victory_summary)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.015, 0.008, 0.02, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	victory_summary.add_child(dim)

	var frame := Panel.new()
	frame.position = Vector2(280, 55)
	frame.size = Vector2(720, 610)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#100b13")
	style.border_color = Color("#b87949")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	frame.add_theme_stylebox_override("panel", style)
	victory_summary.add_child(frame)

	_add_summary_label("ХРОНИКИ ПОБЕД", Vector2(315, 73), Vector2(500, 38), 26, Color("#f2d6ac"))
	_add_summary_label("ПОБЕДЫ: %d  •  МИР: %02d  •  ВСЕГО УДАРОВ: %s" % [boss_victories, boss_stage, _format_number(total_clicks)], Vector2(318, 116), Vector2(640, 26), 13, Color("#d4a77f"))
	var elapsed_total: int = total_play_seconds + maxi(int(Time.get_unix_time_from_system()) - session_started_at, 0)
	var hours: int = elapsed_total / 3600
	var minutes: int = (elapsed_total % 3600) / 60
	_add_summary_label("ВРЕМЯ В КУЗНЕ: %02d ч %02d мин  •  ВСЕГО ЗАРАБОТАНО: %s" % [hours, minutes, _format_number(lifetime_energy_earned)], Vector2(318, 145), Vector2(640, 24), 11, Color("#b89a9c"))
	_add_summary_label("ПОСЛЕДНИЕ ПОБЕДЫ", Vector2(318, 185), Vector2(500, 25), 15, Color("#e8c18b"))

	var history_scroll := ScrollContainer.new()
	history_scroll.position = Vector2(315, 215)
	history_scroll.size = Vector2(650, 350)
	history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	victory_summary.add_child(history_scroll)
	var history_list := VBoxContainer.new()
	history_list.custom_minimum_size = Vector2(620, 0)
	history_list.add_theme_constant_override("separation", 7)
	history_scroll.add_child(history_list)
	if boss_history.is_empty():
		var empty := Label.new()
		empty.text = "Победы появятся здесь после первого поверженного стража."
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", Color("#a58b91"))
		history_list.add_child(empty)
	else:
		for i in range(boss_history.size() - 1, -1, -1):
			var entry: Dictionary = boss_history[i]
			var row := Panel.new()
			row.custom_minimum_size = Vector2(610, 50)
			var row_style := StyleBoxFlat.new()
			row_style.bg_color = Color("#21151b")
			row_style.border_color = Color("#69402f")
			row_style.set_border_width_all(1)
			row_style.set_corner_radius_all(7)
			row.add_theme_stylebox_override("panel", row_style)
			history_list.add_child(row)
			var label := Label.new()
			label.position = Vector2(12, 3)
			label.size = Vector2(585, 42)
			var won_at: int = int(entry.get("timestamp", 0))
			var date_text := Time.get_datetime_string_from_unix_time(won_at, true) if won_at > 0 else "ВРЕМЯ НЕИЗВЕСТНО"
			label.text = "МИР %02d  •  %s  •  УДАРОВ: %s\nНАГРАДА: %s ЭНЕРГИИ  •  %s" % [int(entry.get("stage", 0)), str(entry.get("name", "СТРАЖ")), _format_number(float(entry.get("hits", 0))), _format_number(float(entry.get("reward", 0.0))), date_text]
			label.add_theme_font_size_override("font_size", 12)
			label.add_theme_color_override("font_color", Color("#f2d6ac"))
			row.add_child(label)

	var close := Button.new()
	close.position = Vector2(850, 595)
	close.size = Vector2(105, 42)
	close.text = "ЗАКРЫТЬ"
	close.focus_mode = Control.FOCUS_NONE
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color("#321b20")
	close_style.border_color = Color("#9d5b42")
	close_style.set_border_width_all(1)
	close_style.set_corner_radius_all(8)
	close.add_theme_stylebox_override("normal", close_style)
	close.add_theme_stylebox_override("hover", close_style)
	close.pressed.connect(_close_victory_summary)
	victory_summary.add_child(close)


func _add_summary_label(value: String, pos: Vector2, size: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	victory_summary.add_child(label)


func _close_victory_summary() -> void:
	if victory_summary != null and is_instance_valid(victory_summary):
		victory_summary.queue_free()
	victory_summary = null


func _close_journal() -> void:
	if journal_overlay != null and is_instance_valid(journal_overlay):
		journal_overlay.queue_free()
	journal_overlay = null

func _strike_core() -> void:
	total_clicks += 1
	combo_count += 1
	combo_time = 1.5
	if ui_labels.has("combo"):
		ui_labels["combo"].text = "СЕРИЯ УДАРОВ  ×%d" % combo_count if combo_count > 1 else "ПЕРВЫЙ УДАР СЕРИИ"
		var combo_color := Color("#e5bd7e")
		if combo_count >= 100:
			combo_color = Color("#fff0a3")
		elif combo_count >= 50:
			combo_color = Color("#ffb56b")
		elif combo_count >= 25:
			combo_color = Color("#f2c27b")
		elif combo_count >= 10:
			combo_color = Color("#ffe6a0")
		ui_labels["combo"].add_theme_color_override("font_color", combo_color)
		ui_labels["combo"].scale = Vector2.ONE
		var combo_tween := create_tween()
		combo_tween.tween_property(ui_labels["combo"], "scale", Vector2(1.12, 1.12), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		combo_tween.tween_property(ui_labels["combo"], "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_check_achievements()
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
	lifetime_energy_earned += damage
	energy_flash = 1.0
	var boss_hit_damage := damage * boss_damage
	var previous_hp_ratio: float = clampf(boss_hp / maxf(boss_max_hp, 1.0), 0.0, 1.0)
	boss_hp -= boss_hit_damage
	var current_hp_ratio: float = clampf(boss_hp / maxf(boss_max_hp, 1.0), 0.0, 1.0)
	var previous_phase: int = 1 if previous_hp_ratio > 0.75 else (2 if previous_hp_ratio > 0.5 else (3 if previous_hp_ratio > 0.25 else 4))
	var current_phase: int = 1 if current_hp_ratio > 0.75 else (2 if current_hp_ratio > 0.5 else (3 if current_hp_ratio > 0.25 else 4))
	if current_phase > previous_phase and boss_hp > 0.0:
		combat_popups.append({"text": "ФАЗА %s  •  СТРАЖ ОСЛАБЛЕН" % _roman_phase(current_phase), "position": Vector2(862.0, 254.0), "life": 1.2, "size": 15, "color": Color("#ffbd76")})
		boss_transition_flash = maxf(boss_transition_flash, 0.28)
	boss_hit_flash = 1.0
	boss_shake = 1.0
	boss_slash_flash = 1.0
	boss_slash_angle = rng.randf_range(-PI, PI)
	boss_slash_critical = critical
	combat_popups.append({"text": ("КРИТ!  −" if critical else "−") + _format_number(boss_hit_damage), "position": Vector2(862.0 + rng.randf_range(-24.0, 24.0), 286.0), "life": 1.0, "size": 23 if critical else 18, "color": Color("#ffe28b") if critical else Color("#ff8c72")})
	combat_popups.append({"text": "+" + _format_number(damage) + " ЭНЕРГИИ", "position": Vector2(640.0 + rng.randf_range(-20.0, 20.0), 284.0), "life": 0.82, "size": 15, "color": Color("#ffc879")})
	if combo_count in [10, 25, 50, 100, 250, 500, 1000]:
		var combo_title := "СЕРИЯ  %d УДАРОВ!" % combo_count
		var combo_tier_color := Color("#ffe6a0") if combo_count < 50 else (Color("#ffb56b") if combo_count < 250 else Color("#ff795f"))
		var combo_popup_size := 20 if combo_count < 100 else (23 if combo_count < 500 else 27)
		combat_popups.append({"text": combo_title, "position": Vector2(640.0, 250.0), "life": 1.35, "size": combo_popup_size, "color": combo_tier_color})
		if ui_labels.has("combo"):
			var milestone_tween := create_tween()
			milestone_tween.tween_property(ui_labels["combo"], "scale", Vector2(1.22, 1.22), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			milestone_tween.tween_property(ui_labels["combo"], "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		critical_flash = maxf(critical_flash, 0.35 if combo_count < 100 else 0.5)
		for particle_index in range(18 if combo_count < 100 else 32):
			var burst_angle := rng.randf_range(0.0, TAU)
			var burst_speed := rng.randf_range(90.0, 260.0)
			var burst_origin := Vector2(640.0, 345.0) + Vector2(cos(burst_angle), sin(burst_angle)) * rng.randf_range(35.0, 58.0)
			ember_particles.append(Vector4(burst_origin.x, burst_origin.y, cos(burst_angle) * burst_speed, sin(burst_angle) * burst_speed))
	if ui_labels.has("hit"):
		ui_labels["hit"].text = ("КРИТИЧЕСКИЙ УДАР!  +" if critical else "УДАР ПО ЯДРУ  +") + _format_number(damage)
		ui_labels["hit"].add_theme_color_override("font_color", Color("#fff0a3") if critical else Color("#d58b4c"))
	if boss_hp <= 0.0:
		boss_victories += 1
		boss_history.append({"stage": boss_stage, "name": _boss_name(boss_stage), "reward": 250.0 * (boss_stage + 1), "hits": total_clicks - boss_stage_start_clicks, "timestamp": int(Time.get_unix_time_from_system())})
		if boss_history.size() > 50:
			boss_history.pop_front()
		boss_stage_start_clicks = total_clicks
		boss_stage += 1
		_check_achievements()
		last_boss_reward = 250.0 * boss_stage
		energy += last_boss_reward
		lifetime_energy_earned += last_boss_reward
		energy_flash = 1.0
		victory_banner_time = 2.2
		victory_banner_text = "СТРАЖ СОКРУШЁН  •  +%s ЭНЕРГИИ" % _format_number(last_boss_reward)
		boss_max_hp *= 1.72
		boss_hp = boss_max_hp
		multiplier *= 1.08
		boss_transition_flash = 1.0
		critical_flash = 0.0
		boss_hit_flash = 0.0
		boss_shake = 0.0
		boss_slash_flash = 0.0
		combat_popups.append({"text": "СТРАЖ СОКРУШЁН", "position": Vector2(862.0, 230.0), "life": 1.35, "size": 20, "color": Color("#ffe6a0")})
		combat_popups.append({"text": "+%s ЭНЕРГИИ" % _format_number(last_boss_reward), "position": Vector2(640.0, 200.0), "life": 1.7, "size": 17, "color": Color("#f5c16e")})
		if ui_labels.has("boss_hint"):
			ui_labels["boss_hint"].text = "СТРАЖ ПОВЕРЖЕН!\n+1 ОСКОЛОК БОГА  •  СИЛА +8%"
	_refresh_ui()

func _buy_upgrade(index: int) -> void:
	var cost := _upgrade_cost(index)
	if energy < cost:
		if ui_labels.has("power"):
			ui_labels["power"].text = "НЕДОСТАТОЧНО ЭНЕРГИИ"
		return
	energy -= cost
	energy_flash = 0.65
	total_upgrades += 1
	upgrade_levels[index] += 1
	_check_achievements()
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
	lifetime_energy_earned += 50.0 * multiplier
	if boost_button != null:
		boost_button.text = "БОНУС x2  60 с"
	_refresh_ui()

func _refresh_ui() -> void:
	if not playing:
		return
	if journal_button != null and is_instance_valid(journal_button):
		journal_button.text = "ЛЕТОПИСЬ  %d/9" % _unlocked_achievement_count()
	if ui_labels.has("energy"):
		ui_labels["energy"].text = "ЭНЕРГИЯ  " + _format_number(energy)
		ui_labels["energy"].add_theme_color_override("font_color", Color("#fff0a3").lerp(Color("#f5c16e"), 1.0 - energy_flash))
		ui_labels["lifetime"].text = "ВСЕГО ПОЛУЧЕНО  " + _format_number(lifetime_energy_earned)
		ui_labels["clicks"].text = "УДАРОВ ПО ЯДРУ  " + _format_number(total_clicks)
		var milestone_targets: Array[int] = [5, 10, 25, 50, 100]
		var milestone_target: int = 125
		var milestone_start: int = 100
		for target in milestone_targets:
			if boss_stage < target:
				milestone_target = target
				break
			milestone_start = target
		if boss_stage >= 100:
			milestone_start = boss_stage - posmod(boss_stage, 25)
			milestone_target = milestone_start + 25
		var milestone_ratio: float = clampf(float(boss_stage - milestone_start) / maxf(float(milestone_target - milestone_start), 1.0), 0.0, 1.0)
		ui_labels["milestone"].text = "РУБЕЖ МИРА %02d  •  %d%%" % [milestone_target, int(round(milestone_ratio * 100.0))]
		var milestone_fill: ColorRect = ui_labels["milestone_fill"]
		milestone_fill.size = Vector2(210.0 * milestone_ratio, 5.0)
		ui_labels["rate"].text = _format_number(idle_rate * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)) + " / СЕК"
		ui_labels["stage"].text = "МИР  %02d" % boss_stage
		ui_labels["shards"].text = "ОСКОЛКИ БОГА  %d" % (boss_stage - 1)
		ui_labels["power"].text = "СИЛА УДАРА\n" + _format_number(click_power * multiplier)
		ui_labels["crit"].text = "ШАНС КРИТА\n8%  •  УРОН x5"
		ui_labels["dps"].text = "ДОХОД В ПРОСТОЕ\n" + _format_number(idle_rate * multiplier) + " / сек"
		ui_labels["boss"].text = _boss_name(boss_stage) + "  •  %02d" % boss_stage
		ui_labels["boss_reward"].text = "НАГРАДА: +%s ЭНЕРГИИ" % _format_number(250.0 * float(boss_stage + 1))
		ui_labels["boss_hp"].text = _format_number(maxf(0.0, boss_hp)) + " / " + _format_number(boss_max_hp) + " ОЗ"
		var hp_ratio: float = clampf(boss_hp / maxf(boss_max_hp, 1.0), 0.0, 1.0)
		var phase_label: Label = ui_labels["boss_phase"]
		var phase_number := 1 if hp_ratio > 0.75 else (2 if hp_ratio > 0.5 else (3 if hp_ratio > 0.25 else 4))
		var phase_start := 1.0 - float(phase_number) * 0.25
		var phase_end := 1.0 - float(phase_number - 1) * 0.25
		var phase_progress := clampf((hp_ratio - phase_start) / maxf(phase_end - phase_start, 0.001), 0.0, 1.0)
		phase_label.text = "ФАЗА %s  •  %d%% ДО СМЕНЫ" % [_roman_phase(phase_number), int(round(phase_progress * 100.0))]
		phase_label.add_theme_color_override("font_color", Color("#ff715c") if phase_number >= 4 else (Color("#e6a45d") if phase_number >= 3 else Color("#d5a77a")))
		var phase_markers: Array = ui_labels["boss_phase_markers"]
		for marker_index in range(phase_markers.size()):
			var marker: ColorRect = phase_markers[marker_index]
			var threshold := 0.75 - float(marker_index) * 0.25
			var marker_crossed := hp_ratio <= threshold
			var marker_active := absf(hp_ratio - threshold) <= 0.035
			marker.color = Color("#ff795f") if marker_active else (Color("#e6a45d") if marker_crossed else Color("#512832"))
			marker.size.x = 3.0 if marker_active else 2.0
		var threat_label: Label = ui_labels["boss_threat"]
		if hp_ratio <= 0.2:
			threat_label.text = "УГРОЗА: КРИТИЧЕСКАЯ"
			threat_label.add_theme_color_override("font_color", Color("#ff715c"))
		elif hp_ratio <= 0.5:
			threat_label.text = "УГРОЗА: ПОВЫШЕННАЯ"
			threat_label.add_theme_color_override("font_color", Color("#e6a45d"))
		else:
			threat_label.text = "УГРОЗА: НИЗКАЯ"
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
		var preview_label: Label = ui_labels["upgrade_preview_%d" % i]
		var progress_fill: ColorRect = ui_labels["upgrade_progress_%d" % i]
		var level_label: Label = ui_labels["upgrade_level_%d" % i]
		var accent: ColorRect = ui_labels["upgrade_accent_%d" % i]
		card.disabled = not can_afford
		card.modulate = Color.WHITE
		level_label.text = "УРОВЕНЬ  %02d" % level
		cost_label.text = "✦  %s ЭНЕРГИИ" % _format_number(cost)
		preview_label.text = _upgrade_next_effect(i)
		var affordability_ratio := clampf(energy / maxf(cost, 1.0), 0.0, 1.0)
		progress_fill.size = Vector2(258.0 * affordability_ratio, 4.0)
		progress_fill.color = Color("#f2bb70") if can_afford else (Color("#98513b") if affordability_ratio >= 0.5 else Color("#513541"))
		if upgrade_feedback_time[i] > 0.0:
			state_label.text = "УЛУЧШЕНО!  +1 УРОВЕНЬ"
			state_label.add_theme_color_override("font_color", Color("#ffe6a0"))
		elif can_afford and level == 0:
			state_label.text = "ГОТОВО К КОВКЕ"
			state_label.add_theme_color_override("font_color", Color("#f2bb70"))
		elif can_afford:
			state_label.text = "МОЖНО УЛУЧШИТЬ"
			state_label.add_theme_color_override("font_color", Color("#e5b56f"))
		elif level > 0:
			state_label.text = "НЕ ХВАТАЕТ  %s" % _format_number(maxf(cost - energy, 0.0))
			state_label.add_theme_color_override("font_color", Color("#c08b83"))
		else:
			state_label.text = "НУЖНО ЕЩЁ  %s" % _format_number(maxf(cost - energy, 0.0))
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

func _roman_phase(phase_number: int) -> String:
	match phase_number:
		1:
			return "I"
		2:
			return "II"
		3:
			return "III"
		4:
			return "IV"
	return "I"

func _upgrade_next_effect(index: int) -> String:
	match index:
		0:
			return "СИЛА: %s → %s" % [_format_number(click_power * multiplier), _format_number(click_power * 1.55 * multiplier)]
		1:
			var current_idle := idle_rate * multiplier
			var next_idle := (idle_rate + pow(1.32, upgrade_levels[index])) * multiplier
			return "ДОХОД: %s → %s / сек" % [_format_number(current_idle), _format_number(next_idle)]
		2:
			return "ВСЁ ПРОИЗВОДСТВО: ×%.2f → ×%.2f" % [multiplier, multiplier * 1.18]
		3:
			return "УРОН БОССУ: ×%.2f → ×%.2f" % [boss_damage, boss_damage * 1.45]
	return ""

func _format_number(value: float) -> String:
	if value >= 1.0e12:
		return "%.2f трлн" % (value / 1.0e12)
	if value >= 1.0e9:
		return "%.2f млрд" % (value / 1.0e9)
	if value >= 1.0e6:
		return "%.2f млн" % (value / 1.0e6)
	if value >= 1.0e3:
		return "%.2f тыс." % (value / 1.0e3)
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
	victory_summary = null
	journal_button = null
	journal_overlay = null

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
	cfg.set_value("progress", "total_clicks", total_clicks)
	cfg.set_value("progress", "total_upgrades", total_upgrades)
	cfg.set_value("progress", "boss_victories", boss_victories)
	cfg.set_value("progress", "claimed_achievements", claimed_achievements)
	cfg.set_value("progress", "boss_history", boss_history)
	cfg.set_value("progress", "lifetime_energy_earned", lifetime_energy_earned)
	cfg.set_value("progress", "total_play_seconds", total_play_seconds + maxi(int(Time.get_unix_time_from_system()) - session_started_at, 0))
	cfg.set_value("progress", "boss_stage_start_clicks", boss_stage_start_clicks)
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
	total_clicks = int(cfg.get_value("progress", "total_clicks", 0))
	total_upgrades = int(cfg.get_value("progress", "total_upgrades", 0))
	boss_victories = int(cfg.get_value("progress", "boss_victories", maxi(boss_stage - 1, 0)))
	claimed_achievements = cfg.get_value("progress", "claimed_achievements", [])
	boss_history = cfg.get_value("progress", "boss_history", [])
	lifetime_energy_earned = float(cfg.get_value("progress", "lifetime_energy_earned", energy))
	total_play_seconds = int(cfg.get_value("progress", "total_play_seconds", 0))
	boss_stage_start_clicks = int(cfg.get_value("progress", "boss_stage_start_clicks", total_clicks))
	var last_time := int(cfg.get_value("progress", "last_time", int(Time.get_unix_time_from_system())))
	var elapsed := clampf(float(Time.get_unix_time_from_system() - last_time), 0.0, 28800.0)
	var offline_gain: float = idle_rate * multiplier * elapsed * 0.5
	energy += offline_gain
	lifetime_energy_earned += offline_gain

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()
