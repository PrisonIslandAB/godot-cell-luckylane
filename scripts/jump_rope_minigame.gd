extends Control

## "Jump Rope" minigame module, hosted by luckylane_level_2.gd's sequencer
## (see its header for the shared minigame contract). Back to the usual 4
## separate lanes (one prisoner per lane, positioned at the centers_x passed
## into setup_lanes) - but unlike every other minigame, each lane also owns
## its own rope that swings on its own independent cycle (low -> high ->
## low), so all 4 are jumping at different times rather than in lockstep.
## Every time a lane's own rope passes low, that lane is checked: if its
## prisoner is airborne (jumped in time, see prisoner.gd), it gets a brief
## success flash; if not, the whole round busts instantly, same strictness
## as Fill the Tube/Stop the Clock. A Column button press makes that lane's
## prisoner jump for a fixed hang-time, so timing the tap to that lane's own
## swing is the game. There's no permanent "solved" per lane - the round
## only finishes once every lane has independently completed REQUIRED_PASSES
## clean passes, so you keep jumping over and over rather than clearing each
## lane once. Each lane's clean pass also speeds its own rope up a bit (see
## ROPE_SPEEDUP_FACTOR), so every lane gets faster and faster, independently,
## as the round goes on.
##
## Each rope is anchored at its own prisoner's outstretched fists (the new
## prisoner_pose.png standing pose holds its hands out at the sprite's own
## left/right edges, as if gripping rope handles - see prisoner.gd's header)
## rather than spanning the full screen or being held by separate turner
## characters, so each lane reads as its own prisoner jumping their own
## rope. It's a Line2D using rope.png's texture (cropped to its own opaque
## band - see ROPE_TEXTURE_REGION - so Line2D's width maps directly to
## visible rope thickness), with its points recomputed every frame along a
## curve between those two hand anchors. The anchors stay at a constant
## height; only the rope's middle swings - a deep sag toward the jumper's
## feet at the danger point, an overhead arc at the safe point - the same
## illusion a real turned rope gives from the front.

signal finished(won: bool)

const GAME_NAME := "JUMP ROPE"
const ROUND_SECONDS := 15.0
const WIN_TEXT := "ALL CLEARED!"
const LOSE_TEXT := "CAUGHT!"

## Unlike the other minigames' backgrounds, these are full-canvas size
## (1920x1080 / 1080x1920) rather than pre-cropped to the GameContainer
## region - same convention luckylane_level_3.gd's slot machine background
## uses (see its REEL_LAYOUT comment). The shared Background node the
## sequencer assigns this to already stretches non-uniformly to fill that
## region regardless, so no extra handling is needed here - just a slight
## vertical squish, same as level 3's.
const BACKGROUND_PATH := {
	"landscape": "res://cells/luckylane/resources/images/backgrounds/courtyard-1920x1080.png",
	"portrait": "res://cells/luckylane/resources/images/backgrounds/courtyard-1080x1920.png",
}

const PrisonerScene := preload("res://cells/luckylane/scenes/prisoner.tscn")
const RopeTexture := preload("res://cells/luckylane/resources/images/ui/rope.png")

## Measured from rope.png (2172x724): the actual rope only occupies a thin
## opaque band vertically centered in a much taller transparent canvas;
## cropping to that band (with a small safety margin - the band wobbles a
## few px along the rope's length) means Line2D's width parameter maps
## directly to the rendered rope's thickness instead of mostly empty space.
const ROPE_TEXTURE_REGION := Rect2(0, 305, 2172, 113)

const ROPE_CYCLE_SECONDS := 1.8  ## starting swing duration (low -> high -> low) per lane; gets faster every pass, see ROPE_SPEEDUP_FACTOR
const ROPE_SPEEDUP_FACTOR := 0.9  ## a lane's cycle duration is multiplied by this after each of ITS clean passes, so that lane's rope speeds up over the round
const MIN_ROPE_CYCLE_SECONDS := 0.8  ## floor on how fast a single lane's swing can get, so it never becomes un-reactable
const REQUIRED_PASSES := 8  ## clean passes a lane needs before it's done; round wins once every lane gets there
const INITIAL_PHASE_MAX_FRACTION := 0.5  ## see begin_play() - keeps every lane's very first low-pass check at least half a cycle away
const ROPE_WIDTH := 16.0  ## thinner than a full-screen rope would need - this is a short personal skipping rope, not a turned one spanning the stage
const ROPE_SEGMENTS := 24  ## points sampled along the curve, for a smooth arc

