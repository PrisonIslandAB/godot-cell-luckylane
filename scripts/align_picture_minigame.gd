extends Control

## "Align the Picture" minigame module, hosted by luckylane_level_2.gd's
## sequencer (see its header for the shared minigame contract). Each of the
## four cabinet Column buttons scrolls that lane's picture strip while held
## (see picture_strip.gd) - each lane is dealt one fixed random direction
## for the whole round, never re-rolled by any later press. Releasing
## pauses it in place, no snap-back. Finishes the instant all four lanes are
## simultaneously within ALIGN_TOLERANCE of their aligned position (checked
## live every frame - scrolling a lane away from alignment and back is
## always fine, nothing ever "busts", unlike Fill the Tube).
##
## The four lanes show real quarters of picture_puzzle_*.png (sliced in
## picture_strip.gd via AtlasTexture, so seams line up automatically - no
## need for 4 separately-cut files). The background still reuses Fill the
## Tube's for now; a dedicated one would need the same technical spec (see
## that module's header) if wanted later.

signal finished(won: bool)

const GAME_NAME := "ALIGN THE PICTURE"
const ROUND_SECONDS := 15.0
const WIN_TEXT := "PICTURE COMPLETE!"
const LOSE_TEXT := "TIME'S UP"  ## only ever loses via the sequencer's own timeout.

const BACKGROUND_PATH := {
	"landscape": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1920x1080.png",
	"portrait": "res://cells/luckylane/resources/images/backgrounds/fill_the_tube_1080x1920.png",
}

const PictureStripScene := preload("res://cells/luckylane/scenes/picture_strip.tscn")

## Strips fill nearly the whole lane, same footprint convention as Fill the
## Tube's tubes (see its header for why the region is 1920x885 / 1080x1725).
## Matches picture_puzzle_*.png's per-lane slice width exactly (1840/4=460,
## 880/4=220) so lanes sit edge-to-edge with no horizontal stretch - a gap
## here would show background between what's meant to look like one
## continuous picture.
const STRIP_WIDTH := {
	"landscape": 460.0,
	"portrait": 220.0,
}
const CONTAINER_HEIGHT := {
	"landscape": 885.0,
	"portrait": 1725.0,
}
const TOP_MARGIN := 140.0
const BOTTOM_MARGIN := 40.0

var strips: Array = []
var _active := false


func setup_lanes(centers_x: Array, _center_y: float) -> void:
	for child in get_children():
		child.queue_free()
	strips.clear()

	var strip_width: float = STRIP_WIDTH.get(GameData.screen_orientation, STRIP_WIDTH["landscape"])
	var container_height: float = CONTAINER_HEIGHT.get(GameData.screen_orientation, CONTAINER_HEIGHT["landscape"])
	var strip_height: float = container_height - TOP_MARGIN - BOTTOM_MARGIN

	for i in range(4):
		var strip := PictureStripScene.instantiate()
		add_child(strip)
		strip.position = Vector2(centers_x[i] - strip_width / 2.0, TOP_MARGIN)
		strip.size = Vector2(strip_width, strip_height)
		strip.setup(i)
		strip.randomize_start()
		strips.append(strip)

	_active = true


func handle_lane_pressed(lane: int) -> void:
	if not _active or lane < 0 or lane >= strips.size():
		return
	strips[lane].start_scrolling()


func handle_lane_released(lane: int) -> void:
	if lane < 0 or lane >= strips.size():
		return
	strips[lane].stop_scrolling()


func stop() -> void:
	_active = false
	for strip in strips:
		strip.stop_scrolling()


func _process(_delta: float) -> void:
	if not _active:
		return
	for strip in strips:
		if not strip.is_aligned():
			return
	_active = false
	for strip in strips:
		strip.snap_to_alignment()
	finished.emit(true)
