extends Control

## Single lane's tube for the "Fill the Tube" minigame
## (fill_tube_minigame.gd). Fills upward while its button is held, at a
## constant rate; it also drains slowly all the time, held or not, so a
## lane left alone won't just sit there - it needs occasional top-ups.
##
## line_reached is a live "is this lane currently at or above its target"
## state, not a one-time achievement - it can go false again as the tube
## drains, since the minigame's win condition is "are all four lanes above
## their line at once", checked live every frame. Crossing into it plays a
## one-shot flourish each time (ding/particles/line flash), and it stays
## live after that: continuing to hold risks overshooting past FAIL_MARGIN
## and bursting the whole round (burst) - the player has to release in
## time, not just eventually reach the line.
##
## The fill and target line are inset to the frame's actual glass window
## (see _update_glass_bounds) rather than spanning the tube's full width -
## the frame's rails have a thin transparent margin at their outer edge
## that would otherwise let the color peek out past them.

signal burst()

const FILL_RATE := 1.0 / 3.5  ## fraction per second while held: empty -> full in 3.5s
const DRAIN_RATE := 0.04  ## fraction per second, always - full -> empty in 25s if left untouched

## How far past the target line the fill can go (while still being held)
## before it bursts - the player's reaction window after target_reached
## fires. At FILL_RATE above, 0.03 is about a 0.1s window.
const FAIL_MARGIN := 0.03

## Measured from tube_frame.png (256px wide) at the straight-rail rows,
## consistent throughout: the glass window spans x=58-197, sitting inside
## the NinePatchRect's stretchable middle section (33-221, matching
## FrameOverlay's patch_margin_left/right in tube.tscn). Because that middle
## section is what stretches, the glass window's fraction of the final
## width changes with size - recomputed on resize rather than a fixed
## anchor. Re-measure if tube_frame.png ever changes.
const FRAME_SRC_WIDTH := 256.0
const FRAME_LEFT_CAP := 33.0
const FRAME_RIGHT_CAP := 35.0
const GLASS_LEFT_SRC := 58.0
const GLASS_RIGHT_SRC := 197.0

## Same idea vertically: the top cap (the rounded opening) is opaque, and
## fades through a feathered/anti-aliased edge right at the image's top
## border, so confining the fill/line to below it avoids that feather
## letting color peek out past the frame.
const FRAME_TOP_CAP := 64.0

## FrameOverlay's own patch_margin_bottom (tube.tscn) is 100px, but only the
## last ~73px of that is the solid, opaque base - above that, from y=632
## (where the straight rail ends) to about y=659, the glass is still
## see-through, just narrowing into the base. Using the full 100px as the
## fill's floor left that whole narrowing strip permanently empty, reading
## as water floating above the tube's visible bottom. FILL_BOTTOM_CAP stops
## short of full closure (~y=648, still a wide-open window) so the fill
## sits lower without clipping into the point where the opening pinches
## shut. Re-measure both values together if tube_frame.png ever changes.
const FILL_BOTTOM_CAP := 84.0

@onready var fill_mask: Control = $FillMask
@onready var fill_rect: ColorRect = $FillMask/FillRect
@onready var target_line: ColorRect = $FillMask/TargetLine
@onready var reach_particles: CPUParticles2D = $ReachParticles
@onready var ding_player: AudioStreamPlayer = $DingPlayer

var fill_fraction := 0.0
var target_fraction := 0.75
var filling := false
var line_reached := false
var busted := false


func _ready() -> void:
	resized.connect(_update_glass_bounds)
	_update_glass_bounds()


## Insets FillMask (and, since TargetLine is now its child, the target line
## with it) to the frame's actual glass window in final pixel space, given
## whatever size the level script assigned.
func _update_glass_bounds() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var middle_src := FRAME_SRC_WIDTH - FRAME_LEFT_CAP - FRAME_RIGHT_CAP
	var middle_final: float = max(0.0, w - FRAME_LEFT_CAP - FRAME_RIGHT_CAP)
	var glass_left := FRAME_LEFT_CAP + (GLASS_LEFT_SRC - FRAME_LEFT_CAP) / middle_src * middle_final
	var glass_right := FRAME_LEFT_CAP + (GLASS_RIGHT_SRC - FRAME_LEFT_CAP) / middle_src * middle_final

	fill_mask.anchor_left = glass_left / w
	fill_mask.anchor_right = glass_right / w
	fill_mask.anchor_top = FRAME_TOP_CAP / h
	fill_mask.anchor_bottom = 1.0 - FILL_BOTTOM_CAP / h


func reset(new_target_fraction: float) -> void:
	fill_fraction = 0.0
	target_fraction = new_target_fraction
	filling = false
	line_reached = false
	busted = false
	modulate = Color(1, 1, 1, 1)
	fill_rect.color = Color(0.25, 0.55, 0.85, 0.75)
	target_line.modulate = Color(1, 1, 1, 1)
	target_line.anchor_top = 1.0 - target_fraction
	target_line.anchor_bottom = 1.0 - target_fraction
	_update_fill_visual()


## Ignored once busted - a burst ends the whole round, so there's nothing
## left to resume filling.
func set_filling(value: bool) -> void:
	filling = value and not busted


func _process(delta: float) -> void:
	if busted:
		return

	var rate := -DRAIN_RATE
	if filling:
		rate += FILL_RATE
	if is_equal_approx(fill_fraction, 0.0) and rate <= 0.0:
		return  ## already empty and not actively filling - nothing to update
	fill_fraction = clampf(fill_fraction + rate * delta, 0.0, 1.0)
	_update_fill_visual()

	var above := fill_fraction >= target_fraction
	if above and not line_reached:
		_celebrate_line_reached()
	line_reached = above

	if not filling:
		return

	if fill_fraction >= target_fraction + FAIL_MARGIN:
		busted = true
		filling = false
		_show_burst()
		burst.emit()


func _update_fill_visual() -> void:
	fill_rect.anchor_top = 1.0 - fill_fraction
	fill_rect.anchor_bottom = 1.0


func _celebrate_line_reached() -> void:
	ding_player.play()
	## reach_particles is a Tube-local sibling of FillMask, not a child of
	## it, so its position has to be converted from the fraction-of-safe-
	## zone space FillMask/TargetLine live in back into Tube's full space.
	var safe_top := FRAME_TOP_CAP
	var safe_bottom := size.y - FILL_BOTTOM_CAP
	reach_particles.position = Vector2(size.x / 2.0, safe_bottom - target_fraction * (safe_bottom - safe_top))
	reach_particles.restart()
	reach_particles.emitting = true

	var pulse := create_tween()
	pulse.tween_property(target_line, "modulate", Color(1.6, 1.6, 0.6, 1), 0.1)
	pulse.tween_property(target_line, "modulate", Color(1, 1, 1, 1), 0.3)


func _show_burst() -> void:
	fill_rect.color = Color(1, 0.3, 0.2, 0.85)
	var flash := create_tween()
	flash.tween_property(self, "modulate", Color(1.8, 0.6, 0.5, 1), 0.08)
	flash.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.3)
