extends Control

## Single lane's die for the "Roll 6" minigame (luckylane_level_2). Unlike
## reel.gd, this decides its own outcome locally instead of waiting on a
## python-sent result - there's no bet/payout riding on a die roll, just a
## quick luck/timing round, so there's nothing that needs a server-verified
## outcome. The level script only calls roll() and listens for `landed`.
##
## A die is never locked - press it again and it re-rolls even if it's
## currently showing a 6 (the level script re-checks all four dice's
## current value on every landing, so the win condition is "all four show
## 6 right now", not "each one hit 6 at some point").
##
## No dedicated roll animation art exists, so the "roll" is faked by
## rapidly cycling through random faces with a physical-looking wobble
## before settling on the real one, the same trick a physical die-cage
## uses.

signal landed(value: int)

const CYCLE_STEPS := 8
const CYCLE_INTERVAL := 0.06
const WOBBLE_DEGREES := 14.0

@onready var face: TextureRect = $Face
@onready var land_player: AudioStreamPlayer = $LandPlayer
@onready var tick_player: AudioStreamPlayer = $TickPlayer

var value := 0

var _face_textures: Array[Texture2D] = []
var _roll_tween: Tween
var _celebrate_tween: Tween


func _ready() -> void:
	## Only the face wobbles, not FrameOverlay - the frame reads as a fixed
	## window the die tumbles inside, same idea as reel_frame.png never
	## moving while its reel scrolls. The level script sets this control's
	## size after instantiating it, so face.size isn't known yet here - keep
	## the pivot centered whenever it changes instead of computing it once.
	face.resized.connect(func(): face.pivot_offset = face.size / 2.0)
	for i in range(1, 7):
		_face_textures.append(load("res://cells/luckylane/resources/images/symbols/die_%d.png" % i))


func reset() -> void:
	if _roll_tween:
		_roll_tween.kill()
	if _celebrate_tween:
		_celebrate_tween.kill()
	value = 0
	face.texture = null
	face.rotation_degrees = 0.0
	modulate = Color(1, 1, 1, 1)


## Directly shows a face with no roll animation/sound - used for the
## pre-round starting value shown while the intro countdown plays.
func show_value(v: int) -> void:
	if _roll_tween:
		_roll_tween.kill()
	if _celebrate_tween:
		_celebrate_tween.kill()
	value = v
	face.rotation_degrees = 0.0
	modulate = Color(1, 1, 1, 1)
	_show_face(v)


func roll() -> void:
	if _roll_tween:
		_roll_tween.kill()
	## Clear any leftover six-tint immediately so a fresh roll never looks
	## like it's still celebrating a value it's about to leave behind - also
	## kill a still-running celebrate pulse so it can't fight this reset.
	if _celebrate_tween:
		_celebrate_tween.kill()
	modulate = Color(1, 1, 1, 1)

	_roll_tween = create_tween()
	for _i in range(CYCLE_STEPS):
		_roll_tween.tween_callback(_show_face.bind(randi_range(1, 6)))
		_roll_tween.parallel().tween_callback(tick_player.play)
		_roll_tween.parallel().tween_property(
			face, "rotation_degrees", randf_range(-WOBBLE_DEGREES, WOBBLE_DEGREES), CYCLE_INTERVAL
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_roll_tween.tween_callback(_land_on.bind(randi_range(1, 6)))
	_roll_tween.parallel().tween_property(face, "rotation_degrees", 0.0, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _show_face(v: int) -> void:
	face.texture = _face_textures[v - 1]


func _land_on(v: int) -> void:
	value = v
	_show_face(v)
	land_player.play()
	if v == 6:
		_celebrate_six()
	landed.emit(v)


## Gold flourish when landing on 6 - fades back on its own (reel.gd's
## celebrate()) rather than staying tinted, since this die can still be
## re-rolled away from 6 at any time.
func _celebrate_six() -> void:
	_celebrate_tween = create_tween()
	_celebrate_tween.tween_property(self, "modulate", Color(1.7, 1.4, 0.7, 1), 0.15)
	_celebrate_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.45)
