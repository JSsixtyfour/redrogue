; Red Rogue's low-HP alarm policy around the Crystal engine's PlayDanger. _UpdateSound
; calls this once per frame in place of PlayDanger (crysaudio/engine.asm).
;
; - DISABLE_LOW_HEALTH_ALARM ($ff) keeps its Red meaning, "turn the alarm off": the
;   faint path writes it (engine/battle/core.asm RemoveFaintedPlayerMon), and Crystal's
;   PlayDanger alone would read $ff as "on" and keep beeping.
; - Tone-pair limit (Shin Red import Phase 2.10, kept by user decision 2026-10-28): the
;   alarm plays 3 high/low pairs, then stays quiet until the HP bar leaves red. While the
;   alarm is idle in battle with the bar not red, the allotment is topped up again.
;   wLowHealthTonePairs holds pairs remaining + 1.
RedRogueLowHealthAlarm:
	ld a, [wLowHealthAlarm]
	cp DISABLE_LOW_HEALTH_ALARM
	jr z, .disable
	bit DANGER_ON_F, a
	jr z, .idle
	and ~(1 << DANGER_ON_F)
	jp nz, PlayDanger ; mid-pair
; a fresh high/low pair starts this frame: spend one
	ld a, [wLowHealthTonePairs]
	and LOW_HEALTH_TIMER_MASK
	jr z, .disable
	dec a
	ld [wLowHealthTonePairs], a
	jp nz, PlayDanger
.disable
	xor a
	ld [wLowHealthAlarm], a
	ret

.idle
	ldh a, [hIsInBattle]
	and a
	ret z
	cp $ff ; lost battle
	ret z
	ld a, [wPlayerHPBarColor]
	cp HP_BAR_RED
	ret z
	ld a, 3 + 1
	ld [wLowHealthTonePairs], a
	ret
