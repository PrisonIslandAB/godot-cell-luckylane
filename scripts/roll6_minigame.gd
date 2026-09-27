extends Control

## "Roll 6" minigame module, hosted by luckylane_level_2.gd's sequencer (see
## its header for the shared minigame contract). Each of the four cabinet
## Column buttons rolls that lane's die - a die is never locked, pressing
## again always re-rolls it even if it's currently showing a 6. Finishes
## the instant all four dice simultaneously show 6.
##
## A die's outcome is decided locally (die.gd) rather than by python:
## there's no bet or payout riding on it, just a quick luck/timing round,
## so nothing needs a server-verified result.

signal finished(won: bool)

const GAME_NAME := "ROLL 6"
const ROUND_SECONDS := 12.0
const WIN_TEXT := "ALL SIXES!"
const LOSE_TEXT := "TIME'S UP"  ## Roll 6 only ever loses via the sequencer's own timeout.

const BACKGROUND_PATH := {
	"landscape": "res://cells/luckylane/resources/images/backgrounds/roll_6_1920x1080.png",
	"portrait": "res://cells/luckylane/resources/images/backgrounds/roll_6_1080x1920.png",
}

## Dice show a starting value in this range (never 6) as soon as the round
## is set up, so the intro countdown never shows a lane already at goal.
const STARTING_FACE_MIN := 1
const STARTING_FACE_MAX := 4

const DieScene := preload("res://cells/luckylane/scenes/die.tscn")

const DIE_SIZE := {
	"landscape": 300.0,
	"portrait": 220.0,
}

var dice: Array = []
var _active := false


func setup_lanes(centers_x: Array, center_y: float) -> void:
	for child in get_children():
		child.queue_free()
	dice.clear()

	var die_size: float = DIE_SIZE.get(GameData.screen_orientation, DIE_SIZE["landscape"])
	var half := die_size / 2.0
	for i in range(4):
		var die := DieScene.instantiate()
		add_child(die)
		die.landed.connect(_on_die_landed)
		die.position = Vector2(centers_x[i] - half, center_y - half)
		die.size = Vector2(die_size, die_size)
		die.show_value(randi_range(STARTING_FACE_MIN, STARTING_FACE_MAX))
		dice.append(die)

	_active = true


func handle_lane_pressed(lane: int) -> void:
	if not _active or lane < 0 or lane >= dice.size():
		return
	dice[lane].roll()


func handle_lane_released(_lane: int) -> void:
	pass  ## Roll 6 only reacts to the press edge.


func stop() -> void:
	_active = false


func _on_die_landed(_value: int) -> void:
	if not _active:
		return
	for die in dice:
		if die.value != 6:
			return
	_active = false
	finished.emit(true)
