extends Control

## Reusable slot-machine reel used by luckylane_level_3. Owns its own scroll
## animation (continuous spin + decelerate-and-land tween); the level
## script only tells it which symbol strip to use, when to spin, and which
## symbol to land on, per luckylane_level3.py's UDP message contract.
##
## Single-row window: only one symbol is visible at a time, sitting at the
## top of the Mask child's rect. That symbol is always symbols[current_index].
##
## The level script sets this control's `size` (square, per-orientation -
## landscape and portrait cabinet backgrounds have differently sized reel
## windows) before calling setup(); the Mask/frame overlay are anchored
## fractionally so they scale to whatever size that turns out to be.

## Kept short and with no extra laps: python's symbol is already fixed the
## instant SPIN was pressed, so on a column press we snap straight to the
## nearest upcoming occurrence of it - no lingering "big spin" delay, just
## a quick mechanical stop.
const STOP_TWEEN_TIME := 0.12
const EXTRA_LAPS_ON_STOP := 0

@onready var mask: Control = $Mask
@onready var strip: Control = $Mask/Strip
@onready var amount_label: Label = $AmountLabel
@onready var frame_overlay: TextureRect = $FrameOverlay
@onready var tick_player: AudioStreamPlayer = $TickPlayer
@onready var stop_player: AudioStreamPlayer = $StopPlayer

var symbols: Array = []
var symbol_size: Vector2 = Vector2.ZERO
var row_height: float = 0.0
var scroll_offset := 0.0
var spinning := false
var stop_tween: Tween
var spin_speed := 900.0  # px/sec while spinning; level script ramps this up per locked reel
var last_tick_index := 0
var celebrate_tween: Tween
var amount_pulse_tween: Tween


func setup(symbol_strip: Array) -> void:
	symbols = symbol_strip
	spinning = false
	symbol_size = mask.size
	row_height = symbol_size.y
	last_tick_index = 0

	for child in strip.get_children():
		child.queue_free()

	## Three copies of the strip stacked so the reel can scroll seamlessly;
	## the middle copy is what's visible at rest, with slack above/below.
	for lap in range(3):
		for i in range(symbols.size()):
			var icon := _make_symbol_node(symbols[i])
			icon.position.y = (lap * symbols.size() + i) * row_height
			strip.add_child(icon)

	_set_scroll_offset(0.0)


func spin() -> void:
	if stop_tween:
		stop_tween.kill()
	spinning = true


## Matches this reel's tick/stop SFX to python's [Sounds] volume (sent via
## LUCKYLANE_INIT_REELS) so Godot's cues don't play louder than python's.
func set_volume(linear_volume: float) -> void:
	var db := linear_to_db(clampf(linear_volume, 0.0, 1.0))
	tick_player.volume_db = db
	stop_player.volume_db = db


## Swaps this reel's square from the spinning symbol strip to a plain
## label - used for LUCKYLANE_SHOW_BET_OPTIONS, where the four reel
## windows temporarily double as the bet-picker's option display. The
## ornate frame is hidden too so the text isn't visually competing with
## it - easier to read what you're about to press. Takes the already-
## formatted display text (e.g. "25%") rather than a raw number, since
## the level script is the one that knows how python wants it shown.
func show_amount(text: String) -> void:
	amount_label.text = text
	amount_label.visible = true
	amount_label.scale = Vector2(1, 1)
	amount_label.modulate = Color(1, 1, 1, 1)
	strip.visible = false
	frame_overlay.visible = false


func hide_amount() -> void:
	amount_label.visible = false
	strip.visible = true
	frame_overlay.visible = true


## Quick gold flourish on the currently-shown option number, then reverts
## to the normal symbol view once it's done - used when a Column button
## closes the picker (whether it confirmed this option or another one;
## either way it's a clean closing beat rather than an instant cut).
func confirm_amount() -> void:
	if not amount_label.visible:
		return

	amount_label.pivot_offset = amount_label.size / 2.0

	if amount_pulse_tween:
		amount_pulse_tween.kill()
	amount_pulse_tween = create_tween()
	amount_pulse_tween.set_parallel(true)
	amount_pulse_tween.tween_property(amount_label, "scale", Vector2(1.3, 1.3), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	amount_pulse_tween.tween_property(amount_label, "modulate", Color(1.8, 1.5, 0.8, 1), 0.12)
	amount_pulse_tween.chain().tween_interval(0.12)
	amount_pulse_tween.chain().tween_callback(hide_amount)


## Brief gold shimmer, played on all four reels on a win.
func celebrate() -> void:
	if celebrate_tween:
		celebrate_tween.kill()
	modulate = Color(1, 1, 1, 1)
	celebrate_tween = create_tween()
	celebrate_tween.tween_property(self, "modulate", Color(1.8, 1.5, 0.8, 1), 0.15)
	celebrate_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.45)


