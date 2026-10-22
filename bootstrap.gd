## bootstrap.gd — bulletproof loader, guarantees NO gray screen ever
## Uses dynamic load() only — no preload(), no typed class references.
## If any module fails, shows bright red error screen with exact file name.
extends Node2D

var _lines:    Array  = []
var _err:      String = ""
var _progress: int    = 0
var _done:     bool   = false

const MODULES := [
	"res://scripts/config/balance.gd",
	"res://scripts/core/combat_manager.gd",
	"res://scripts/core/enemy_spawner.gd",
	"res://scripts/core/round_manager.gd",
	"res://scripts/core/loot_manager.gd",
	"res://scripts/rendering/world_renderer.gd",
	"res://scripts/rendering/fx_manager.gd",
	"res://scripts/ui/hud.gd",
	"res://scripts/game_manager.gd",
]


func _ready() -> void:
	_lines.append("SuperShooterHybrid v2.0")
	_lines.append("Verifying modules...")
	queue_redraw()
	call_deferred("_boot")


func _boot() -> void:
	for path in MODULES:
		var s = load(path)
		if s == null:
			_err = path
			queue_redraw()
			return
		_progress += 1
		_lines.append("  + " + (path as String).get_file().get_basename())
		queue_redraw()

	_lines.append("All OK — launching!")
	queue_redraw()
	call_deferred("_launch")


func _launch() -> void:
	var gm_script = load("res://scripts/game_manager.gd")
	if gm_script == null:
		_err = "res://scripts/game_manager.gd (instantiation)"
		queue_redraw()
		return

	var gm = gm_script.new()
	if gm == null:
		_err = "GameManager.new() returned null"
		queue_redraw()
		return

	var parent = get_parent()
	if parent:
		parent.add_child(gm)
	else:
		add_child(gm)

	_done = true
	queue_free()


func _draw() -> void:
	if _done:
		return

	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font

	if _err != "":
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.18, 0.02, 0.02))
		draw_string(font, Vector2(40, 130), "STARTUP ERROR", HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1.0, 0.15, 0.15))
		draw_string(font, Vector2(40, 210), "Failed to load:", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.9, 0.9, 0.9))

		# Show short filename big + full path small
		var short_name: String = (_err as String).get_file()
		draw_string(font, Vector2(40, 270), short_name, HORIZONTAL_ALIGNMENT_LEFT, int(vp.x - 80), 34, Color(1.0, 0.8, 0.2))
		draw_string(font, Vector2(40, 320), _err, HORIZONTAL_ALIGNMENT_LEFT, int(vp.x - 80), 20, Color(0.65, 0.65, 0.65))
		draw_string(font, Vector2(40, 380), "Check GDScript syntax — open Godot editor for details", HORIZONTAL_ALIGNMENT_LEFT, int(vp.x - 80), 22, Color(0.7, 0.9, 0.7))

		# Show successful loads above the error
		var y2 := 450.0
		draw_string(font, Vector2(40, y2), "Modules that loaded OK:", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.5, 0.8, 0.5))
		y2 += 28.0
		for i in range(1, _lines.size()):
			draw_string(font, Vector2(60, y2), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.7, 0.5))
			y2 += 26.0
		return

	# Normal loading screen
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.04, 0.07, 0.04))

	# Title
	draw_string(font, Vector2(40, 90), "SuperShooterHybrid", HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.3, 1.0, 0.4))
	draw_string(font, Vector2(40, 135), "v2.0", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.4, 0.6, 0.4))

	# Progress bar
	var bar_y := 170.0
	var bar_w := vp.x - 80.0
	draw_rect(Rect2(40, bar_y, bar_w, 10), Color(0.1, 0.18, 0.1))
	var fill := bar_w * (float(_progress) / float(maxi(MODULES.size(), 1)))
	draw_rect(Rect2(40, bar_y, fill, 10), Color(0.25, 0.9, 0.3))

	# Log lines
	var y := 200.0
	for i in range(_lines.size()):
		var alpha := 1.0 if i >= _lines.size() - 2 else 0.55
		draw_string(font, Vector2(40, y), _lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
			Color(1.0, 1.0, 1.0, alpha))
		y += 30.0
