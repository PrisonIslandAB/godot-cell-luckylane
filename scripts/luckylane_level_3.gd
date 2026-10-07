extends Control

## Godot-rendered slot machine level ("Luckylane Level3" in the python
## source, luckylane_level3.py). Four reels spin at once; python decides
## the winning symbol for every reel the instant SPIN is pressed and only
## tells Godot WHEN each reel should stop, never WHAT it lands on - python
## owns the outcome, Godot owns the animation.
##
## Betting is entirely python-driven: the physical Hint button opens a bet
## picker (LUCKYLANE_SHOW_BET_OPTIONS) and the Column buttons pick one of
## the four options while it's open - Godot only displays whatever python
## tells it to. The on-screen bet_button.png is a readout, not an input;
## it shows the confirmed bet from LUCKYLANE_BET_UPDATE. See
## luckylane_level3.py's module docstring for the full UDP message
## contract this listens for.
##
## Background art + reel placement:
## The cabinet background art (resources/images/backgrounds/) was designed
## full-screen (1920x1080 / 1080x1920), but this level only gets the
## GameContainer sub-region below the shared header bar (1920x885 landscape,
## 1080x1725 portrait - both 195px shorter than the full canvas). Background
## is stretched to fill that region exactly (non-uniform, slightly squished
## vertically), and REEL_LAYOUT below is the black cutout centers/size from
## the original art, scaled by that same vertical factor so reels line up
## with the squished cutouts. Re-measure from the source art if it changes.

const ReelScene := preload("res://cells/luckylane/scenes/reel.tscn")

## Difficulty ramp: starts slow so the first column is easy to time, and
## speeds up every time a reel locks so the remaining ones get harder to
## call. Purely visual - doesn't touch which symbol anything lands on.
const BASE_SPIN_SPEED := 550.0
const SPIN_SPEED_STEP := 275.0  # added per locked reel

## reel_index -> {position: Vector2 (top-left, px), size: float (square side, px)}
## Both orientations are currently a single horizontal row of 4 (matching
## Column 1-4 left to right); portrait's background art used to be a 2x2
## grid earlier on, so if it ever goes back to one, re-add that mapping
## note and re-measure - reading order (top-left, top-right, bottom-left,
## bottom-right) is what it used then.
##
## If any of these background images gets swapped for new art, re-measure
## rather than assuming the old coordinates still apply - verify by
## resizing the source image to its container size (STRETCH_SCALE,
## non-uniform - see the note above on background sizing) and overlaying
## these coordinates on it, the same transform Godot does at runtime.
##
## All-in is a full-screen overlay (all_in_overlay, one big transparent
## cutout, no per-reel alignment needed) shown on top of this same normal
## background+reels rather than a different background - see
## _hide_bet_options()/_show_bet_options().
##
## all_in_overlay_offset_top: the overlay's transparent hole doesn't quite
## clear the reel row on its own (measured ~78px of overlap in landscape,
## portrait already clears it with margin). Extending the TextureRect
## upward past the screen's top edge (bottom stays anchored in place)
## stretches the whole image taller, pushing the hole's edges outward
## proportionally - same idea as background sizing above, just applied to
## one edge instead of uniformly. Re-derive if this art changes: measure
## the hole's top (flood-fill from center for the transparent region) and
## solve for the offset that puts it above the reel row's top with some
## margin.
const REEL_LAYOUT := {
	"landscape": {
		"background": "res://cells/luckylane/resources/images/backgrounds/slot_machine_1920x1080.png",
		"all_in_overlay": "res://cells/luckylane/resources/images/backgrounds/slot_machine_all_in_overlay_1920x1080.png",
		"all_in_overlay_offset_top": -170.0,
		"reels": [
			{"center": Vector2(380, 375), "size": 250.0},
			{"center": Vector2(748, 375), "size": 250.0},
			{"center": Vector2(1116, 375), "size": 250.0},
			{"center": Vector2(1484, 375), "size": 250.0},
		],
	},
	"portrait": {
		"background": "res://cells/luckylane/resources/images/backgrounds/slot_machine_1080x1920.png",
		"all_in_overlay": "res://cells/luckylane/resources/images/backgrounds/slot_machine_all_in_overlay_1080x1920.png",
		"all_in_overlay_offset_top": 0.0,
		"reels": [
			{"center": Vector2(182, 702), "size": 195.0},
			{"center": Vector2(422, 702), "size": 195.0},
			{"center": Vector2(660, 702), "size": 195.0},
			{"center": Vector2(897, 702), "size": 195.0},
		],
	},
}

