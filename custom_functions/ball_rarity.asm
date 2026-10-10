; custom_functions/ball_rarity.asm
;
; Rarity-colored overworld Poke Balls (RARITY_COLORED_POKEBALLS_PLAN.md).
;
; wBallRarityPal holds, per sprite slot, the CGB OBJ palette PrepareOAMData ORs
; into that sprite's OAM attributes: 0 not a ball, 1 Great, 2 Ultra, 3 Master,
; 7 standard (the red Poke Ball). EVERY SPRITE_POKE_BALL sprite on every map is
; at least 7: a ball with no tier is simply "not set", so it is red everywhere,
; including Facility's fake balls and maps this file never mentions.
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
	INCLUDE "data/gfx/ball_rarity_palettes_enhanced.asm"
BallRarityPalettesEnd:
ASSERT BallRarityPalettesEnd - BallRarityPalettes == 4 * PAL_SIZE, \
	"ball_rarity_palettes_enhanced.asm must hold exactly four rows: Great, Ultra, Master, standard"
ASSERT BANK(BallRarityPalettes) == BANK(BufferAllEnhancedColorsGBC), \
	"BallRarityPalettes must share a bank with .ReadMasterPals, which reads it directly"

; Stage reward balls 1-3 sit in sprite slots 7-9 on every rogue stage map; the
; same fixed slot map IsObjectHidden uses (engine/overworld/toggleable_objects.asm).
DEF BALL_RARITY_REWARD_SLOT EQU 7

; The random item ball on a rogue stage map is slot 6 (RandomPickUpItem rule 3).
DEF BALL_RARITY_ITEM_SLOT EQU 6

; OAM palette every ball without a tier uses: the red Poke Ball (OBJ 7, the Master
; row seen through rOBP1; see data/gfx/ball_rarity_palettes.asm).
DEF BALL_RARITY_STANDARD_PAL EQU 7

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
	; Every ball sprite on every map starts as a standard (red) ball; the tiers
	; below only override. Done first so each early return still leaves them red.
	ld c, 0
.markBalls
	call BallRarityIsBallSlot
	jr nz, .notBall
	ld a, BALL_RARITY_STANDARD_PAL
	call BallRarityStoreSlot
.notBall
	inc c
	ld a, c
	cp NUM_SPRITESTATEDATA_STRUCTS
	jr c, .markBalls
	ldh a, [hCurMap]
	ld c, 1                  ; the three balls sit in slots 1-3 in these rooms
	cp REWARD_ROOM
	jr z, .pokemonBalls
	cp OAKS_LAB              ; starter balls: wRoguePokemon1-3 too
	jr z, .pokemonBalls
	; Special maps with ONE item ball at slot 6 that are not in RogueStageMapTable:
	; RandomPickUpItem's .normalPickup hands over wRogueItem. They roll it the same
	; way as a stage (Random_Item_Selection, then RogueRefresh), so honour d.
	cp FIGHTING_DOJO
	jr z, .itemMap
	cp GAME_CORNER
	jr nz, .notItemMap
.itemMap
	ld a, d
	and a
	ret z
	ld a, [wRogueItem]
	ld c, BALL_RARITY_ITEM_SLOT
	jr BallRarityItemSlot
.notItemMap
	call GetCurMapStageClass ; preserves bc/de
	bit 1, a                 ; rogue stage map? (Facility is not one)
	jr nz, .rogueStage
	; Procedural maps. Their contents are restored by the finalize step inside
	; ProcStageLoadDispatch, before this refresh, so d (pending roll) is moot.
	; RandomPickUpItem's precedence: cemetery slot 1 first, then wild-area 2-5.
	bit 0, a                 ; wild-area stage map (cave, forest, Facility)?
	jr nz, .wildArea
	farcall IsCemeteryMap    ; Z clear = cemetery; Z survives the farcall, a does not
	ret z
	ld a, [wRogueItem]
	ld c, 1
	jr BallRarityItemSlot
.wildArea
	ld hl, wRogueItem        ; four dw, item in the low byte; slots 2-5
	ld c, 2
.wildLoop
	ld a, [hli]
	inc hl
	push hl
	call BallRarityItemSlot
	pop hl
	inc c
	ld a, c
	cp 6
	jr c, .wildLoop
	ret
.rogueStage
	ld c, BALL_RARITY_REWARD_SLOT
.pokemonBalls
	ld a, d
	and a
	ret z
	ld hl, wRoguePokemon1
	ld b, 3
