extends Control

## Single lane's prisoner for the "Jump Rope" minigame
## (jump_rope_minigame.gd). Each lane has its own rope and its own
## independent swing timing - a tap makes this prisoner jump for
## JUMP_DURATION seconds, and every time ITS rope passes low, the minigame
## checks whether it was airborne: landing it plays a quick success flash
## (celebrate()), missing busts the whole round instantly, same strictness
## as Fill the Tube/Stop the Clock. There's no permanent "solved" state
## here - the round only ends once every lane has independently completed
## enough passes (see jump_rope_minigame.gd's REQUIRED_PASSES), so this
## prisoner has to keep landing jumps pass after pass, not just once.
## Repeated taps just refresh the hang-time, so spamming is a valid (if
## less precise) strategy.
##
## Uses the real prisoner_pose.png sprite sheet (standing with fists held
## out to the sides as if gripping a rope's handles, and a knees-tucked
## jump, both cropped to the sheet's full height rather than their own
## tight bounding box - see STANDING_REGION/JUMPING_REGION). Both poses
## share almost the same head-top position at that shared height, so
## swapping between them naturally "lifts" the figure while jumping: the
## tucked pose is shorter, so its feet land higher up in the same display
## box without any extra animation code needed. The outstretched fists sit
## right at the sprite's own left/right edges, which is also where
## jump_rope_minigame.gd anchors this lane's rope - so the rope reads as
## held in this prisoner's own hands rather than a disembodied line.

const JUMP_DURATION := 0.5  ## seconds airborne after a tap

const SHEET := preload("res://cells/luckylane/resources/images/ui/prisoner_pose.png")

## Measured from prisoner_pose.png (1295x1215, two poses side by side,
## separated by a transparent gap from x=643 to x=646): each region is
## cropped to its pose's own column but the SHEET's full height, so both
## textures occupy the same vertical reference (see header above).
## Re-measure if prisoner_pose.png ever changes.
const STANDING_REGION := Rect2(0, 0, 643, 1215)
const JUMPING_REGION := Rect2(646, 0, 649, 1215)

## The standing pose's own feet sit slightly above the crop's bottom edge
## (measured y=1170 of 1215) - nudges the control down by that fraction so
## the feet land exactly on the lane's ground line instead of floating
## slightly above it.
const GROUND_OFFSET_FRACTION := (1215.0 - 1170.0) / 1215.0

const BUST_TINT := Color(1.6, 0.55, 0.5, 1.0)

@onready var sprite: TextureRect = $Sprite
@onready var ding_player: AudioStreamPlayer = $DingPlayer
@onready var thud_player: AudioStreamPlayer = $ThudPlayer

var jump_timer := 0.0
var busted := false

var _standing_tex: AtlasTexture
var _jumping_tex: AtlasTexture


func _ready() -> void:
	_standing_tex = AtlasTexture.new()
	_standing_tex.atlas = SHEET
	_standing_tex.region = STANDING_REGION
	_jumping_tex = AtlasTexture.new()
	_jumping_tex.atlas = SHEET
	_jumping_tex.region = JUMPING_REGION
	sprite.texture = _standing_tex
	resized.connect(_update_sprite_layout)
	_update_sprite_layout()


## Nudges the sprite down by GROUND_OFFSET_FRACTION (see its comment) -
## recomputed on resize since the level script sets .size after
## instantiating this, same pattern as die.gd's face pivot.
func _update_sprite_layout() -> void:
	if size.y <= 0.0:
		return
	sprite.position = Vector2(0.0, size.y * GROUND_OFFSET_FRACTION)
	sprite.size = size


func reset() -> void:
	jump_timer = 0.0
	busted = false
	modulate = Color(1, 1, 1, 1)
	sprite.texture = _standing_tex


## Ignored once busted - a miss already ended the round, nothing left to
## jump for.
func jump() -> void:
	if busted:
		return
	jump_timer = JUMP_DURATION
	sprite.texture = _jumping_tex


func is_airborne() -> bool:
	return jump_timer > 0.0


## Brief success flash for clearing a single pass - not a permanent state,
## since the next pass still requires another well-timed jump.
func celebrate() -> void:
	ding_player.play()
	modulate = Color(1, 1, 1, 1)
	var pulse := create_tween()
	pulse.tween_property(self, "modulate", Color(0.5, 1.8, 0.6, 1), 0.12)
	pulse.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)


func bust() -> void:
	busted = true
	thud_player.play()
	var flash := create_tween()
	flash.tween_property(self, "modulate", Color(1.9, 0.6, 0.5, 1), 0.08)
	flash.tween_property(self, "modulate", BUST_TINT, 0.3)


func _process(delta: float) -> void:
	if jump_timer <= 0.0:
		return
	jump_timer = max(0.0, jump_timer - delta)
	if jump_timer <= 0.0 and not busted:
		sprite.texture = _standing_tex
