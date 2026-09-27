extends Control

## Single lane's scrolling picture strip for the "Align the Picture"
## minigame (align_picture_minigame.gd). Each lane is dealt one random
## scroll direction for the whole round, decided once in randomize_start()
## - holding its button always scrolls that same fixed way, never
## re-rolled by any later press; releasing just pauses it in place, same
## hold/pause idiom as tube.gd, no snap-back on release.
##
## Loops seamlessly: three stacked copies of the same loop_height-tall
## content scroll together, the same trick reel.gd uses for its
## continuously-spinning reels. Alignment isn't a one-way lock like the
## tube's line - it's just "is this lane currently sitting within
## ALIGN_TOLERANCE_FRACTION of a whole loop" (is_aligned()), re-checked
## live every frame by the minigame, so scrolling away from alignment and
## back again is always fine, nothing ever "busts".
##
## The four lanes' textures are quarters of one shared picture
## (picture_puzzle_*.png - see align_picture_minigame.gd's header), sliced
## via AtlasTexture rather than asking for 4 separate files, so seams line
## up automatically. loop_height is the source image's own height in
## pixels, since that's this lane's one full "page" before it repeats.

const PICTURE_PATH := {
	"landscape": "res://cells/luckylane/resources/images/ui/picture_puzzle_1840x700.png",
	"portrait": "res://cells/luckylane/resources/images/ui/picture_puzzle_880x1550.png",
}
const PICTURE_LANES := 4

const SCROLL_SPEED := 220.0  ## px/sec while held

## How close counts as aligned, as a fraction of loop_height - reuses the
## same strictness as tube.gd's FAIL_MARGIN per the chat.
const ALIGN_TOLERANCE_FRACTION := 0.03

@onready var strip: Control = $Mask/Strip
@onready var ding_player: AudioStreamPlayer = $DingPlayer

var loop_height := 1.0
var align_tolerance := 0.0
var lane_texture: Texture2D

var total_offset := 0.0  ## unwrapped - keeps accumulating across presses, never reset to [0, loop_height)
var direction := 1.0
var scrolling := false
var _was_aligned := false


func _ready() -> void:
	resized.connect(_layout_strip)


## Slices out this lane's vertical quarter of the shared picture. Must be
## called once, before randomize_start(), and before this control's final
## size is relied on (position/size are typically set by the level script
## right around the same time - _layout_strip() runs again on resize
## regardless of call order).
func setup(lane_index: int) -> void:
	var path: String = PICTURE_PATH.get(GameData.screen_orientation, PICTURE_PATH["landscape"])
	var full_texture: Texture2D = load(path)
	var slice_width := full_texture.get_width() / float(PICTURE_LANES)
	loop_height = float(full_texture.get_height())
	align_tolerance = ALIGN_TOLERANCE_FRACTION * loop_height

	var atlas := AtlasTexture.new()
	atlas.atlas = full_texture
	atlas.region = Rect2(lane_index * slice_width, 0, slice_width, loop_height)
	lane_texture = atlas

	_layout_strip()


## Builds the loop's 3 stacked copies at the current width - rebuilt on
## resize since the level script sets .size after instantiating this (and
## may call setup() before or after that).
func _layout_strip() -> void:
	if lane_texture == null or size.x <= 0.0:
		return
	for child in strip.get_children():
		child.queue_free()

	for lap in range(3):
		var rect := TextureRect.new()
		rect.texture = lane_texture
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.position = Vector2(0, lap * loop_height)
		rect.size = Vector2(size.x, loop_height)
		strip.add_child(rect)

	_apply_scroll()


func randomize_start() -> void:
	total_offset = randf_range(0.0, loop_height)
	direction = 1.0 if randf() < 0.5 else -1.0
	scrolling = false
	_was_aligned = false
	_apply_scroll()


## Direction is fixed for the whole round (see randomize_start()) - a press
## just resumes scrolling that same way, it never re-rolls anything, so
## repeated press messages during one hold or across several separate
## presses all behave identically.
func start_scrolling() -> void:
	scrolling = true


func stop_scrolling() -> void:
	scrolling = false


func _process(delta: float) -> void:
	if not scrolling:
		return
	total_offset += direction * SCROLL_SPEED * delta
	_apply_scroll()

	var aligned := is_aligned()
	if aligned and not _was_aligned:
		_celebrate_aligned()
	_was_aligned = aligned


func is_aligned() -> bool:
	var nearest: float = round(total_offset / loop_height) * loop_height
	return abs(total_offset - nearest) <= align_tolerance


## Smoothly finishes the last little bit of distance to perfect alignment -
## called once every lane is already within tolerance, for a satisfying
## "click into place" on the win rather than leaving each lane at whatever
## slightly-off position it happened to be released at.
func snap_to_alignment() -> void:
	scrolling = false
	var nearest: float = round(total_offset / loop_height) * loop_height
	var tween := create_tween()
	tween.tween_method(_set_total_offset, total_offset, nearest, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_total_offset(value: float) -> void:
	total_offset = value
	_apply_scroll()


func _apply_scroll() -> void:
	strip.position.y = -fposmod(total_offset, loop_height)


func _celebrate_aligned() -> void:
	ding_player.play()