## Takes effect on the next frame if this reel is still spinning; a no-op
## once it's stopped. Lets the level script ramp difficulty up as each
## column locks without restarting or otherwise disturbing the animation.
func set_spin_speed(speed: float) -> void:
	spin_speed = speed


func stop_on_symbol(symbol: String) -> void:
	spinning = false

	var strip_height: float = symbols.size() * row_height
	var target_index := _find_next_symbol_index(symbol)

	## strip.position.y runs the strip in the opposite direction from a
	## naive "index * row_height" offset (scrolling forward reveals
	## descending strip indices), so the offset that actually lands
	## target_index in the window is its mirror image around the strip
	## length, not target_index itself.
	var target_offset: float = float((symbols.size() - target_index) % symbols.size()) * row_height
	while target_offset <= scroll_offset:
		target_offset += strip_height
	target_offset += EXTRA_LAPS_ON_STOP * strip_height

	if stop_tween:
		stop_tween.kill()
	stop_tween = create_tween()
	stop_tween.tween_method(_set_scroll_offset, scroll_offset, target_offset, STOP_TWEEN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	## Played on tween completion rather than on the button press itself,
	## so the "thud" lands in sync with the reel actually visually settling.
	stop_tween.finished.connect(stop_player.play)


func _process(delta: float) -> void:
	if spinning:
		_set_scroll_offset(scroll_offset + spin_speed * delta)


func _set_scroll_offset(value: float) -> void:
	scroll_offset = value
	var strip_height: float = symbols.size() * row_height
	strip.position.y = fmod(scroll_offset, strip_height) - strip_height

	## One tick per symbol-row crossed, whether freely spinning or mid
	## decelerate-to-stop - ticks naturally slow down with the tween.
	var tick_index := int(floor(scroll_offset / row_height))
	if tick_index != last_tick_index:
		last_tick_index = tick_index
		tick_player.play()


func _find_next_symbol_index(symbol: String) -> int:
	var strip_height: float = symbols.size() * row_height
	var current_index := int(floor(fmod(scroll_offset, strip_height) / row_height))
	for step in range(symbols.size()):
		var idx := (current_index + step) % symbols.size()
		if symbols[idx] == symbol:
			return idx
	push_error("Luckylane reel: symbol '%s' not found in strip" % symbol)
	return current_index


func _make_symbol_node(symbol: String) -> Control:
	var texture := _load_symbol_texture(symbol)
	if texture:
		var rect := TextureRect.new()
		## Must be set before .size/.texture: EXPAND_IGNORE_SIZE keeps the
		## rect's minimum size at (0, 0) regardless of the source texture's
		## native resolution, so our explicit symbol_size below isn't
		## clamped back up to the texture's real (much larger) size.
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture = texture
		rect.size = symbol_size
		return rect

	## Placeholder until the symbol image is in: colored tile + symbol name,
	## so the reel is fully testable before art assets exist.
	var placeholder := ColorRect.new()
	placeholder.size = symbol_size
	placeholder.color = _placeholder_color(symbol)

	var label := Label.new()
	label.text = symbol.to_upper()
	label.size = placeholder.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.add_child(label)
	return placeholder


func _load_symbol_texture(symbol: String) -> Texture2D:
	var path := "res://cells/luckylane/resources/images/symbols/%s.png" % symbol
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _placeholder_color(symbol: String) -> Color:
	match symbol:
		"logo":
			return Color(0.8, 0.1, 0.1)
		"giovanni":
			return Color(0.1, 0.1, 0.8)
		"pi":
			return Color(0.9, 0.7, 0.1)
		"rose":
			return Color(0.6, 0.1, 0.8)
		_:
			return Color(0.3, 0.3, 0.3)
