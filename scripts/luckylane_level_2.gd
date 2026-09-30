extends Control

## Sequencer/host for Luckylane's "Level 2" gauntlet of short minigames.
## Owns all the shared chrome (background, dividers, round timer bar, intro
## title card, result banner) and cycles through MINIGAME_SCENES in a
## shuffled-bag random order (each minigame plays once before any repeats)
## forever: intro card with a 3-2-1 countdown -> the minigame plays until it
## signals finished() or the round timer runs out -> result banner (the
## minigame's own win text, or a generic timeout message) -> waits for the
## green "Guess" button -> next minigame's intro.
##
## Godot UDP message contract (python -> godot, matches
## luckylane_level2.py's module docstring):
##
##   "LUCKYLANE_LANE_BUTTON"
##       data: { "lane": 0-3, "pressed": bool }
##       Sent on both the press and release edge of a Column 1-4 button -
##       forwarded to whichever minigame is currently playing exactly as
##       received. Only the raw sensor_id -> lane translation happens in
##       python (the physical Column 1-4 buttons are sensor_id 3-6, same
##       hardware as level 3's reels - see luckylane_level3.py's
##       SENSOR_ID_TO_REEL); this script never touches raw
##       sensor_value_changed at all.
##
##   "LUCKYLANE_CONTINUE_PRESSED"
##       data: {}
##       Sent on the press edge of the green Guess button (repurposed here
##       to advance past a finished minigame's result screen). Only acted
##       on while waiting between minigames; ignored otherwise.
##
##   "LUCKYLANE_SKIP_PRESSED"
##       data: {}
##       Sent on the press edge of the red Hint button (sensor_id 2 - see
##       luckylane_level2.py's SENSOR_ID_SKIP), repurposed here to bail out
##       of whichever minigame is currently showing (intro, playing, or
##       already waiting to continue) and jump straight to the next one,
##       skipping its result screen entirely.
##
## Each minigame is its own scene/script (see roll6_minigame.gd,
## fill_tube_minigame.gd) implementing a small duck-typed contract:
##   const GAME_NAME: String
##   const ROUND_SECONDS: float
##   const WIN_TEXT: String
##   const LOSE_TEXT: String
##   const BACKGROUND_PATH: Dictionary  ## {"landscape": .., "portrait": ..}
##   signal finished(won: bool)
##   func setup_lanes(centers_x: Array, center_y: float) -> void
##   func handle_lane_pressed(lane: int) -> void
##   func handle_lane_released(lane: int) -> void
##   func stop() -> void
##   func begin_play() -> void  ## optional - see _start_round()

const MINIGAME_SCENES := [
	preload("res://cells/luckylane/scenes/roll6_minigame.tscn"),
	preload("res://cells/luckylane/scenes/fill_tube_minigame.tscn"),
	preload("res://cells/luckylane/scenes/align_picture_minigame.tscn"),
	preload("res://cells/luckylane/scenes/stop_the_clock_minigame.tscn"),
]

const INTRO_SECONDS := 3.0

## Shared 4-lanes-in-a-row layout, matching luckylane_level_3.gd's
## REEL_LAYOUT convention: pixel centers within the GameContainer region.
## Background art is already sized to that region (1920x885 / 1080x1725),
## not the full canvas, so no squish-factor math is needed. Each minigame
## picks its own element size for these centers (a die is square, a tube is
## a tall rect, etc.) - see its own script.
const LANE_LAYOUT := {
	"landscape": {
		"lane_centers_x": [240.0, 720.0, 1200.0, 1680.0],
		"lane_center_y": 442.0,
	},
	"portrait": {
		"lane_centers_x": [182.0, 422.0, 660.0, 897.0],
		"lane_center_y": 862.0,
	},
}

## Measured from roll_6_timer_frame.png's transparent cutout (640x80 art).
const TIMER_FILL_LEFT := 0.0297
const TIMER_FILL_RIGHT := 0.9703

enum State { INTRO, PLAYING, WAIT_CONTINUE }

@onready var background: TextureRect = $Background
@onready var content_layer: Control = $ContentLayer
@onready var round_timer_node: Control = $RoundTimer
@onready var timer_fill: ColorRect = $RoundTimer/TimerFill
@onready var seconds_label: Label = $RoundTimer/SecondsLabel
@onready var intro_overlay: Control = $IntroOverlay
@onready var intro_name_label: Label = $IntroOverlay/GameNameLabel
@onready var intro_countdown_label: Label = $IntroOverlay/CountdownLabel
@onready var result_banner: Control = $ResultBanner
@onready var header_label: Label = $ResultBanner/HeaderLabel
@onready var continue_label: Label = $ResultBanner/ContinueLabel
@onready var win_chime_player: AudioStreamPlayer = $WinChimePlayer
@onready var aww_player: AudioStreamPlayer = $AwwPlayer