@onready var background: TextureRect = $Background
@onready var reels_layer: Control = $ReelsLayer
@onready var all_in_overlay: TextureRect = $AllInOverlay
@onready var poof_particles: CPUParticles2D = $PoofParticles
@onready var flash_overlay: ColorRect = $FlashOverlay
@onready var result_banner: Control = $ResultBanner
@onready var header_label: Label = $ResultBanner/HeaderLabel
@onready var payout_label: Label = $ResultBanner/PayoutLabel
@onready var win_particles: CPUParticles2D = $ResultBanner/WinParticles
@onready var bet_label: Label = $BetButton/BetLabel
@onready var bet_prompt_frame: Panel = $BetPromptFrame
@onready var bet_prompt_label: Label = $BetPromptFrame/BetPromptLabel
@onready var bet_button_player: AudioStreamPlayer = $BetButtonPlayer
@onready var lever_pull_player: AudioStreamPlayer = $LeverPullPlayer
@onready var chip_in_player: AudioStreamPlayer = $ChipInPlayer
@onready var all_right_player: AudioStreamPlayer = $AllRightPlayer
@onready var jackpot_player: AudioStreamPlayer = $JackpotPlayer
@onready var yeehaw_player: AudioStreamPlayer = $YeehawPlayer
@onready var aww_player: AudioStreamPlayer = $AwwPlayer
@onready var slot_machine_player: AudioStreamPlayer = $SlotMachinePlayer
@onready var auto_lock_timer: Control = $AutoLockTimer

var reels: Array = []
var layout: Dictionary
var locked_reels := 0
var current_reel_strips: Array = []
var current_bet_options: Array = []
var bet_initialized := false
var master_volume := 1.0
var bet_pulse_tween: Tween
var banner_tween: Tween
var payout_tween: Tween


func level_specific_start_game() -> void:
	EventBus.game_specific_message_received.connect(_on_game_specific_message_received)
	result_banner.visible = false
	bet_initialized = false

	layout = REEL_LAYOUT.get(GameData.screen_orientation, REEL_LAYOUT["landscape"])
	background.texture = load(layout.background)
	all_in_overlay.texture = load(layout.all_in_overlay)
	all_in_overlay.offset_top = layout.get("all_in_overlay_offset_top", 0.0)
	all_in_overlay.visible = false


func _on_game_specific_message_received(message: String, data: Variant) -> void:
	match message:
		"LUCKYLANE_INIT_REELS":
			_init_reels(data)
		"LUCKYLANE_BET_UPDATE":
			_update_bet(data)
		"LUCKYLANE_SHOW_BET_OPTIONS":
			_show_bet_options(data)
		"LUCKYLANE_HIDE_BET_OPTIONS":
			_hide_bet_options(data)
		"LUCKYLANE_SPIN":
			_spin_all()
		"LUCKYLANE_STOP_REEL":
			_stop_reel(data.reel_index, data.symbol)
		"LUCKYLANE_RESULT":
			_show_result(data)


## data: { "symbols": [...], "reels": [[...], [...], [...], [...]], "volume": 0.0-1.0 }
## Sent once per round start; rebuilds each reel's strip from scratch so
## python stays the single source of truth for strip content/order.
func _init_reels(data: Dictionary) -> void:
	result_banner.visible = false

	if data.has("volume"):
		master_volume = float(data.volume)
		_apply_master_volume()

	for child in reels_layer.get_children():
		child.queue_free()
	reels.clear()

	current_reel_strips = data.reels
	for reel_index in range(current_reel_strips.size()):
		var reel := ReelScene.instantiate()
		reels_layer.add_child(reel)
		reel.set_volume(master_volume)
		reels.append(reel)

	_apply_reel_slots(layout.reels)


