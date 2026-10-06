; custom_functions/ball_rarity.asm
;
; Rarity-colored overworld Poke Balls (RARITY_COLORED_POKEBALLS_PLAN.md).
;
; wBallRarityPal holds, per sprite slot, the CGB OBJ palette PrepareOAMData ORs
; into that sprite's OAM attributes: 0 standard, 1 Great, 2 Ultra, 3 Master.
; This file is the only writer. It classifies a ball's REAL contents (the
; species or item its pickup script will hand over), never a roll threshold, and
; consumes no RNG, so colouring cannot change an offer.
;
; Rebuilt from scratch (never patched) at two kinds of moment:
;   - every map load: ProcStageLoadDispatch's tail, after sprites and procedural
;     finalize, before SET_PAL_OVERWORLD. Covers warps, battle return (EnterMap)
;     and Continue.
;   - every time contents are re-rolled: the end of rogue_pokemon_randomized_batch
;     (stage entry, mon dice reroll).
;
; Palettes: OBJ palettes 1-3 are BallRarityPalettes in the overworld in both
; colour modes (SetPal_Overworld for non-enhanced CGB, .ReadMasterPals for
; Enhanced). Off CGB the cache stays zero.
;
; Lives in "Relocated HOME Routines" beside item_rarity.asm (same bank as the
; item tier tables and as BufferAllEnhancedColorsGBC). Entry points are farcall /
; farjp only.

; The Enhanced Colors path reads this table with a plain pointer from
; BufferAllEnhancedColorsGBC.ReadMasterPals.
BallRarityPalettes:
	INCLUDE "data/gfx/ball_rarity_palettes.asm"
ASSERT BANK(BallRarityPalettes) == BANK(BufferAllEnhancedColorsGBC), \
	"BallRarityPalettes must share a bank with .ReadMasterPals, which reads it directly"

; Stage reward balls 1-3 sit in sprite slots 7-9 on every rogue stage map; the
; same fixed slot map IsObjectHidden uses (engine/overworld/toggleable_objects.asm).
DEF BALL_RARITY_REWARD_SLOT EQU 7

; ---------------------------------------------------------------------------
; RefreshBallRarityCacheAtLoad - map-load entry.
; A rogue stage entered fresh (EVENT_ENTER_ROOM clear, WarpFound2 clears it on
; every warp) still holds the PREVIOUS stage's offers until its map script
; re-rolls them on the first overworld frame; that roll refreshes again. Leave
; the reward balls standard for that gap rather than show last stage's colours.
; ---------------------------------------------------------------------------
RefreshBallRarityCacheAtLoad::
	CheckEvent EVENT_ENTER_ROOM
	ld d, 0              ; rolls pending: skip the rogue-stage roll slots
	jr z, RefreshBallRarityCache.build
	; fall through

; ---------------------------------------------------------------------------
; RefreshBallRarityCache - rebuild every slot. Clobbers all.
; ---------------------------------------------------------------------------
RefreshBallRarityCache::
	ld d, 1              ; rogue-stage roll slots are current
.build
	xor a
	ld hl, wBallRarityPal
	ld b, NUM_SPRITESTATEDATA_STRUCTS
.clear
	ld [hli], a
	dec b
	jr nz, .clear
	ldh a, [hGBC]
	and a
	ret z
	call GetCurMapStageClass ; preserves bc/de
	bit 1, a                 ; rogue stage map? (Facility is not one)
	ret z
	ld a, d
	and a
	ret z
	ld hl, wRoguePokemon1
	ld c, BALL_RARITY_REWARD_SLOT
.rewardLoop
	ld a, [hli]
	push hl
	push bc
	call BallRaritySetSpeciesSlot
	pop bc
	pop hl
	inc c
	ld a, c
	cp BALL_RARITY_REWARD_SLOT + 3
	jr c, .rewardLoop
	ret

; a = species (0 = no offer), c = sprite slot. Colours slot c by the species'
; legacy class (Uber folds into Master; unknown species read as Poke Ball) when
; that slot really shows a Poke Ball. Clobbers all but c.
BallRaritySetSpeciesSlot:
	and a
	ret z
	ld e, a
	call BallRarityIsBallSlot
	ret nz
	push bc
	farcall RogueClassifySpeciesFar ; e = class 1-4; only d/e cross Bankswitch
	pop bc
	ld a, e
	dec a                ; class 1-4 -> palette 0-3
	; fall through

; a = palette 0-3, c = sprite slot.
BallRarityStoreSlot:
	ld b, 0
	ld hl, wBallRarityPal
	add hl, bc
	ld [hl], a
	ret

; c = sprite slot. Z set when that slot's picture is SPRITE_POKE_BALL. A hidden
; toggleable object keeps its picture (only its image index goes to $ff), so a
; ball hidden now and shown later is still recognised. Clobbers a, hl.
BallRarityIsBallSlot:
	ld a, c
	swap a
	ASSERT SPRITESTATEDATA1_PICTUREID == 0
	ld l, a
	ld h, HIGH(wSpriteStateData1)
	ld a, [hl]
	cp SPRITE_POKE_BALL
	ret