var current_minigame: Control
var state: State = State.INTRO
var time_remaining := 0.0
var intro_seconds_remaining := 0.0

var _minigame_bag: Array = []


func level_specific_start_game() -> void:
	EventBus.game_specific_message_received.connect(_on_game_specific_message_received)

	_start_next_minigame()


func _pick_next_minigame_scene() -> PackedScene:
	if _minigame_bag.is_empty():
		_minigame_bag = MINIGAME_SCENES.duplicate()
		_minigame_bag.shuffle()
	return _minigame_bag.pop_front()


func _start_next_minigame() -> void:
	for child in content_layer.get_children():
		child.queue_free()

	current_minigame = _pick_next_minigame_scene().instantiate()
	content_layer.add_child(current_minigame)
	current_minigame.finished.connect(_on_minigame_finished)

	background.texture = load(current_minigame.BACKGROUND_PATH.get(
		GameData.screen_orientation, current_minigame.BACKGROUND_PATH["landscape"]
	))

	var layout: Dictionary = LANE_LAYOUT.get(GameData.screen_orientation, LANE_LAYOUT["landscape"])
	current_minigame.setup_lanes(layout.lane_centers_x, layout.lane_center_y)

	_start_intro()


func _start_intro() -> void:
	result_banner.visible = false
	round_timer_node.visible = false
	intro_name_label.text = current_minigame.GAME_NAME
	state = State.INTRO
	intro_seconds_remaining = INTRO_SECONDS
	intro_overlay.visible = true
	_update_intro_display()


func _update_intro_display() -> void:
	intro_countdown_label.text = str(int(ceil(intro_seconds_remaining)))


func _start_round() -> void:
	state = State.PLAYING
	result_banner.visible = false
	round_timer_node.visible = true
	time_remaining = current_minigame.ROUND_SECONDS
	_update_timer_display()
	## Optional - most minigames only ever react to button presses (which
	## the sequencer already gates to PLAYING state), but a couple animate
	## on their own (Stop the Clock's ticking hand) and need to know
	## exactly when play begins rather than starting during the intro.
	if current_minigame.has_method("begin_play"):
		current_minigame.begin_play()


func _process(delta: float) -> void:
	match state:
		State.INTRO:
			intro_seconds_remaining = max(0.0, intro_seconds_remaining - delta)
			_update_intro_display()
			if intro_seconds_remaining <= 0.0:
				intro_overlay.visible = false
				_start_round()
		State.PLAYING:
			time_remaining = max(0.0, time_remaining - delta)
			_update_timer_display()
			if time_remaining <= 0.0:
				_end_round(false, "TIME'S UP")
		State.WAIT_CONTINUE:
			pass


func _update_timer_display() -> void:
	var fraction: float = time_remaining / current_minigame.ROUND_SECONDS
	timer_fill.anchor_right = TIMER_FILL_LEFT + (TIMER_FILL_RIGHT - TIMER_FILL_LEFT) * fraction
	seconds_label.text = str(int(ceil(time_remaining)))


func _on_game_specific_message_received(message: String, data: Variant) -> void:
	match message:
		"LUCKYLANE_LANE_BUTTON":
			_on_lane_button(int(data.lane), bool(data.pressed))
		"LUCKYLANE_CONTINUE_PRESSED":
			_on_continue_pressed()
		"LUCKYLANE_SKIP_PRESSED":
			_on_skip_pressed()


func _on_lane_button(lane: int, pressed: bool) -> void:
	if state != State.PLAYING:
		return
	if pressed:
		current_minigame.handle_lane_pressed(lane)
	else:
		current_minigame.handle_lane_released(lane)


func _on_continue_pressed() -> void:
	if state != State.WAIT_CONTINUE:
		return
	_start_next_minigame()


## Bails out of the current minigame from any state (intro, playing, or
## already waiting to continue) straight into the next one - stop() is
## already safe to call regardless of state (every minigame's stop() just
## halts its own interactivity, matching how _end_round() also calls it).
func _on_skip_pressed() -> void:
	current_minigame.stop()
	_start_next_minigame()


## A minigame that finished on its own (not via timeout) can still have this
## queued from the same frame the round timer independently ends it - the
## state guard keeps a stray finished() from double-ending the round.
func _on_minigame_finished(won: bool) -> void:
	if state != State.PLAYING:
		return
	_end_round(won, current_minigame.WIN_TEXT if won else current_minigame.LOSE_TEXT)


func _end_round(won: bool, header_text: String) -> void:
	current_minigame.stop()
	state = State.WAIT_CONTINUE
	round_timer_node.visible = false
	header_label.text = header_text
	if won:
		header_label.modulate = Color(1, 0.84, 0.35, 1)
		win_chime_player.play()
	else:
		header_label.modulate = Color(0.75, 0.75, 0.75, 1)
		aww_player.play()
	continue_label.text = "PRESS GREEN TO CONTINUE"
	result_banner.visible = true