## How far above the rope's fixed anchor height its middle arcs at the safe
## point, as a fraction of a prisoner's own height. The downward sag isn't
## a fraction like this - it's derived from the actual anchor-to-ground
## distance (_bulge_down below) so the low point lands exactly at the
## jumper's feet instead of overshooting into the floor.
const BULGE_UP_FRACTION := 1.3

## How high up a standing prisoner's outstretched fists sit, as a fraction
## of their own height measured up from the ground - this is where each
## lane's rope is anchored. Measured from prisoner_pose.png's standing pose:
## fist center at y=552.5 of a 1138px-tall figure whose feet sit at y=1170,
## i.e. (1170 - 552.5) / 1138.
const HAND_HEIGHT_FRACTION := 0.543

## Sized to prisoner_pose.png's own standing-pose aspect ratio (643:1215,
## wider than the old pose since the arms are now held straight out to the
## sides) rather than an arbitrary box, same convention as Roll 6's
## dice/Stop the Clock's dials.
const PRISONER_SIZE := {
	"landscape": Vector2(210.0, 397.0),
	"portrait": Vector2(130.0, 246.0),
}

var prisoners: Array = []
var rope_lines: Array = []  ## one Line2D per lane, same index as prisoners
var _active := false

## Per-lane state, all indexed in parallel with prisoners/rope_lines - each
## lane's rope runs on its own clock entirely independently of the others.
var _phase_timers: Array = []  ## seconds into the lane's current swing, wraps at its own _cycle_seconds
var _cycle_seconds: Array = []  ## current swing duration per lane - shrinks each time that lane clears a pass
var _passes_completed: Array = []  ## clean passes per lane so far

## Shared across all lanes since every lane sits at the same height - only
## each lane's rope_left/rope_right (x position) differs.
var _ground_y := 0.0
var _bulge_down := 0.0
var _bulge_up := 0.0
var _rope_anchor_y := 0.0
var _rope_lefts: Array = []
var _rope_rights: Array = []

var _rope_texture: AtlasTexture


func _ready() -> void:
	_rope_texture = AtlasTexture.new()
	_rope_texture.atlas = RopeTexture
	_rope_texture.region = ROPE_TEXTURE_REGION


func _make_rope_line() -> Line2D:
	var line := Line2D.new()
	line.texture = _rope_texture
	line.width = ROPE_WIDTH
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.joint_mode = Line2D.LINE_JOINT_BEVEL
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(line)
	return line


func setup_lanes(centers_x: Array, center_y: float) -> void:
	for child in prisoners:
		child.queue_free()
	prisoners.clear()
	for line in rope_lines:
		line.queue_free()
	rope_lines.clear()

	var p_size: Vector2 = PRISONER_SIZE.get(GameData.screen_orientation, PRISONER_SIZE["landscape"])

	_ground_y = center_y + p_size.y / 2.0
	_rope_anchor_y = _ground_y - p_size.y * HAND_HEIGHT_FRACTION
	_bulge_down = _ground_y - _rope_anchor_y  ## low point lands exactly at the jumper's feet
	_bulge_up = p_size.y * BULGE_UP_FRACTION

	_phase_timers.clear()
	_cycle_seconds.clear()
	_passes_completed.clear()
	_rope_lefts.clear()
	_rope_rights.clear()

	for i in range(4):
		var lane_x: float = centers_x[i]
		var prisoner := PrisonerScene.instantiate()
		add_child(prisoner)
		prisoner.position = Vector2(lane_x - p_size.x / 2.0, center_y - p_size.y / 2.0)
		prisoner.size = p_size
		prisoner.reset()
		prisoners.append(prisoner)

		rope_lines.append(_make_rope_line())
		_rope_lefts.append(lane_x - p_size.x / 2.0)  ## roughly where the standing pose's own fists sit
		_rope_rights.append(lane_x + p_size.x / 2.0)

		## Rope starts resting at its low point for every lane, same neutral
		## look as Stop the Clock's still hand through the intro countdown -
		## the random per-lane desync is injected in begin_play() instead,
		## right as real play starts.
		_phase_timers.append(0.0)
		_cycle_seconds.append(ROPE_CYCLE_SECONDS)
		_passes_completed.append(0)

	_active = false
	_update_all_rope_points()


