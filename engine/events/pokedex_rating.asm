; Prof. Oak's Pokedex rating (Oak's PC, Oak in person, the Hall of Fame).
;
; 2026-11-03 (Pokedex forms Checkpoint C): counts are the whole collection, base
; species plus form identities, 16-bit (DexCountCollection, dex_forms.asm). The
; seven bands are percentages of NUM_DEX_IDENTITIES computed at assembly time, so
; adding species or forms re-scales them; the old table was 15 vanilla 10-mon
; steps that called 150 owned "complete". The band index (0-6) also picks the
; jingle (PlayPokedexRatingSfx), through hDexRatingBand.

; owned < threshold -> this band. Ceiling division, so "below 25%" is exact.
MACRO dex_rating_percent
	DEF \1 EQU (NUM_DEX_IDENTITIES * (\2) + 99) / 100
ENDM
	dex_rating_percent DEX_RATING_25, 25
	dex_rating_percent DEX_RATING_50, 50
	dex_rating_percent DEX_RATING_75, 75
	dex_rating_percent DEX_RATING_90, 90
	ASSERT 1 < DEX_RATING_25 && DEX_RATING_25 < DEX_RATING_50 && DEX_RATING_50 < DEX_RATING_75 \
	    && DEX_RATING_75 < DEX_RATING_90 && DEX_RATING_90 < NUM_DEX_IDENTITIES, \
	    "Pokedex rating bands collapsed; NUM_DEX_IDENTITIES is too small"

DisplayDexRating:
	farcall DexCountCollection ; wDexRatingNumMonsSeen/Owned (big-endian), de = owned
	ld hl, DexRatingsTable
	ld b, -1
.findRating
	inc b                      ; b = band index
	ld a, [hli]
	ld c, a
	ld a, e
	sub c
	ld a, [hli]                ; threshold high byte
	ld c, a
	ld a, d
	sbc c
	jr c, .foundRating         ; owned < threshold
	inc hl
	inc hl
	jr .findRating
.foundRating
	ld a, b
	ldh [hDexRatingBand], a
	ld a, [hli]
	ld h, [hl]
	ld l, a ; load text pointer into hl
	CheckAndResetEventA EVENT_HALL_OF_FAME_DEX_RATING
	jr nz, .hallOfFame
	push hl
	ld hl, DexCompletionText
	call PrintText
	pop hl
	call PrintText
	farcall PlayPokedexRatingSfx
	jp WaitForTextScrollButtonPress
.hallOfFame
	; The counts are already in wDexRatingNumMonsSeen/Owned; append the text.
	ld de, wDexRatingText
.copyRatingTextLoop
	ld a, [hli]
	cp '@'
	jr z, .doneCopying
	ld [de], a
	inc de
	jr .copyRatingTextLoop
.doneCopying
	ld [de], a
	ret

DexCompletionText:
	text_far _DexCompletionText
	text_end

; dw owned-below threshold, text. Seven bands = the seven rating jingles.
DexRatingsTable:
	dw 1,                  DexRatingText_None
	dw DEX_RATING_25,      DexRatingText_Started
	dw DEX_RATING_50,      DexRatingText_Quarter
	dw DEX_RATING_75,      DexRatingText_Half
	dw DEX_RATING_90,      DexRatingText_ThreeQuarters
	dw NUM_DEX_IDENTITIES, DexRatingText_Nearly
	dw $FFFF,              DexRatingText_Complete ; terminal: always matches
DexRatingsTableEnd:
	ASSERT (DexRatingsTableEnd - DexRatingsTable) / 4 == 7, "PlayPokedexRatingSfx has 7 jingles"

DexRatingText_None:
	text_far _DexRatingText_None
	text_end

DexRatingText_Started:
	text_far _DexRatingText_Started
	text_end

DexRatingText_Quarter:
	text_far _DexRatingText_Quarter
	text_end

DexRatingText_Half:
	text_far _DexRatingText_Half
	text_end

DexRatingText_ThreeQuarters:
	text_far _DexRatingText_ThreeQuarters
	text_end

DexRatingText_Nearly:
	text_far _DexRatingText_Nearly
	text_end

DexRatingText_Complete:
	text_far _DexRatingText_Complete
	text_end