## Positions/sizes every reel to match REEL_LAYOUT's slot table and builds
## its symbol strip (setup() reads mask.size, which only updates once
## .size is set below).
func _apply_reel_slots(slots: Array) -> void:
	for i in range(reels.size()):
		if i >= slots.size():
			push_error("Luckylane: no layout slot for reel_index %s" % i)
			continue
		var slot: Dictionary = slots[i]
		var slot_size: float = slot.size
		var half: float = slot_size / 2.0
		var reel = reels[i]
		reel.position = slot.center - Vector2(half, half)
		reel.size = Vector2(slot_size, slot_size)
		if i < current_reel_strips.size():
			reel.setup(current_reel_strips[i])


## Matches every level-owned SFX player to python's [Sounds] volume so
## Godot's cues don't play louder than python's (see LUCKYLANE_INIT_REELS
## in luckylane_level3.py). Each Reel scales its own tick/stop players the
## same way via set_volume(), called on it individually above.
func _apply_master_volume() -> void:
	var db := linear_to_db(clampf(master_volume, 0.0, 1.0))
	for player in [
		bet_button_player, lever_pull_player, chip_in_player, all_right_player,
		jackpot_player, yeehaw_player, aww_player, slot_machine_player,
	]:
		player.volume_db = db


## data: { "bet": int, "credits": int, "reborrow": bool }
## Sent at round start and whenever the confirmed bet changes.
func _update_bet(data: Dictionary) -> void:
	bet_label.text = str(data.bet)

	## Skip the pulse on the very first update (round start) - only flash
	## when the player actually just picked a new bet.
	if bet_initialized:
		_pulse_bet_label()
	bet_initialized = true


