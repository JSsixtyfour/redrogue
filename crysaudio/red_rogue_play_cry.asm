; Red Rogue's cry lookup for the Crystal audio engine. Must sit in the same section as
; engine.asm (_PlayCry) and red_rogue_cries.asm (PokemonCries): both are reached with
; plain calls and reads. HOME's PlayCryWithOffsets switches here.

_RedRoguePlayCry::
; a = species (internal id), b = pitch offset, c = length offset (0, 0 for a plain cry).
; The offsets are the Red move-sound table's pitch/tempo modifier bytes (only GROWL today).
; An id outside 1-NUM_POKEMON_INDEXES plays nothing, as pokecrystal's GetCryIndex does,
; instead of reading past the table (the old engine's CryData lookup had no such guard).
	and a
	ret z
	cp NUM_POKEMON_INDEXES + 1
	ret nc
	dec a ; PokemonCries is in internal species order
	ld e, a
	ld d, 0
	ld hl, PokemonCries
rept MON_CRY_LENGTH
	add hl, de
endr
	ld e, [hl]
	inc hl
	ld d, [hl] ; de = cry id
	inc hl
	ld a, [hli]
	ld [wCryPitch], a
	ld a, [hli]
	ld [wCryPitch + 1], a
	ld a, [hli]
	ld [wCryLength], a
	ld a, [hl]
	ld [wCryLength + 1], a

	ld a, b
	or c
	jr z, .play

; A Red-format row (every Gen 1 cry and the converted later-gen ones) has pitch
; $00-$ff and length $80-$17f: that is the old byte pair with length + $80. For those,
; repeat the old engine's 8-bit wrapping adds exactly, so Growl sounds as it did.
	ld a, [wCryPitch + 1]
	and a
	jr nz, .wide
	ld a, [wCryLength]
	sub $80
	ld l, a ; l = old tempo modifier byte
	ld a, [wCryLength + 1]
	sbc 0
	jr nz, .wide
	ld a, [wCryPitch]
	add b
	ld [wCryPitch], a
	ld a, l
	add c
	add $80
	ld [wCryLength], a
	ld a, 0
	adc 0
	ld [wCryLength + 1], a
	jr .play

.wide
; An authentic Crystal (Gen 2) cry: add the offsets as 16-bit values, the way
; Crystal's battle-animation cry adjusts its length.
	ld a, [wCryPitch]
	add b
	ld [wCryPitch], a
	ld a, [wCryPitch + 1]
	adc 0
	ld [wCryPitch + 1], a
	ld a, [wCryLength]
	add c
	ld [wCryLength], a
	ld a, [wCryLength + 1]
	adc 0
	ld [wCryLength + 1], a

.play
	jp _PlayCry
