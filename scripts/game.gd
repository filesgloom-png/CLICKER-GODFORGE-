extends Control

const SAVE_PATH := "user://godforge_save.cfg"
const UPGRADE_NAMES := ["FORGE HAMMER", "SOUL ENGINE", "RUNE OF RUIN", "GODSLAYER EDGE"]
const UPGRADE_DESC := ["More power per strike", "Earn energy while idle", "Increase all production", "Deal more damage to bosses"]
const UPGRADE_BASE_COST := [25.0, 80.0, 180.0, 320.0]

var rng := RandomNumberGenerator.new()
var stars: Array[Vector3] = []
var pulse := 0.0
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
	idle_clock += delta
	autosave_clock += delta
	if idle_clock >= 1.0:
		idle_clock = 0.0
		if playing and idle_rate > 0.0:
			energy += idle_rate * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color("#08070d"))
	for y in range(0, int(size.y), 4):
		var shade := 0.015 + 0.012 * float(y) / maxf(size.y, 1.0)
		draw_rect(Rect2(0, y, size.x, 4), Color(0.12, 0.055, 0.07, shade))
	for star in stars:
		var p := Vector2(star.x * size.x, star.y * size.y)
		var twinkle := 0.25 + 0.35 * absf(sin(pulse * star.z + star.x * 20.0))
		draw_circle(p, 0.7 + star.z * 1.2, Color(1.0, 0.68, 0.36, twinkle))
	var center := Vector2(size.x * 0.5, size.y * 0.48)
	var core_size := 1.0 + 0.035 * sin(pulse * 2.2)
	for i in range(8, 0, -1):
		draw_circle(center, (42.0 + i * 10.0) * core_size, Color(0.9, 0.23, 0.08, 0.018 + float(8 - i) * 0.003))
	draw_arc(center, 114.0 * core_size, pulse * 0.15, pulse * 0.15 + TAU * 0.78, 96, Color("#a84b29"), 2.0, true)
	draw_arc(center, 137.0, -pulse * 0.11, -pulse * 0.11 + TAU * 0.66, 96, Color(0.95, 0.62, 0.24, 0.42), 1.5, true)
	for i in range(12):
		var a := TAU * float(i) / 12.0 + pulse * 0.12
		var inner := center + Vector2(cos(a), sin(a)) * 121.0
		var outer := center + Vector2(cos(a), sin(a)) * (132.0 + 3.0 * sin(pulse * 2.0 + a))
		draw_line(inner, outer, Color("#d58b4c"), 2.0, true)
	draw_circle(center, 56.0 * core_size, Color(0.95, 0.23, 0.07, 0.18))
	draw_circle(center, 37.0 * core_size, Color("#35151b"))
	draw_circle(center, 27.0 * core_size, Color("#9d321e"))
	draw_circle(center, 17.0 * core_size, Color("#f4a64e"))
	draw_circle(center, 8.0 * core_size, Color("#fff0bf"))
	for i in range(9):
		var a := TAU * float(i) / 9.0 - pulse * 0.3
		var p := center + Vector2(cos(a), sin(a)) * (72.0 + 9.0 * sin(pulse + a))
		draw_circle(p, 2.0, Color(1.0, 0.55, 0.2, 0.8))
	draw_line(Vector2(0, 88), Vector2(size.x, 88), Color(0.75, 0.34, 0.19, 0.26), 1.0)
	draw_line(Vector2(0, size.y - 132), Vector2(size.x, size.y - 132), Color(0.75, 0.34, 0.19, 0.24), 1.0)

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
	core_button = _button("STRIKE THE CORE", Vector2(440, 215), Vector2(400, 200), false)
	core_button.add_theme_font_size_override("font_size", 23)
	core_button.pressed.connect(_strike_core)
	_panel(Vector2(945, 118), Vector2(305, 340))
	_label("GATEKEEPER", Vector2(968, 136), Vector2(250, 24), 15, Color("#dfb89e"))
	ui_labels["boss"] = _label("THE HOLLOW TITAN", Vector2(968, 168), Vector2(250, 24), 13, Color("#f0d9c2"))
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
	ui_labels["boss_hp"] = _label("500 / 500 HP", Vector2(968, 232), Vector2(255, 22), 12, Color("#d8b9a8"))
	ui_labels["boss_hint"] = _label("Break the Titan to claim\na Godshard.", Vector2(968, 277), Vector2(255, 48), 13, Color("#aa8b87"))
	boost_button = _button("REWARDED AD x2  (DEMO)", Vector2(968, 365), Vector2(255, 52), true)
	boost_button.add_theme_font_size_override("font_size", 13)
	boost_button.pressed.connect(_activate_ad_demo)
	_label("BONUS SIMULATION — NO AD SDK YET", Vector2(968, 423), Vector2(255, 20), 9, Color("#8c777b"))
	_label("FORGE UPGRADES", Vector2(32, 486), Vector2(300, 25), 16, Color("#e7c9a5"))
	var card_x := [32.0, 340.0, 648.0, 956.0]
	for i in range(4):
		var index := i
		var card := _button("", Vector2(card_x[i], 520), Vector2(290, 154), false)
		card.add_theme_font_size_override("font_size", 14)
		card.pressed.connect(func(): _buy_upgrade(index))
		ui_labels["upgrade_%d" % i] = card
	_label("CLICK  •  COLLECT  •  ASCEND", Vector2(0, 690), Vector2(1280, 20), 10, Color("#77646b")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _strike_core() -> void:
	var damage := click_power * multiplier * (2.0 if ad_boost_time > 0.0 else 1.0)
	var critical := rng.randf() < 0.08
	if critical:
		damage *= 5.0
	energy += damage
	boss_hp -= damage * boss_damage
	if core_button != null:
		core_button.text = "CRITICAL STRIKE!" if critical else "STRIKE THE CORE"
	if boss_hp <= 0.0:
		boss_stage += 1
		energy += 250.0 * boss_stage
		boss_max_hp *= 1.72
		boss_hp = boss_max_hp
		multiplier *= 1.08
		if ui_labels.has("boss_hint"):
			ui_labels["boss_hint"].text = "TITAN DEFEATED!\n+1 GODSHARD  •  POWER +8%"
	_refresh_ui()

func _buy_upgrade(index: int) -> void:
	var cost := _upgrade_cost(index)
	if energy < cost:
		if ui_labels.has("power"):
			ui_labels["power"].text = "NOT ENOUGH ENERGY"
		return
	energy -= cost
	upgrade_levels[index] += 1
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
		ui_labels["boss"].text = "THE HOLLOW TITAN  •  %02d" % boss_stage
		ui_labels["boss_hp"].text = _format_number(maxf(0.0, boss_hp)) + " / " + _format_number(boss_max_hp) + " HP"
	if boss_bar != null and is_instance_valid(boss_bar):
		boss_bar.max_value = boss_max_hp
		boss_bar.value = maxf(0.0, boss_hp)
	for i in range(4):
		var key := "upgrade_%d" % i
		if ui_labels.has(key):
			var card: Button = ui_labels[key]
			card.text = "%s  •  LV %d\n%s\nCOST  %s" % [UPGRADE_NAMES[i], upgrade_levels[i], UPGRADE_DESC[i], _format_number(_upgrade_cost(i))]
			card.disabled = energy < _upgrade_cost(i)
			card.modulate = Color(1, 1, 1, 1) if not card.disabled else Color(0.65, 0.58, 0.58, 1)

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
	style.bg_color = Color(0.055, 0.035, 0.055, 0.92)
	style.border_color = Color(0.53, 0.25, 0.16, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(0, 0, 0, 0.3)
	style.shadow_size = 8
	panel.add_theme_stylebox_override("panel", style)
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
	normal.bg_color = Color("#4c281f") if gold else Color(0.07, 0.045, 0.065, 0.96)
	normal.border_color = Color("#d58b4c") if gold else Color("#75412f")
	normal.set_border_width_all(2 if gold else 1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#6b3825") if gold else Color("#281721")
	hover.border_color = Color("#ffd080")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#26131a")
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