func _pulse_bet_label() -> void:
	bet_label.pivot_offset = bet_label.size / 2.0

	if bet_pulse_tween:
		bet_pulse_tween.kill()
	bet_pulse_tween = create_tween()
	bet_pulse_tween.set_parallel(true)
	bet_pulse_tween.tween_property(bet_label, "scale", Vector2(1.35, 1.35), 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bet_pulse_tween.tween_property(bet_label, "modulate", Color(1.6, 1.3, 0.7, 1), 0.12)
	bet_pulse_tween.chain().set_parallel(true)
	bet_pulse_tween.tween_property(bet_label, "scale", Vector2(1, 1), 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bet_pulse_tween.tween_property(bet_label, "modulate", Color(1, 1, 1, 1), 0.2)


## data: { "options": [int, int, int, int], "option_percents": [int, int,
##          int, int], "prompt": String }
## Hint button opened the picker - swap each reel's square from symbols to
## its option's percentage (left to right, matching the Column buttons).
## "prompt" is shown above the reels while the picker is open; it comes
## from python (luckylane_level3.py's PO file) rather than being
## hardcoded here so it goes through the same translation pipeline as
## every other on-screen string.
func _show_bet_options(data: Dictionary) -> void:
	result_banner.visible = false
	bet_button_player.play()
	if all_in_overlay.visible:
		all_in_overlay.visible = false
		_poof_transition()
	var options: Array = data.options
	var percents: Array = data.get("option_percents", [])
	current_bet_options = options
	for i in range(reels.size()):
		if i < options.size():
			var label_text := ("%d%%" % percents[i]) if i < percents.size() else str(options[i])
			reels[i].show_amount(label_text)
	bet_prompt_label.text = str(data.get("prompt", ""))
	bet_prompt_frame.visible = true


## data: { "reel_index": 0-3 or null }
## null means the picker was cancelled (SPIN pressed while it was open) -
## every square just reverts. Otherwise only the picked reel gets the
## confirm flourish; the rest revert immediately.
func _hide_bet_options(data: Dictionary) -> void:
	bet_prompt_frame.visible = false
	var chosen_index = data.get("reel_index")
	var is_all_in := false
	if chosen_index != null:
		chip_in_player.play()
		is_all_in = _is_highest_option(int(chosen_index))
		if is_all_in:
			all_right_player.play()

	for i in range(reels.size()):
		if chosen_index != null and i == int(chosen_index):
			reels[i].confirm_amount()
		else:
			reels[i].hide_amount()

	if is_all_in:
		all_in_overlay.visible = true
		_poof_transition()


## Gray smoke burst masking the instant the all-in overlay pops in/out.
func _poof_transition() -> void:
	poof_particles.position = size / 2.0
	poof_particles.restart()
	poof_particles.emitting = true


## True when the picked option is the largest of the four shown - always
## the "all of your current credits" option, but found by value rather
## than by a hardcoded index so this stays correct even if python ever
## reorders LUCKYLANE_SHOW_BET_OPTIONS's options array.
func _is_highest_option(index: int) -> bool:
	if index < 0 or index >= current_bet_options.size():
		return false
	var chosen_value: int = current_bet_options[index]
	for value in current_bet_options:
		if value > chosen_value:
			return false
	return true


func _spin_all() -> void:
	result_banner.visible = false
	locked_reels = 0
	lever_pull_player.play()
	slot_machine_player.play()
	auto_lock_timer.start()
	for reel in reels:
		reel.set_spin_speed(BASE_SPIN_SPEED)
		reel.spin()


## data: { "reel_index": 0-3, "symbol": "logo" }
func _stop_reel(reel_index: int, symbol: String) -> void:
	if reel_index >= 0 and reel_index < reels.size():
		reels[reel_index].stop_on_symbol(symbol)
	else:
		push_error("Luckylane: LUCKYLANE_STOP_REEL for out-of-range reel_index %s" % reel_index)
		return

	## Ramp up whichever reels are still spinning - set_spin_speed() is a
	## no-op on ones that already stopped.
	locked_reels += 1
	var next_speed: float = BASE_SPIN_SPEED + locked_reels * SPIN_SPEED_STEP
	for reel in reels:
		reel.set_spin_speed(next_speed)


## data: { "win": bool, "bet": int, "multiplier": int, "payout": int,
##          "credits": int, "symbols": [...] }
func _show_result(data: Dictionary) -> void:
	auto_lock_timer.stop()
	if data.win:
		_show_win_banner(data)
	else:
		_show_loss_banner()


func _show_win_banner(data: Dictionary) -> void:
	## 4-of-a-kind (the rarer, higher-multiplier hit) gets the bigger
	## "JACKPOT" treatment; 3-of-a-kind is still a clear win, just calmer.
	var is_jackpot: bool = int(data.multiplier) >= 3
	header_label.text = "JACKPOT!" if is_jackpot else "WINNER!"
	header_label.modulate = Color(1, 1, 1, 1)
	payout_label.visible = true

	if is_jackpot:
		jackpot_player.play()
	else:
		yeehaw_player.play()
	for reel in reels:
		reel.celebrate()

	flash_overlay.color.a = 0.55
	var flash_tween := create_tween()
	flash_tween.tween_property(flash_overlay, "color:a", 0.0, 0.35)

	win_particles.restart()
	win_particles.emitting = true

	if payout_tween:
		payout_tween.kill()
	payout_tween = create_tween()
	payout_tween.tween_method(_set_payout_text, 0, int(data.payout), 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	_pop_in_banner()


func _set_payout_text(value: int) -> void:
	payout_label.text = "+%s" % value


func _show_loss_banner() -> void:
	header_label.text = "NO LUCK"
	header_label.modulate = Color(0.75, 0.75, 0.75, 1)
	payout_label.visible = false
	aww_player.play()
	_pop_in_banner()


func _pop_in_banner() -> void:
	result_banner.visible = true
	result_banner.pivot_offset = result_banner.size / 2.0
	result_banner.scale = Vector2(0.6, 0.6)
	result_banner.modulate.a = 0.0

	if banner_tween:
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.set_parallel(true)
	banner_tween.tween_property(result_banner, "scale", Vector2(1, 1), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(result_banner, "modulate:a", 1.0, 0.2)
