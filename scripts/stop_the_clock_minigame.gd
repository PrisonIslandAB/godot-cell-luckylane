extends Control

## "Stop the Clock" minigame module, hosted by luckylane_level_2.gd's
## sequencer (see its header for the shared minigame contract). Each lane's
## clock hand holds still (at its starting position) through the intro
## countdown and only starts sweeping once begin_play() fires, right as the
## round actually begins - matching every other minigame staying static
## during the countdown. A Column button press then stops that lane's hand
## in place (see clock_face.gd): landing within its target mark's fail
## margin locks the lane solved for good; missing busts the whole round
## instantly, same strictness as Fill the Tube's overshoot. Finishes once
## all four lanes are locked.
##
## The dial and hand are real art (clock_face.png/clock_hand.png); the
## background still reuses Fill the Tube's for now.

signal finished(won: bool)

const GAME_NAME := "STOP THE CLOCK"
const ROUND_SECONDS := 15.0
const WIN_TEXT := "PERFECT TIMING!"
const LOSE_TEXT := "MISTIMED!"

const BACKGROUND_PATH := {
	"landscape": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1920x1080.png",
	"portrait": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1080x1920.png",
}

const ClockFaceScene := preload("res://cells/luckylane/scenes/clock_face.tscn")

## Clocks sit as a compact centered element per lane, same convention as
## Roll 6's dice (unlike Fill the Tube/Align the Picture, which fill the
## whole lane) - a round face doesn't need the extra room.
const CLOCK_SIZE := {
	"landscape": 340.0,
	"portrait": 200.0,
}

var clocks: Array = []
var _active := false


func setup_lanes(centers_x: Array, center_y: float) -> void:
	for child in get_children():
		child.queue_free()
	clocks.clear()

	var clock_size: float = CLOCK_SIZE.get(GameData.screen_orientation, CLOCK_SIZE["landscape"])
	var half := clock_size / 2.0
	for i in range(4):
		var clock := ClockFaceScene.instantiate()
		add_child(clock)
		clock.burst.connect(_on_burst)
		clock.position = Vector2(centers_x[i] - half, center_y - half)
		clock.size = Vector2(clock_size, clock_size)
		clock.reset()
		clocks.append(clock)

	_active = true


func begin_play() -> void:
	for clock in clocks:
		clock.start_ticking()


func handle_lane_pressed(lane: int) -> void:
	if not _active or lane < 0 or lane >= clocks.size():
		return
	clocks[lane].stop_and_check()


func handle_lane_released(_lane: int) -> void:
	pass  ## Stop the Clock only reacts to the press edge - a tap stops the hand.


func stop() -> void:
	_active = false
	for clock in clocks:
		clock.spinning = false


func _process(_delta: float) -> void:
	if not _active:
		return
	for clock in clocks:
		if not clock.locked:
			return
	_active = false
	finished.emit(true)


func _on_burst() -> void:
	if not _active:
		return
	_active = false
	finished.emit(false)
