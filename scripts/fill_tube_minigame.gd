extends Control

## "Fill the Tube" minigame module, hosted by luckylane_level_2.gd's
## sequencer (see its header for the shared minigame contract). Each of the
## four cabinet Column buttons fills that lane's tube while held (see
## tube.gd) - release pauses it, but it still drains slowly on its own.
## Every lane gets its own random target line each round.
##
## Reaching a line is only half of it: the button stays live afterward, so
## holding past FAIL_MARGIN (tube.gd) bursts the tube and fails the whole
## round instantly - the player has to release right around the line, not
## just get there eventually. Because of the drain, being above the line is
## a live state, not a one-time achievement, so this checks live every
## frame for all four tubes being above their line at once, rather than
## reacting to a single "just reached" event.
##
## tube.tscn's frame (tube_frame.png) is 9-sliced (see its patch_margin_*)
## rather than plainly stretched, since the tube spans nearly the full lane
## height and that height differs a lot between landscape and portrait -
## a plain stretch would badly distort the frame's round top/bottom caps.
## The water fill and target line are still plain colored shapes; the
## frame's opaque rails/caps naturally mask their edges either way, so real
## art for those isn't required for it to look right.

signal finished(won: bool)

const GAME_NAME := "FILL THE TUBE"
const ROUND_SECONDS := 12.0
const WIN_TEXT := "ALL FILLED!"
const LOSE_TEXT := "BUSTED!"

const BACKGROUND_PATH := {
	"landscape": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1920x1080.png",
	"portrait": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1080x1920.png",
}

## Each lane's target line is randomized to a fraction in this range - kept
## under 1.0 - FAIL_MARGIN (tube.gd) so there's always headroom to burst into
## rather than a target sitting right at the tube's physical top.
const TARGET_FRACTION_MIN := 0.4
const TARGET_FRACTION_MAX := 0.8

const TubeScene := preload("res://cells/luckylane/scenes/tube.tscn")

## Tubes fill nearly the whole lane top-to-bottom rather than sitting as a
## small centered element (unlike Roll 6's dice) - width is a fixed size
## per orientation, height fills the space below the round timer bar down
## to near the bottom of the GameContainer region (see luckylane_level_2.gd
## for why that region is 1920x885 / 1080x1725, not the full canvas).
const CONTAINER_HEIGHT := {
	"landscape": 885.0,
	"portrait": 1725.0,
}
const TUBE_WIDTH := {
	"landscape": 400.0,
	"portrait": 220.0,
}
const TOP_MARGIN := 140.0
const BOTTOM_MARGIN := 40.0

var tubes: Array = []
var _active := false


func setup_lanes(centers_x: Array, _center_y: float) -> void:
	for child in get_children():
		child.queue_free()
	tubes.clear()

	var tube_width: float = TUBE_WIDTH.get(GameData.screen_orientation, TUBE_WIDTH["landscape"])
	var container_height: float = CONTAINER_HEIGHT.get(GameData.screen_orientation, CONTAINER_HEIGHT["landscape"])
	var tube_height: float = container_height - TOP_MARGIN - BOTTOM_MARGIN

	for i in range(4):
		var tube := TubeScene.instantiate()
		add_child(tube)
		tube.burst.connect(_on_tube_burst)
		tube.position = Vector2(centers_x[i] - tube_width / 2.0, TOP_MARGIN)
		tube.size = Vector2(tube_width, tube_height)
		tube.reset(randf_range(TARGET_FRACTION_MIN, TARGET_FRACTION_MAX))
		tubes.append(tube)

	_active = true


func handle_lane_pressed(lane: int) -> void:
	if not _active or lane < 0 or lane >= tubes.size():
		return
	tubes[lane].set_filling(true)


func handle_lane_released(lane: int) -> void:
	if lane < 0 or lane >= tubes.size():
		return
	tubes[lane].set_filling(false)


func stop() -> void:
	_active = false
	for tube in tubes:
		tube.set_filling(false)


func _process(_delta: float) -> void:
	if not _active:
		return
	for tube in tubes:
		if not tube.line_reached:
			return
	_active = false
	finished.emit(true)


func _on_tube_burst() -> void:
	if not _active:
		return
	_active = false
	finished.emit(false)