func begin_play() -> void:
	## Give each lane a random starting point in its own swing so the 4
	## ropes immediately desync instead of all passing low at once. Capped to
	## INITIAL_PHASE_MAX_FRACTION of the cycle rather than the full range -
	## a phase_timer landing right before a full wrap would fire that lane's
	## very first low-pass check almost instantly (while also visually
	## looking like the rope's already down at the prisoner's feet), giving
	## no time to react on the first jump of the round.
	for i in range(_phase_timers.size()):
		_phase_timers[i] = randf() * _cycle_seconds[i] * INITIAL_PHASE_MAX_FRACTION
	_active = true


func handle_lane_pressed(lane: int) -> void:
	if not _active or lane < 0 or lane >= prisoners.size():
		return
	prisoners[lane].jump()


func handle_lane_released(_lane: int) -> void:
	pass  ## Jump Rope only reacts to the press edge - a tap starts a jump.


func stop() -> void:
	_active = false


func _process(delta: float) -> void:
	if not _active:
		return
	for i in range(prisoners.size()):
		_phase_timers[i] += delta
		if _phase_timers[i] >= _cycle_seconds[i]:
			_phase_timers[i] -= _cycle_seconds[i]
			_on_rope_low_pass(i)
			if not _active:
				return
	_update_all_rope_points()


## Checks a single lane each time ITS rope passes low. A miss busts the
## whole round; a clean pass speeds that lane's own rope up a bit and counts
## toward its REQUIRED_PASSES - there's no way to "solve" a lane once and
## coast, it has to keep landing every pass, and the round only ends once
## every lane has gotten there independently.
func _on_rope_low_pass(lane: int) -> void:
	var prisoner = prisoners[lane]
	if prisoner.is_airborne():
		prisoner.celebrate()
	else:
		prisoner.bust()
		_active = false
		finished.emit(false)
		return

	_passes_completed[lane] += 1
	_cycle_seconds[lane] = max(MIN_ROPE_CYCLE_SECONDS, _cycle_seconds[lane] * ROPE_SPEEDUP_FACTOR)

	for passes in _passes_completed:
		if passes < REQUIRED_PASSES:
			return
	_active = false
	finished.emit(true)


func _update_all_rope_points() -> void:
	for i in range(rope_lines.size()):
		_update_rope_points(i, _phase_timers[i] / _cycle_seconds[i])


## A lane's rope anchors stay at a fixed height - only its middle swings,
## from a sag that reaches exactly the jumper's feet (danger, phase 0/1) up
## to a taller overhead arc (safe, phase 0.5), flattening out in between.
## Positive bulge = sags down; negative = arcs up - scaled by a different
## amount each way (see _bulge_down/_bulge_up).
func _update_rope_points(lane: int, phase: float) -> void:
	var c: float = cos(phase * TAU)
	var bulge: float = c * (_bulge_down if c >= 0.0 else _bulge_up)

	## Quadratic bezier control point placed so the curve's own midpoint
	## (not the control point itself) ends up offset by exactly `bulge`.
	var p0 := Vector2(_rope_lefts[lane], _rope_anchor_y)
	var p2 := Vector2(_rope_rights[lane], _rope_anchor_y)
	var control := Vector2((p0.x + p2.x) / 2.0, _rope_anchor_y + bulge * 2.0)

	var points := PackedVector2Array()
	for i in range(ROPE_SEGMENTS + 1):
		var t: float = i / float(ROPE_SEGMENTS)
		var point: Vector2 = p0.lerp(control, t).lerp(control.lerp(p2, t), t)
		points.append(point)
	rope_lines[lane].points = points
