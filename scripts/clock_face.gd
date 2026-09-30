extends Control

## Single lane's clock for the "Stop the Clock" minigame
## (stop_the_clock_minigame.gd). A pointer sweeps continuously around the
## face at a fixed angular speed, always visible, starting diametrically
## opposite a randomly-placed target mark (different per lane each round -
## "stop at the right time") - reset() only positions it there, it doesn't
## start moving until start_ticking() (once the round's intro countdown
## finishes). Pressing the button stops it in place:
## landing within FAIL_MARGIN_DEG of the mark locks the lane solved for
## good; missing busts the whole round instantly (same strictness as Fill
## the Tube's overshoot) and reveals exactly how far off the stop was.
##
## clock_face.png (the dial) and clock_hand.png (the pointer, pivoting
## around its own image center - both are 340x340) are real art; the
## target mark and "how far off" label are still drawn directly (_draw()
## below) since their position/text need to change live, which a static
## image can't do.

signal locked_in()
signal burst()

const ROTATION_SPEED := TAU / 2.0  ## radians/sec - one full turn every 2s ("fairly quickly")

## How far the stop can land from the mark and still count, in degrees -
## without this the mark would need frame-perfect timing to hit.
const FAIL_MARGIN_DEG := 7.5

## Measured from clock_face.png (340x340, so half-size 170): the dark
## paintable dial runs to about r=138 before the gold rim starts - the mark
## is drawn out to that radius (as a fraction of this control's own
## half-size, so it scales with whatever size the level script assigns)
## rather than the rim, which would look wrong painted over.
const DIAL_RADIUS_FRACTION := 138.0 / 170.0

const FaceTexture := preload("res://cells/luckylane/resources/images/ui/clock_face.png")

const MARK_COLOR := Color(0.95, 0.95, 0.9, 1.0)
const LOCKED_TINT := Color(0.5, 1.6, 0.6, 1.0)
const BUST_TINT := Color(1.7, 0.55, 0.5, 1.0)

@onready var hand_texture: TextureRect = $HandTexture
@onready var ding_player: AudioStreamPlayer = $DingPlayer

var target_angle := 0.0  ## radians, 0 = up, increases clockwise - the "correct" stop angle
var angle := 0.0
var spinning := false
var locked := false
var busted := false
var miss_degrees := 0.0  ## set on a miss, for the "how far off" readout


func _ready() -> void:
	hand_texture.resized.connect(func(): hand_texture.pivot_offset = hand_texture.size / 2.0)


## Randomizes a fresh target mark and positions the hand at the opposite
## side of the face, holding still there until start_ticking() - called
## once per round, well before the round (and its countdown) begins.
func reset() -> void:
	target_angle = randf() * TAU
	angle = wrapf(target_angle + PI, 0.0, TAU)
	spinning = false
	locked = false
	busted = false
	hand_texture.modulate = Color(1, 1, 1, 1)
	_apply_hand()
	queue_redraw()


## Starts the hand sweeping - called once the intro countdown finishes.
func start_ticking() -> void:
	spinning = true


## No-op once already stopped (locked or busted) - there's nothing left to
## stop again, a miss already ended the round and a hit is permanent.
func stop_and_check() -> void:
	if not spinning:
		return
	spinning = false

	var diff_deg := rad_to_deg(wrapf(angle - target_angle, -PI, PI))
	if abs(diff_deg) <= FAIL_MARGIN_DEG:
		locked = true
		hand_texture.modulate = LOCKED_TINT
		ding_player.play()
		locked_in.emit()
	else:
		busted = true
		miss_degrees = diff_deg
		hand_texture.modulate = BUST_TINT
		_show_burst()
		burst.emit()
	_apply_hand()
	queue_redraw()


func _process(delta: float) -> void:
	if not spinning:
		return
	angle = wrapf(angle + ROTATION_SPEED * delta, 0.0, TAU)
	_apply_hand()
	queue_redraw()


func _apply_hand() -> void:
	hand_texture.rotation = angle


func _show_burst() -> void:
	var flash := create_tween()
	flash.tween_property(self, "modulate", Color(1.8, 0.6, 0.5, 1), 0.08)
	flash.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)


func _draw() -> void:
	var radius: float = min(size.x, size.y) / 2.0 * DIAL_RADIUS_FRACTION
	var center := size / 2.0

	draw_texture_rect(FaceTexture, Rect2(Vector2.ZERO, size), false)

	var mark_dir := Vector2(sin(target_angle), -cos(target_angle))
	draw_line(center + mark_dir * radius * 0.7, center + mark_dir * radius, MARK_COLOR, 3.0, true)

	if busted:
		var label_pos := Vector2(0.0, size.y + 8.0)
		draw_string(ThemeDB.fallback_font, label_pos, "%.0f° off" % abs(miss_degrees),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(0.9, 0.25, 0.2, 1.0))
