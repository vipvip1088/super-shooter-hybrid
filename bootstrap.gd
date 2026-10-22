## bootstrap.gd — bulletproof loader for 3D modules.
## Uses dynamic load() only — no preload(), no typed class refs.
## CanvasLayer always renders debug UI — no gray screen ever.
extends Node3D

const MODULES := [
	"res://scripts/config/balance.gd",
	"res://scripts/core/save_manager.gd",
	"res://scripts/world/world_generator_3d.gd",
	"res://scripts/player/player_controller_3d.gd",
	"res://scripts/player/weapon_system_3d.gd",
	"res://scripts/enemies/enemy_ai_3d.gd",
	"res://scripts/fx/fx_manager_3d.gd",
	"res://scripts/audio/audio_generator_3d.gd",
	"res://scripts/ui/hud_3d.gd",
	"res://scripts/game_manager_3d.gd",
]

var _err: String = ""
var _progress: int = 0
var _canvas: CanvasLayer
var _bg: ColorRect
var _label: Label


func _ready() -> void:
	_setup_ui()
	_boot.call_deferred()


func _setup_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 128
	add_child(_canvas)

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.04, 0.07, 0.04, 1.0)
	_canvas.add_child(_bg)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_label.text = "SuperShooterHybrid 3D\nLoading..."
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_canvas.add_child(_label)


func _boot() -> void:
	var loaded: Array = []
	for path in MODULES:
		_label.text = "SuperShooterHybrid 3D\n\nLoading: " + path.get_file()
		await get_tree().process_frame
		var script = load(path)
		if script == null:
			_err = path
			_bg.color = Color(0.18, 0.02, 0.02, 1.0)
			_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
			var ok_list := "\n".join(loaded)
			_label.text = (
				"STARTUP ERROR\n\nFailed to load:\n" + path
				+ "\n\nLoaded OK:\n" + ok_list
			)
			return
		loaded.append("  + " + path.get_file().get_basename())
		_progress += 1

	_label.text = "All modules OK — launching 3D world..."
	await get_tree().process_frame
	_launch()


func _launch() -> void:
	var GMScript = load("res://scripts/game_manager_3d.gd")
	if GMScript == null:
		_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		_label.text = "FATAL: game_manager_3d.gd missing"
		return
	var gm = GMScript.new()
	gm.name = "GameManager3D"
	get_parent().add_child(gm)
	_canvas.queue_free()
	queue_free()