.rewardLoop
	ld a, [hli]
	push hl
	push bc
	call BallRaritySetSpeciesSlot
	pop bc
	pop hl
	inc c
	dec b
	jr nz, .rewardLoop
	ld a, c
	cp BALL_RARITY_REWARD_SLOT + 3
	jr z, .stageItem
	; Oak's Lab: no item ball. The Reward Room's mid-run item ball is slot 4
	; (BallRarityItemSlot leaves it alone while it is hidden).
	ldh a, [hCurMap]
	cp REWARD_ROOM
	ret nz
	ld a, [wRogueItem]
	ld c, 4
	jr BallRarityItemSlot
.stageItem
	ld a, [wRogueItem]
	ld c, BALL_RARITY_ITEM_SLOT
	; fall through

; a = item id, c = sprite slot. Colours slot c by the item's tier when that slot
; really shows a Poke Ball. Preserves c; clobbers a, b, d, e, hl.
BallRarityItemSlot:
	push bc
	ld d, a                  ; BallRarityIsBallSlot clobbers a
	call BallRarityIsBallSlot
	jr nz, .done
	ld a, d
	call BallRarityItemPalette
	pop bc
	push bc
	call BallRarityStoreSlot
.done
	pop bc
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

; a = tier 0-3 (0 = Poke Ball), c = sprite slot. Tier 0 is stored as the
; standard palette, the same one every unset ball gets.
BallRarityStoreSlot:
	and a
	jr nz, .store
	ld a, BALL_RARITY_STANDARD_PAL
.store
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

; a = item id -> a = palette 0-3 (the tier whose pool the roller draws it from),
; 0 when it is in no pool. Scans item_rarity.asm's own pools in tier order (the
; first hit wins), using the same per-pool lengths the roller draws from. The
; money pools are DEF'd with count 0, but the roller computes floor(rand * 0 / 256)
; = index 0 and still loads their single item, so they are length 1 here
; (PEARL standard, BIG_PEARL Great, NUGGET Ultra, BIG_NUGGET Master). Clobbers
; bc, de, hl.
BallRarityItemPalette:
	ld e, a
	ld d, 0                  ; entry 0-15, tier = entry / 4
	ld hl, BallRarityPools
.entry
	ld a, [hli]
	ld c, a
	ld a, [hli]
	ld b, a                  ; bc = pool
	ld a, [hli]              ; a = pool length
	and a
	jr z, .next
	push hl
	ld h, b
	ld l, c
	ld b, a                  ; b = remaining
.scan
	ld a, [hli]
	cp e
	jr z, .found
	dec b
	jr nz, .scan
	pop hl
.next
	inc d
	ld a, d
	cp 16
	jr c, .entry
	xor a
	ret
.found
	pop hl
	ld a, d
	srl a
	srl a
	ret

; One row per (tier, group): pool pointer and length. Tier order and group order
; (HEALING, STAT, TM, MONEY) are item_*ball_classes's; tools/pyboy_smoke/
; test_ball_rarity_sources.py checks both.
; dw pool, db length. A zero count is a one-item pool (see above).
MACRO ball_rarity_pool
	dw \1
	IF \2 == 0
		db 1
	ELSE
		db \2
	ENDC
ENDM

BallRarityPools:
	ball_rarity_pool healing_pokeball_class, NUM_HEALING_POKEBALL_CLASS
	ball_rarity_pool stat_pokeball_class, NUM_STAT_POKEBALL_CLASS
	ball_rarity_pool tm_pokeball_class, NUM_TM_POKEBALL_CLASS
	ball_rarity_pool money_pokeball_class, NUM_MONEY_POKEBALL_CLASS
	ball_rarity_pool healing_greatball_class, NUM_HEALING_GREATBALL_CLASS
	ball_rarity_pool stat_greatball_class, NUM_STAT_GREATBALL_CLASS
	ball_rarity_pool tm_greatball_class, NUM_TM_GREATBALL_CLASS
	ball_rarity_pool money_greatball_class, NUM_MONEY_GREATBALL_CLASS
	ball_rarity_pool healing_ultraball_class, NUM_HEALING_ULTRABALL_CLASS
	ball_rarity_pool stat_ultraball_class, NUM_STAT_ULTRABALL_CLASS
	ball_rarity_pool tm_ultraball_class, NUM_TM_ULTRABALL_CLASS
	ball_rarity_pool money_ultraball_class, NUM_MONEY_ULTRABALL_CLASS
	ball_rarity_pool healing_masterball_class, NUM_HEALING_MASTERBALL_CLASS
	ball_rarity_pool stat_masterball_class, NUM_STAT_MASTERBALL_CLASS
	ball_rarity_pool tm_masterball_class, NUM_TM_MASTERBALL_CLASS
	ball_rarity_pool money_masterball_class, NUM_MONEY_MASTERBALL_CLASS
ASSERT BANK(BallRarityPools) == BANK(healing_pokeball_class), \
	"BallRarityPools reads item_rarity.asm's pools with plain pointers"
