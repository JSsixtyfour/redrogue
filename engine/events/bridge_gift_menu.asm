; ============================================================================
; Bridge gift menu - data-driven rewrite.
;
; Each gift giver (identified by the map it lives in) owns one variable-length
; list of GiftEntry structs. A giver's list begins with a 1-byte count, then
; that many GiftEntry records:
;
;   GiftEntry (GIFT_ENTRY_SIZE bytes):
;     db  kind        ; GIFT_MON / GIFT_ITEM / GIFT_TEACH_MOVE / GIFT_SPECIAL /
;                      ; GIFT_MON_EVOLVE
;     dw  param       ; species / item / move id (low byte), OR routine addr,
;                      ; OR (GIFT_MON_EVOLVE) base species lo + custom gift
;                      ; finalizer id in the high byte
;     dw  nameptr     ; short menu name string (ignored for GIFT_MON_EVOLVE -
;                      ; its label is rendered dynamically from the resolved,
;                      ; possibly-evolved species; see BridgeResolveEvolveSpecies)
;     dw  descptr     ; description text (text_far)
;
; GIFT_SPECIAL points param at an arbitrary routine so a gift can do anything.
; GIFT_MON_EVOLVE gives the base species evolved to whatever it would be at
; the reward level (via EvolveMonByLevel), and shows that resolved species'
; real name in the menu, so the label always matches what's given.
; The giver is resolved from hCurMap (BridgeGiverMapTable) - no WRAM giver id.
; wGift1/2/3 hold the entry indices that were rolled for this visit.
; ============================================================================

DEF GIFT_MON        EQU 0
DEF GIFT_ITEM       EQU 1
DEF GIFT_TEACH_MOVE EQU 2
DEF GIFT_SPECIAL    EQU 3
DEF GIFT_MON_EVOLVE EQU 4  ; param lo = base species, param hi = BRIDGE_MON_FINALIZE_*
DEF GIFT_GLOBAL_EFFECT   EQU 5 ; param low = BRIDGE_EFFECT_*
DEF GIFT_SELECTED_EFFECT EQU 6 ; param low = BRIDGE_SELECTED_EFFECT_*

DEF GIFT_ENTRY_SIZE EQU 7

DEF BRIDGE_MON_FINALIZE_NONE       EQU 0
DEF BRIDGE_MON_FINALIZE_SPECIAL    EQU 1
DEF BRIDGE_MON_FINALIZE_FARFETCHD  EQU 2
DEF BRIDGE_MON_FINALIZE_QUICK_CLAW EQU 3
DEF BRIDGE_MON_FINALIZE_INTIMIDATE EQU 4
DEF BRIDGE_MON_FINALIZE_SUPER_FANG EQU 5
DEF BRIDGE_MON_FINALIZE_SPORE      EQU 6
DEF BRIDGE_MON_FINALIZE_EARTHQUAKE EQU 7
DEF BRIDGE_MON_FINALIZE_AMNESIA    EQU 8
DEF BRIDGE_MON_FINALIZE_DRAGON     EQU 9

MACRO gift_entry
; \1 = kind, \2 = param (id or routine), \3 = name ptr, \4 = desc ptr
	db \1
	dw \2
	dw \3
	dw \4
ENDM

DEF BRIDGE_MENU_MAX_OFFERED EQU 3
DEF BRIDGE_GIFT_ROLL_RETRIES EQU 32

; ---------------------------------------------------------------------------
; Roll 3 gift entry indices for the current giver into wGift1/wGift2/wGift3.
; Prefer eligible, distinct gifts. If fewer than 3 eligible gifts exist, a
; bounded retry limit repeats an already-selected eligible gift. Only a giver
; with zero eligible gifts falls back to the full list, because there is no
; eligible entry to repeat. The menu therefore cannot hang on an exhausted pool.
; Called (farcall) from each bridge room's setup script.
; ---------------------------------------------------------------------------
rogue_gift_randomized_batch::
	; Roll this visit's #MON RESCUE species (Mr. Fuji gift 2) into wRoguePokemon1.
	; Bridge rooms don't run rogue_pokemon_randomized_batch, so wRoguePokemon1
	; would otherwise hold garbage from the last procedural stage -> a glitchmon.
	; Safe to clobber: the stage this bridge exits to re-rolls wRoguePokemon1-3 on
	; load. Rolled here (once per room entry) so the description and the give agree
	; and it stays stable across menu open/close.
	; Random_Pokemon_Selection (not _Any) enforces the uniqueness guarantee via
	; AllSpeciesCheck - matches every other reward-mon roll in the game
	; (rogue_pokemon_randomized_batch, RogueRewardTradeRoll). Returns species in
	; d, which survives the farcall return (only a/b/c are clobbered by
	; Bankswitch's exit, not d/e/h/l - see project-farcall-home-clobbers-a).
	call GetRewardMonLevel
	ld [wCurEnemyLevel], a
	ld e, 0                     ; random class by odds; only d/e cross a farcall
	call Random                 ; primes hRandomAdd for the class-odds roll (HOME)
	farcall Random_Pokemon_Selection_Far  ; -> d = species
	ld a, d
	ld [wRoguePokemon1], a
	call GetGiverCount          ; a = number of gifts this giver has
	ld [wBuffer], a             ; gift count / Rangerandom range
	and a
	jr nz, .initSlots
	; Defensive guard for malformed/empty giver lists. Do not dereference entry 0.
	ld hl, wGift1
	ld b, BRIDGE_MENU_MAX_OFFERED
	ld a, $ff
.emptyLoop
	ld [hli], a
	dec b
	jr nz, .emptyLoop
	ret
.initSlots
	xor a
	ld [wBuffer + 1], a         ; output slot (0..2)
.nextSlot
	ld a, BRIDGE_GIFT_ROLL_RETRIES
	ld [wBuffer + 2], a
.tryEligible
	ld a, [wBuffer]
	ld c, a
	call Rangerandom
	ld [wBuffer + 3], a         ; candidate entry index
	call BridgeGiftIsEligible
	jr nc, .retry
	call BridgeGiftCandidateIsNew
	jr c, .accept
.retry
	ld hl, wBuffer + 2
	dec [hl]
	jr nz, .tryEligible
	; Random retries are only an optimization. Scan the full list before
	; declaring the eligible/distinct pool exhausted, so unlucky RNG can never
	; leak an owned gift into the menu.
	xor a
	ld [wBuffer + 4], a
.scanEligible
	ld a, [wBuffer + 4]
	ld b, a
	ld a, [wBuffer]
	cp b
	jr z, .eligibleExhausted
	ld a, b
	ld [wBuffer + 3], a
	call BridgeGiftIsEligible
	jr nc, .nextScan
	call BridgeGiftCandidateIsNew
	jr c, .accept
.nextScan
	ld hl, wBuffer + 4
	inc [hl]
	jr .scanEligible
.eligibleExhausted
	; If an eligible gift was already accepted, repeat one of those. This keeps
	; owned gifts filtered when the eligible pool contains only one or two entries.
	ld a, [wBuffer + 1]
	and a
	jr z, .noEligible
	ld c, a
	call Rangerandom
	ld e, a
	ld d, 0
	ld hl, wGift1
	add hl, de
	ld a, [hl]
	ld [wBuffer + 3], a
	jr .accept
.noEligible
	; Nothing eligible exists, so there is no valid entry to repeat. Preserve a
	; usable three-choice menu by drawing from the giver's complete list.
	ld a, [wBuffer]
	ld c, a
	call Rangerandom
	ld [wBuffer + 3], a
.accept
	ld a, [wBuffer + 1]
	ld e, a
	ld d, 0
	ld hl, wGift1
	add hl, de
	ld a, [wBuffer + 3]
	ld [hl], a
	ld hl, wBuffer + 1
	inc [hl]
	ld a, [hl]
	cp BRIDGE_MENU_MAX_OFFERED
	jr c, .nextSlot
	ret

; Return carry set when the candidate in wBuffer+3 is not already present in
; an earlier output slot. wBuffer+1 is the number of populated output slots.
BridgeGiftCandidateIsNew:
	ld a, [wBuffer + 1]
	and a
	jr z, .new
	ld b, a
	ld hl, wGift1
	ld a, [wBuffer + 3]
.loop
	cp [hl]
	jr z, .duplicate
	inc hl
	dec b
	jr nz, .loop
.new
	scf
	ret
.duplicate
	and a
	ret

; Return carry set when the candidate gift in wBuffer+3 is eligible.
; C1 filters owned TM/HM items and exact Pokemon species already present in
; the party/current box. Special-form Pokemon delivered through GIFT_SPECIAL
; require the same species plus BIT_SPECIAL_FORM; Mr. Fuji's generic rescue
; remains species-only. Other specials stay eligible.
BridgeGiftIsEligible:
	ld a, [wBuffer + 3]
	call GetGiftEntry
	ld a, [hli]                 ; kind
	cp GIFT_ITEM
	jr z, .item
	cp GIFT_MON
	jr z, .mon
	cp GIFT_MON_EVOLVE
	jr z, .monEvolve
	cp GIFT_GLOBAL_EFFECT
	jr z, .globalEffect
	cp GIFT_SPECIAL
	jr z, .special
.eligible
	scf
	ret
.item
	ld a, [hli]                 ; item id (param low)
	ld e, a
	ld a, [wCurItem]            ; aliases wCurPartySpecies: preserve it
	push af
	ld a, e
	ld [wCurItem], a
	farcall IsTMHMItem
	jr nc, .itemEligible
	farcall HasTMHM             ; Z = not owned, NZ = owned
	jr z, .itemEligible
	pop af
	ld [wCurItem], a
	and a                       ; owned: carry clear
	ret
.itemEligible
	pop af
	ld [wCurItem], a
	scf
	ret
.mon
	ld a, [hl]                  ; species (param low)
	jr BridgeSpeciesGiftEligible
.monEvolve
	ld a, [hli]                 ; base species (param low)
	call BridgeResolveEvolveSpecies
	ld e, [hl]                  ; finalizer id (param high)
	ld d, a                     ; resolved species survives the farcall in d
	ld a, e
	and a
	ld a, d
	jr nz, BridgeSpecialFormGiftEligible
	jr BridgeSpeciesGiftEligible
.globalEffect
	ld e, [hl]
	farcall BridgeHasGlobalEffect
	ccf                            ; eligible only while not already owned
	ret

.special
	; hl -> special routine pointer. Only specials whose primary reward is a
	; Pokemon participate in duplicate-species filtering.
	ld a, [hli]
	ld e, a
	ld a, [hl]
	ld d, a
	ld a, e
	cp LOW(BridgeCopyCatSuperDitto)
	jr nz, .notSuperDitto
	ld a, d
	cp HIGH(BridgeCopyCatSuperDitto)
	ld a, DITTO
	jr z, BridgeSpecialFormGiftEligible
.notSuperDitto
	ld a, e
	cp LOW(BridgeCaptainFarfetchd)
	jr nz, .notCaptainFarfetchd
	ld a, d
	cp HIGH(BridgeCaptainFarfetchd)
	ld a, FARFETCHD
	jr z, BridgeSpecialFormGiftEligible
.notCaptainFarfetchd
	ld a, e
	cp LOW(BridgeOakPikachu)
	jr nz, .notOakPikachu
	ld a, d
	cp HIGH(BridgeOakPikachu)
	ld a, PIKACHU
	jr z, BridgeSpecialFormGiftEligible
.notOakPikachu
	ld a, e
	cp LOW(BridgeMomSecondChance)
	jr nz, .notMomSecondChance
	ld a, d
	cp HIGH(BridgeMomSecondChance)
	jr nz, .notMomSecondChance
	farcall BridgeMomSecondChanceEligibleFar
	ret
.notMomSecondChance
	ld a, e
	cp LOW(BridgeMrFujiRescue)
	; Species Groups Phase 2 pushed .eligible just out of jr range from here -
	; jp is the same semantics, just no +/-128 byte limit.
	jp nz, .eligible
	ld a, d
	cp HIGH(BridgeMrFujiRescue)
	jp nz, .eligible
	ld a, [wRoguePokemon1]
	; fall through

; In: a = exact species that would be awarded.
; Out: carry set if absent; carry clear if already in party/current box.
BridgeSpeciesGiftEligible:
	ld d, a
	ld a, [wPartyCount]
	and a
	jr z, .box
	ld b, a
	ld hl, wPartySpecies
.partyLoop
	ld a, [hli]
	cp d
	jr z, .owned
	dec b
	jr nz, .partyLoop

.box
	ld a, [wBoxCount]
	and a
	jr z, .absent
	ld b, a
	ld hl, wBoxSpecies
.boxLoop
	ld a, [hli]
	cp d
	jr z, .owned
	dec b
	jr nz, .boxLoop
.absent
	scf
	ret
.owned
	and a
	ret

; In: a = species whose special form would be awarded.
; Out: carry set unless that species with BIT_SPECIAL_FORM is already present.
; A generic mon of the same species does not suppress the special gift.
BridgeSpecialFormGiftEligible:
	ld d, a
	ld a, [wPartyCount]
	ld e, a
	ld hl, wPartyMons
.partyLoop
	ld a, e
	and a
	jr z, .box
	ld a, [hl]
	cp d
	jr nz, .nextParty
	push hl
	ld bc, MON_CATCH_RATE
	add hl, bc
	bit BIT_SPECIAL_FORM, [hl]
	pop hl
	jr nz, .owned
.nextParty
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	dec e
	jr .partyLoop

.box
	ld a, [wBoxCount]
	ld e, a
	ld hl, wBoxMons
.boxLoop
	ld a, e
	and a
	jr z, .absent
	ld a, [hl]
	cp d
	jr nz, .nextBox
	push hl
	ld bc, MON_CATCH_RATE
	add hl, bc
	bit BIT_SPECIAL_FORM, [hl]
	pop hl
	jr nz, .owned
.nextBox
	ld bc, BOXMON_STRUCT_LENGTH
	add hl, bc
	dec e
	jr .boxLoop
.absent
	scf
	ret
.owned
	and a
	ret

; ---------------------------------------------------------------------------
BridgeGiftMenu::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	ld hl, BridgeGiftText
	call PrintText
; menu settings
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	call GetOfferedCount
	ld [wMaxMenuItem], a         ; max index = the NO THANKS slot
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	ld b, 8
	ld c, 18
	call TextBoxBorder
	call BridgePlaceGiftNames
	call UpdateSprites
	xor a
	call BridgePrintGiftDesc     ; description for the initially-hovered gift
.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
	ldh a, [hCurrentMenuItem]
	call BridgePrintGiftDesc
	jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	push af
	call GetOfferedCount
	ld b, a
	pop af                       ; a = selected menu index
	cp b
	jr z, .noChoice              ; NO THANKS
	call BridgeDoGift
	; fall through to clear BIT_NO_TEXT_DELAY before returning
.noChoice
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]
	ret

; ---------------------------------------------------------------------------
; Place the offered gift names (rows 4,6,8,...) then NO THANKS below them.
BridgePlaceGiftNames:
	call GetOfferedCount
	ld b, a                      ; b = offered count
	ld c, 0                      ; c = index
.loop
	ld a, c
	cp b
	jr z, .noThanks
	ld hl, wGift1
	ld a, c
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry (bc preserved)
	ld a, [hl]                   ; kind byte (offset 0)
	cp GIFT_MON_EVOLVE
	jr nz, .fixedName
	inc hl                       ; -> param low (offset 1) = base species
	ld a, [hl]
	push bc                      ; preserve index (c) + offered count (b)
	call BridgeResolveEvolveSpecies  ; a = resolved species
	ld [wNamedObjectIndex], a
	call GetMonName               ; name -> wNameBuffer (@-terminated)
	pop bc
	ld de, wNameBuffer
	jr .haveName
.fixedName
	inc hl
	inc hl
	inc hl                       ; -> name ptr field
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ld d, h
	ld e, l                      ; de = fixed name string
.haveName
	ld a, c
	add a
	add 4                        ; row = 4 + 2*index
	push bc
	push de
	call BridgeCoordRow2         ; hl = coord(2, row)
	pop de
	call PlaceString
	pop bc
	inc c
	jr .loop
.noThanks
	ld a, b
	add a
	add 4                        ; row = 4 + 2*offered
	call BridgeCoordRow2
	ld de, NoThanksText
	call PlaceString
	ret

; in: a = row ; out: hl = coord at column 2, given row (clobbers a, de)
BridgeCoordRow2:
	ld l, a
	ld h, 0
	ld d, h
	ld e, l                      ; de = row
	add hl, hl                   ; *2
	add hl, hl                   ; *4
	add hl, de                   ; *5
	add hl, hl                   ; *10
	add hl, hl                   ; *20 (SCREEN_WIDTH)
	ld de, wTileMap + 2
	add hl, de
	ret

; in: a = menu index ; prints that slot's description (or Empty for NO THANKS)
BridgePrintGiftDesc:
	push af
	call GetOfferedCount
	ld b, a
	pop af
	cp b
	jr z, .empty
	ld hl, wGift1
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry
	; #MON RESCUE (Mr. Fuji gift 2): its description text uses text_ram wNameBuffer,
	; so populate that buffer with the rolled species' name (wRoguePokemon1) before
	; rendering, so the bottom box shows the actual mon. Detect the gift by its
	; GIFT_SPECIAL routine address in the param field.
	push hl
	inc hl                       ; -> param low byte
	ld a, [hli]
	cp LOW(BridgeMrFujiRescue)
	jr nz, .notRescue
	ld a, [hl]                   ; param high byte
	cp HIGH(BridgeMrFujiRescue)
	jr nz, .notRescue
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName              ; -> wNameBuffer (@-terminated)
.notRescue
	pop hl
	ld bc, 5
	add hl, bc                   ; -> desc ptr field
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp PrintText
.empty
	ld hl, Empty
	jp PrintText

; ---------------------------------------------------------------------------
; in: a = selected menu index ; performs the chosen gift.
BridgeDoGift:
	ld hl, wGift1
	add l
	ld l, a
	ld a, [hl]                   ; entry index
	call GetGiftEntry            ; hl -> entry
	ld a, [hli]                  ; kind
	ld e, [hl]
	inc hl
	ld d, [hl]                   ; de = param
	cp GIFT_MON
	jr z, .mon
	cp GIFT_ITEM
	jr z, .item
	cp GIFT_TEACH_MOVE
	jr z, .teach
	cp GIFT_MON_EVOLVE
	jr z, .monEvolve
	cp GIFT_GLOBAL_EFFECT
	jr z, .globalEffect
	cp GIFT_SELECTED_EFFECT
	jr z, .selectedEffect
; GIFT_SPECIAL: de = routine address. Every special routine returns carry set
; only when its primary effect was applied.
	ld h, d
	ld l, e
	ld de, .checkSuccess
	push de
	jp hl
.mon
	ld a, e
	call BridgeGiveMon
	jr .checkSuccess
.item
	ld a, e
	call BridgeGiveItem
	jr .checkSuccess
.teach
	ld a, e
	call BridgeTeachMove
	jr .checkSuccess
.globalEffect
	farcall BridgeHasGlobalEffect
	jr c, .failed
	farcall BridgeGrantGlobalEffect
	scf
	jr .checkSuccess
.selectedEffect
	push de
	call BridgeSelectPartyMon
	pop de
	jr c, .failed
	farcall BridgeGrantSelectedEffect
	jr .checkSuccess
.monEvolve
	push de                      ; d = flag byte, e = base species
	ld a, e
	call BridgeResolveEvolveSpecies  ; a = resolved species
	call BridgeGiveMon           ; gives resolved species at reward level
	pop de                       ; d = finalizer id (pop doesn't touch carry)
	jr nc, .failed               ; nothing added (party+box full)
	ld e, d
	farcall BridgeFinalizeGiftMonFar
	jr .success
.checkSuccess
	jr nc, .failed
.success
	SetEvent EVENT_BRIDGE_RECEIVE_GIFT
	ld hl, BridgeByeText
	jp PrintText
.failed
	ret

; ---------------------------------------------------------------------------
; Generic gift helpers.

; in: a = species. Gives it at the current reward level.
BridgeGiveMon:
	push af
	call GetRewardMonLevel
	ld c, a                      ; level
	pop af
	ld b, a                      ; species
	call GivePokemon
	ret

; in: a = item id. Gives one and announces it.
BridgeGiveItem:
	push af                      ; preserve item id while seeding delivery sentinel
	ld a, $fe
	ldh [hSpriteOffset], a       ; distinguish key-item PC delivery from failure
	pop af
	push af
	ld b, a
	ld c, 1
	call GiveItem
	jr c, .received
	ldh a, [hSpriteOffset]
	cp $ff                       ; key item was successfully sent to PC storage
	jr z, .received
	pop af
	and a
	ret
.received
	pop af
	ld [wNamedObjectIndex], a   ; GiveItem clobbers it internally; restore for the name
	call ReceivedItem
	scf
	ret

; in: a = move id. Player picks a party mon; teaches it the move.
BridgeTeachMove:
	push af                      ; save move id
	call BridgeSelectPartyMon    ; carry = cancelled; hWhichPokemon = slot
	pop bc                       ; b = move id (carry unaffected by pop)
	jr nc, .selected
	and a
	ret
.selected
	ld a, b
	; fall through

; in: a = move id. Teaches it to the party mon at hWhichPokemon via the normal,
; rejectable LearnMove flow (used by the tutor gifts and the type-variant move).
BridgeTeachMoveToCurrent:
	ld [wMoveNum], a
	ld [wNamedObjectIndex], a
	call GetMoveName
	call CopyToStringBuffer
	ld a, [wLetterPrintingDelayFlags]
	push af
	xor a
	ld [wLetterPrintingDelayFlags], a
	predef LearnMove
	pop af
	ld [wLetterPrintingDelayFlags], a
	ld a, b                      ; LearnMove: b = 1 learned, b = 0 rejected
	and a
	ret z
	scf
	ret

; Opens the party menu for a selection. out: carry set = cancelled,
; hWhichPokemon = chosen slot.
BridgeSelectPartyMon:
	call SaveScreenTilesToBuffer2
	xor a
	ld [wListScrollOffset], a
	ld [wPartyMenuTypeOrMessageID], a
	ldh [hUpdateSpritesEnabled], a
	ld [wMenuItemToSwap], a
	call DisplayPartyMenu
	push af
	call GBPalWhiteOutWithDelay3
	call RestoreScreenTilesAndReloadTilePatterns
	call LoadGBPal
	pop af
	ret

; ---------------------------------------------------------------------------
; Giver resolution helpers (giver = current map).

; out: a = giver index (position in BridgeGiverMapTable). Assumes the current
; map is a bridge giver (only reached while inside a giver room).
GetGiverIndex:
	ldh a, [hCurMap]
	ld b, a
	ld hl, BridgeGiverMapTable
	ld c, 0
.loop
	ld a, [hli]
	cp b
	jr z, .found
	inc c
	jr .loop
.found
	ld a, c
	ret

; out: hl -> the giver's list (count byte first)
GetGiverListBase:
	call GetGiverIndex
	add a                        ; *2 (dw table)
	ld e, a
	ld d, 0
	ld hl, BridgeGiverLists
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

; out: a = number of gifts the current giver has
GetGiverCount:
	call GetGiverListBase
	ld a, [hl]
	ret

; out: a = 3 for any non-empty giver list, 0 for an invalid empty list.
; Short and eligibility-exhausted lists are padded with repeated entries.
GetOfferedCount:
	call GetGiverCount
	and a
	ret z
	ld a, BRIDGE_MENU_MAX_OFFERED
	ret

; in: a = entry index ; out: hl -> that GiftEntry. Preserves bc (clobbers de).
GetGiftEntry:
	push bc                      ; save caller's bc BEFORE GetGiverListBase clobbers it
	push af
	call GetGiverListBase
	inc hl                       ; skip count byte -> entry 0
	pop af
	ld bc, GIFT_ENTRY_SIZE
	call AddNTimes               ; hl += a * GIFT_ENTRY_SIZE
	pop bc
	ret

; ---------------------------------------------------------------------------
; GIFT_SPECIAL routines (must not print bye - the dispatcher does).

; Mr. Fuji "#MON RESCUE": give the run's rogue pokemon at reward level.
BridgeMrFujiRescue::
	ld a, [wRoguePokemon1]
	jp BridgeGiveMon

; Oak's Light-Ball PIKACHU: given as a BIT_SPECIAL_FORM mon (DOUBLE_ATK |
; DOUBLE_SPC | NO_EVOLVE per SpecialFormCaps).
BridgeOakPikachu::
	ld a, PIKACHU
	call BridgeGiveMon
	ret nc                       ; party AND box full -> nothing added
	call BridgeApplySpecialFormToNewMon
	scf
	ret

; Captain's always-crit FARFETCH'D (SpecialFormCaps -> ALWAYS_CRIT).
BridgeCaptainFarfetchd::
	ld a, FARFETCHD
	call BridgeGiveMon
	ret nc                       ; party AND box full -> nothing added
	ld e, BRIDGE_MON_FINALIZE_FARFETCHD
	farcall BridgeFinalizeGiftMonFar
	scf
	ret

; Oak's EXPERT TRAINING maxes stat experience for the whole current party.
BridgeOakExpertTraining::
	farcall BridgeOakExpertTrainingFar
	scf
	ret

; Mom's SECOND CHANCE restores KO Defiance's single charge, but only while
; that key item is in the active loadout and its charge has been spent.
BridgeMomSecondChance::
	farcall BridgeMomSecondChanceFar
	ret

; Copycat's SUPER DITTO: a BIT_SPECIAL_FORM DITTO with perfect DVs, maxed stat
; exp, and the SUPER_TRANSFORM + TRANSFORM move pair. Party and boxed delivery
; both receive the complete persistent form data.
BridgeCopyCatSuperDitto::
	ld a, DITTO
	call BridgeGiveMon
	ret nc                       ; party AND box full -> nothing added
	call BridgeGetNewMonStruct   ; de = struct base (party last OR box last)
	ld h, d
	ld l, e                      ; hl = struct base
	; perfect DVs
	push hl
	ld bc, MON_DVS
	add hl, bc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	pop hl
	; max stat exp (MON_HP_EXP..MON_SPC_EXP = 5 words = 10 bytes, contiguous)
	push hl
	ld bc, MON_HP_EXP
	add hl, bc
	ld c, 10
	ld a, $ff
.statExpLoop
	ld [hli], a
	dec c
	jr nz, .statExpLoop
	pop hl
	; moves = SUPER_TRANSFORM, TRANSFORM, 0, 0
	push hl
	ld bc, MON_MOVES
	add hl, bc
	ld a, SUPER_TRANSFORM
	ld [hli], a
	ld a, TRANSFORM
	ld [hli], a
	xor a
	ld [hli], a
	ld [hl], a
	pop hl
	; PP for the new moveset (predef LoadMovePPs: hl = moves, de = PP - 1)
	push hl                      ; [struct base]
	ld bc, MON_MOVES
	add hl, bc                   ; hl = moves ptr
	pop de                       ; de = struct base
	push hl                      ; [moves ptr]
	ld h, d
	ld l, e
	ld bc, MON_PP - 1
	add hl, bc
	ld d, h
	ld e, l                      ; de = PP - 1
	pop hl                       ; hl = moves ptr
	predef LoadMovePPs
	call BridgeApplySpecialFormToNewMon
	; party: recalc stored stats now. box: skip - box mons store no stats;
	; they recompute from box level + these maxed DVs/stat-exp on withdrawal.
	ld a, [wAddedToParty]
	and a
	jr nz, .partyStats
	scf
	ret
.partyStats
	call BridgeGetNewMonStruct   ; de = party struct base
	ld h, d
	ld l, e
	call BridgeRecalcStats
	scf
	ret

; Mr. Fuji's GENE SPLICING: max out a chosen party mon's DVs, then recalc.
BridgeMrFujiGeneSplice::
	call BridgeSelectPartyMon
	jr c, .cancel
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes               ; hl = selected struct base
	push hl
	ld bc, MON_DVS
	add hl, bc
	ld a, $ff
	ld [hli], a
	ld [hl], a
	pop hl
	call BridgeRecalcStats
	scf
	ret
.cancel
	and a
	ret

; Bill's DUPLICATE TRICK: pick a party mon, give an exact clone through the
; normal GivePokemon flow. Party-full clones fall back to a fresh same-species
; mon in the box (an exact copy needs the party struct, which the box lacks).
BridgeBillDuplicate::
	call BridgeSelectPartyMon
	jr c, .failed
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes               ; hl = source struct base
	ld a, [hl]
	ld b, a                      ; b = species
	push hl                      ; save source base across GivePokemon
	ld de, MON_LEVEL
	add hl, de
	ld a, [hl]
	ld c, a                      ; c = level
	call GivePokemon             ; fresh mon (party or box) + standard messaging
	pop hl                       ; hl = source base (party structs don't move)
	jr nc, .failed
	ld a, [wAddedToParty]
	and a
	jr nz, .copyPartyStruct
	scf                          ; boxed -> fresh same-species mon, still delivered
	ret
.copyPartyStruct
	push hl                      ; source base
	call GetLastPartyMonStruct   ; hl = dest (new last slot)
	pop de                       ; de = source base
	; CopyData copies [hl] -> [de]; we need source -> dest, so swap hl<->de.
	ld a, h
	ld h, d
	ld d, a
	ld a, l
	ld l, e
	ld e, a                      ; hl = source, de = dest
	ld bc, PARTYMON_STRUCT_LENGTH
	call CopyData
	scf
	ret
.failed
	and a
	ret

; Bill's MAD SCIENCE: fuse two party mons (func_fusion.asm handles the whole
; selection UI, guards, and messaging).
BridgeBillFusion::
	ld a, [wPartyCount]
	push af                      ; successful fusion removes exactly one party mon
	farcall CreateFusion
	pop bc                       ; b = party count before CreateFusion
	push bc                      ; preserve it across sprite restoration
	; CreateFusion's party menus ClearSprites and it never reloads sprite tile
	; patterns (only map/tileset tiles), so the overworld sprites stay erased
	; until the party menu is reopened. Restore them here the same way the other
	; party-menu gifts do (RestoreScreenTilesAndReloadTilePatterns). All three
	; calls are HOME, safe to plain-call from this ROMX bank.
	ld a, $1
	ldh [hUpdateSpritesEnabled], a
	call ReloadMapSpriteTilePatterns
	call UpdateSprites
	pop bc
	ld a, [wPartyCount]
	cp b
	jr z, .failed
	scf
	ret
.failed
	and a
	ret

; Captain's WATER type variant: adds WATER as a chosen party mon's secondary
; type (blue palette, water STAB/defense). Fossil's is the ROCK equivalent.
BridgeCaptainWaterVariant::
	ld e, WATER
	jr BridgeApplyTypeVariantGift

BridgeFossilRockVariant::
	ld e, ROCK
	; fall through

; in: e = target type. Player picks a party mon; if it doesn't already have
; that type (type1 or type2), flags it as a type variant, sets MON_TYPE2,
; announces the new type, and offers a random move of that type (rejectable,
; via the normal LearnMove flow). Rejects with a message if the mon already has
; the type; silent on cancel.
BridgeApplyTypeVariantGift:
	ld a, e
	push af                       ; save target type across the menu
	call BridgeSelectPartyMon     ; carry = cancel, hWhichPokemon = slot
	pop bc                        ; b = target type (pop preserves carry)
	jr c, .failed
	ldh a, [hWhichPokemon]
	push bc                       ; save target type across AddNTimes
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes                ; hl = struct base
	pop bc                        ; b = target type
	push hl
	push bc
	ld de, MON_TYPE1
	add hl, de
	ld a, [hli]                   ; type1
	cp b
	jr z, .already
	ld a, [hl]                    ; type2 (MON_TYPE2 follows MON_TYPE1)
	cp b
	jr z, .already
	pop bc                        ; b = target type
	pop hl                        ; hl = struct base
	; apply the type variant inline - pure WRAM writes. NOT a farcall: Bankswitch
	; would clobber the type in `a` on the way in (project-farcall-home-clobbers-a),
	; which is exactly the bug that made this write garbage before.
	push hl                       ; save struct base
	ld de, MON_CATCH_RATE
	add hl, de
	set BIT_TYPE_VARIANT, [hl]
	pop hl                        ; struct base
	ld de, MON_TYPE2
	add hl, de
	ld [hl], b                    ; MON_TYPE2 = target type
	; announce the new type and offer a matching move (b = target type)
	ld a, b
	cp WATER
	jr z, .water
; ROCK
	ld hl, BridgeRockVariantText
	call PrintText
	ld hl, BridgeRockMovePool
	call BridgeTeachRandomMoveFromPool
	scf                          ; type change succeeds even if bonus move is refused
	ret
.water
	ld hl, BridgeWaterVariantText
	call PrintText
	ld hl, BridgeWaterMovePool
	call BridgeTeachRandomMoveFromPool
	scf                          ; type change succeeds even if bonus move is refused
	ret
.already
	pop bc
	pop hl
	ld hl, BridgeTypeVariantFailText
	call PrintText
.failed
	and a
	ret

; in: hl = move pool (count byte, then that many move ids). Picks one at random
; and teaches it to the current party mon (hWhichPokemon) via the normal,
; rejectable LearnMove flow.
BridgeTeachRandomMoveFromPool:
	ld a, [hli]                   ; count -> hl now at first move id
	ld c, a
	call Rangerandom              ; a = 0..count-1 (hl, bc preserved)
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]                    ; chosen move id
	jp BridgeTeachMoveToCurrent

BridgeRockMovePool:
	db 2
	db ROCK_SLIDE, ROCK_THROW
BridgeWaterMovePool:
	db 4
	db SURF, BUBBLEBEAM, WATER_GUN, HYDRO_PUMP

; ---------------------------------------------------------------------------
; Shared special-gift helpers.

; Flag the just-given mon (party OR box) as a special form. Its per-species
; caps come from SpecialFormCaps (func_special_form.asm). Only call after a
; GivePokemon that returned CARRY (success) - see the `ret nc` guards below.
BridgeApplySpecialFormToNewMon:
	call BridgeGetNewMonStruct
	farcall ApplySpecialForm
	scf
	ret

; out: de = struct base of the mon GivePokemon most recently added - the last
; party slot if it went to the party, else the FRONT box slot (wBoxMon1), where
; SendNewMonToBox front-inserts it. (An earlier version used the last box slot and
; flagged the wrong mon on a non-empty box - confirmed in-emulator.) box_struct
; shares MON_CATCH_RATE/MON_TYPE2/MON_MOVES/etc. offsets with party_struct, so
; the Apply* routines work on either.
BridgeGetNewMonStruct:
	ld a, [wAddedToParty]
	and a
	jr z, .boxed
	call GetLastPartyMonStruct   ; hl = last party slot
	ld d, h
	ld e, l
	ret
.boxed
	; SendNewMonToBox front-inserts the new mon at slot 0 (wBoxMon1); the old
	; "last slot" math flagged the wrong mon (confirmed in-emulator: a boxed
	; gift flagged the last box mon, not the one just added).
	ld de, wBoxMon1
	ret

; in:  a = base species
; out: a = species after level-based evolution at this giver's reward level
;      (base species itself if it doesn't evolve at that level).
; Preserves wCurPartySpecies (EvolveMonByLevel uses it as scratch/output).
; Clobbers af, bc, de, hl (and wCurEnemyLevel/wMonHeader as EvolveMonByLevel does).
BridgeResolveEvolveSpecies:
	ld e, a
	farcall BridgeResolveEvolveSpeciesFar
	ld a, e
	ret

; Farcall-safe reward-level adapter. Bankswitch destroys a on return.
GetBridgeRewardMonLevelFar::
	call GetRewardMonLevel
	ld e, a
	ret

; out: hl = struct base of the last (most-recently-added) party mon.
GetLastPartyMonStruct:
	ld a, [wPartyCount]
	dec a
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	jp AddNTimes

; Recalculate a party mon's stats in place from its stored DVs + stat exp, then
; refill current HP to the new max. in: hl = struct base.
BridgeRecalcStats:
	ld d, h
	ld e, l
	farcall BridgeRecalcStatsFar
	ret

; ---------------------------------------------------------------------------
ReceivedItem::
	call GetItemName
	ld hl, ReceivedItemText
	call PrintText
	ret

; ---------------------------------------------------------------------------
; Text.
BridgeGiftText:
	text_far _BridgeGiftText
	text_end

BridgeByeText:
	text_far _BridgeByeText
	text_end

ReceivedItemText:
	text_far _ReceivedItemText
	text_end

BridgeTypeVariantFailText:
	text_far _BridgeTypeVariantFailText
	text_end

BridgeWaterVariantText:
	text_far _BridgeWaterVariantText
	text_end

BridgeRockVariantText:
	text_far _BridgeRockVariantText
	text_end

Empty:
	text_far _Empty
	text_end

; ---------------------------------------------------------------------------
; Giver dispatch tables. BridgeGiverMapTable and BridgeGiverLists are indexed
; in lockstep - add a map + its list to both when adding a bridge room.
BridgeGiverMapTable:
	db COPYCATS_HOUSE_2F
	db BILLS_HOUSE
	db MR_FUJIS_HOUSE
	db SS_ANNE_CAPTAINS_ROOM
	db CINNABAR_LAB_FOSSIL_ROOM
	db POKEMON_FAN_CLUB
	db WARDENS_HOUSE
	db VIRIDIAN_SCHOOL_HOUSE
	db VIRIDIAN_NICKNAME_HOUSE
	db CERULEAN_TRASHED_HOUSE
	db REDS_HOUSE_1F
	db LAVENDER_CUBONE_HOUSE
	db CERULEAN_TRADE_HOUSE
	db OAKS_LAB

BridgeGiverLists:
	dw CopyCatGiftList
	dw BillGiftList
	dw MrFujiGiftList
	dw CaptainGiftList
	dw FossilScientistGiftList
	dw FanClubChairmanGiftList
	dw WardenGiftList
	dw SchoolCooltrainerGiftList
	dw OldManGiftList
	dw OfficerJennyGiftList
	dw RedsHouseMomGiftList
	dw IgaGiftList
	dw TradeHouseGrannyGiftList
	dw OaksLabOakGiftList

; ---------------------------------------------------------------------------
CopyCatGiftList:
	db 7
	gift_entry GIFT_SPECIAL,    BridgeCopyCatSuperDitto, CopyCatGift1_Text, CopyCatGift1_Desc
	gift_entry GIFT_ITEM,       TM_MIMIC,       CopyCatGift2_Text, CopyCatGift2_Desc
	gift_entry GIFT_ITEM,       TM_PSYCHIC_M,   CopyCatGift3_Text, CopyCatGift3_Desc
	gift_entry GIFT_TEACH_MOVE, MIRROR_MOVE,    CopyCatGift4_Text, CopyCatGift4_Desc
	gift_entry GIFT_TEACH_MOVE, TRANSFORM,      CopyCatGift5_Text, CopyCatGift5_Desc
	gift_entry GIFT_ITEM,       NUGGET,         CopyCatGift6_Text, CopyCatGift6_Desc
	gift_entry GIFT_ITEM,       TM_SUBSTITUTE,  CopyCatGift7_Text, CopyCatGift7_Desc

BillGiftList:
	db 7
	gift_entry GIFT_SPECIAL, BridgeBillFusion,    BillGift1_Text, BillGift1_Desc
	gift_entry GIFT_MON,  EEVEE,       BillGift2_Text, BillGift2_Desc
	gift_entry GIFT_MON,  JOLTEON,     BillGift3_Text, BillGift3_Desc
	gift_entry GIFT_MON,  FLAREON,     BillGift4_Text, BillGift4_Desc
	gift_entry GIFT_MON,  VAPOREON,    BillGift5_Text, BillGift5_Desc
	gift_entry GIFT_SPECIAL, BridgeBillDuplicate, BillGift6_Text, BillGift6_Desc
	gift_entry GIFT_ITEM, TM_THUNDERBOLT, BillGift7_Text, BillGift7_Desc

MrFujiGiftList:
	db 8
	gift_entry GIFT_ITEM,       POKE_FLUTE,         MrFujiGift1_Text, MrFujiGift1_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiRescue, MrFujiGift2_Text, MrFujiGift2_Desc
	gift_entry GIFT_MON_EVOLVE, CUBONE | (1 << 8),      MrFujiGift3_Text, MrFujiGift3_Desc
	gift_entry GIFT_SPECIAL,    BridgeMrFujiGeneSplice, MrFujiGift4_Text, MrFujiGift4_Desc
	gift_entry GIFT_TEACH_MOVE, NIGHT_SHADE,        MrFujiGift5_Text, MrFujiGift5_Desc
	gift_entry GIFT_TEACH_MOVE, CONFUSE_RAY,        MrFujiGift6_Text, MrFujiGift6_Desc
	gift_entry GIFT_TEACH_MOVE, LICK,               MrFujiGift7_Text, MrFujiGift7_Desc
	gift_entry GIFT_ITEM,       M_GENE,             MrFujiGift8_Text, MrFujiGift8_Desc

CaptainGiftList:
	db 9
	gift_entry GIFT_ITEM,    HM_CUT,    CaptainGift1_Text, CaptainGift1_Desc
	gift_entry GIFT_MON_EVOLVE, TENTACOOL, NoThanksText, CaptainGift2_Desc
	gift_entry GIFT_SPECIAL, BridgeCaptainWaterVariant, CaptainGift3_Text, CaptainGift3_Desc
	gift_entry GIFT_SPECIAL, BridgeCaptainFarfetchd, CaptainGift4_Text, CaptainGift4_Desc
    gift_entry GIFT_MON,     LAPRAS, CaptainGift5_Text, CaptainGift5_Desc
    gift_entry GIFT_ITEM,    HM_SURF,    CaptainGift6_Text, CaptainGift6_Desc
    gift_entry GIFT_TEACH_MOVE, CRABHAMMER, CaptainGift7_Text, CaptainGift7_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_CRITICAL_RATE, CaptainGift8_Text, CaptainGift8_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_CRITICAL_DAMAGE, CaptainGift9_Text, CaptainGift9_Desc

FossilScientistGiftList:
	db 8
	gift_entry GIFT_MON_EVOLVE, OMANYTE, NoThanksText, FossilGift1_Desc
	gift_entry GIFT_SPECIAL, BridgeFossilRockVariant, FossilGift2_Text, FossilGift2_Desc
    gift_entry GIFT_MON_EVOLVE, KABUTO, NoThanksText, FossilGift4_Desc
    gift_entry GIFT_MON,     AERODACTYL, FossilGift5_Text, FossilGift5_Desc
    gift_entry GIFT_MON,     PORYGON, FossilGift6_Text, FossilGift6_Desc
    gift_entry GIFT_ITEM,    TM_METRONOME, FossilGift7_Text, FossilGift7_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_SHRINK_RAY, FossilGift8_Text, FossilGift8_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_GROWTH_RAY, FossilGift9_Text, FossilGift9_Desc

FanClubChairmanGiftList:
	db 8
	gift_entry GIFT_ITEM, PP_UP, FanClubGift1_Text, FanClubGift1_Desc
	gift_entry GIFT_MON_EVOLVE,  PONYTA, FanClubGift2_Text, FanClubGift2_Desc
	gift_entry GIFT_ITEM, RARE_CANDY,   FanClubGift3_Text, FanClubGift3_Desc
    gift_entry GIFT_MON_EVOLVE,  DROWZEE, FanClubGift4_Text, FanClubGift4_Desc
    gift_entry GIFT_MON_EVOLVE,  SPEAROW, FanClubGift5_Text, FanClubGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_CUTE_BOOST, FanClubGift6_Text, FanClubGift6_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_REWARD_RARITY, FanClubGift7_Text, FanClubGift7_Desc
	gift_entry GIFT_ITEM, MIST_STONE, FanClubGift8_Text, FanClubGift8_Desc

WardenGiftList:
	db 7
	gift_entry GIFT_ITEM, HM_STRENGTH, WardenGift1_Text, WardenGift1_Desc
	gift_entry GIFT_MON,  KANGASKHAN,  WardenGift2_Text, WardenGift2_Desc
	gift_entry GIFT_ITEM, HM_SURF,  WardenGift3_Text, WardenGift3_Desc
    gift_entry GIFT_MON,  TAUROS,  WardenGift4_Text, WardenGift4_Desc
    gift_entry GIFT_ITEM, BIG_NUGGET,  WardenGift5_Text, WardenGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_ATTACK_BOOST, WardenGift6_Text, WardenGift6_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_FLINCH, WardenGift7_Text, WardenGift7_Desc

SchoolCooltrainerGiftList:
	db 8
	gift_entry GIFT_TEACH_MOVE, SHARPEN, SchoolGift1_Text, SchoolGift1_Desc
	gift_entry GIFT_ITEM,       CALCIUM,     SchoolGift2_Text, SchoolGift2_Desc
	gift_entry GIFT_ITEM,       TM_DOUBLE_TEAM,  SchoolGift3_Text, SchoolGift3_Desc
	gift_entry GIFT_MON_EVOLVE, NIDORAN_M, NoThanksText, SchoolGift4_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_STAB_DAMAGE, SchoolGift5_Text, SchoolGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_SUPER_EFFECTIVE, SchoolGift6_Text, SchoolGift6_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_REPEAT, SchoolGift7_Text, SchoolGift7_Desc
	gift_entry GIFT_MON_EVOLVE, NIDORAN_F | (BRIDGE_MON_FINALIZE_QUICK_CLAW << 8), NoThanksText, SchoolGift8_Desc

OldManGiftList:
	db 8
	gift_entry GIFT_MON_EVOLVE,  WEEDLE,    OldManGift1_Text, OldManGift1_Desc
	gift_entry GIFT_MON_EVOLVE,  RATTATA,   OldManGift2_Text, OldManGift2_Desc
	gift_entry GIFT_ITEM, TM_REST, OldManGift3_Text, OldManGift3_Desc
	gift_entry GIFT_ITEM, TM_THUNDER_WAVE, OldManGift4_Text, OldManGift4_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_NO_RECOIL, OldManGift5_Text, OldManGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_SPEED_BOOST, OldManGift6_Text, OldManGift6_Desc
	gift_entry GIFT_TEACH_MOVE, DIZZY_PUNCH, OldManGift7_Text, OldManGift7_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_STATUS_CHANCE, OldManGift8_Text, OldManGift8_Desc

OfficerJennyGiftList:
	db 8
	gift_entry GIFT_ITEM, LEMONADE, TrashedGift1_Text, TrashedGift1_Desc
	gift_entry GIFT_MON_EVOLVE,  SQUIRTLE, TrashedGift2_Text, TrashedGift2_Desc
	gift_entry GIFT_ITEM, TM_BODY_SLAM, TrashedGift3_Text, TrashedGift3_Desc
	gift_entry GIFT_ITEM, TM_TAKE_DOWN, TrashedGift4_Text, TrashedGift4_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_ACCURACY, TrashedGift5_Text, TrashedGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_DEFENSE_BOOST, TrashedGift6_Text, TrashedGift6_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_BODY_ARMOR, TrashedGift7_Text, TrashedGift7_Desc
	gift_entry GIFT_MON_EVOLVE, GROWLITHE | (BRIDGE_MON_FINALIZE_INTIMIDATE << 8), NoThanksText, TrashedGift8_Desc

RedsHouseMomGiftList:
	db 9
	gift_entry GIFT_ITEM, FULL_RESTORE, MomGift1_Text, MomGift1_Desc
	gift_entry GIFT_MON,  CHANSEY,        MomGift2_Text, MomGift2_Desc
	gift_entry GIFT_ITEM, FULL_HEAL,   MomGift3_Text, MomGift3_Desc
	gift_entry GIFT_TEACH_MOVE, RECOVER, MomGift4_Text, MomGift4_Desc
	gift_entry GIFT_ITEM, TM_SOFTBOILED, MomGift5_Text, MomGift5_Desc
	gift_entry GIFT_ITEM, TM_REST, MomGift6_Text, MomGift6_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_HEALING, MomGift7_Text, MomGift7_Desc
	gift_entry GIFT_MON_EVOLVE, MR_MIME, MomGift8_Text, MomGift8_Desc
	gift_entry GIFT_SPECIAL, BridgeMomSecondChance, MomGift9_Text, MomGift9_Desc

IgaGiftList:
	db 8
	gift_entry GIFT_MON_EVOLVE, EKANS | (BRIDGE_MON_FINALIZE_SUPER_FANG << 8), NoThanksText, IgaGift1_Desc
	gift_entry GIFT_MON_EVOLVE,  GRIMER, IgaGift2_Text, IgaGift2_Desc
	gift_entry GIFT_ITEM, TM_TOXIC, IgaGift3_Text, IgaGift3_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_TOXIC_POISON, IgaGift4_Text, IgaGift4_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_POISON_IMMUNITY, IgaGift5_Text, IgaGift5_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_LIFE_ORB, IgaGift6_Text, IgaGift6_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_EVASION, IgaGift7_Text, IgaGift7_Desc
	gift_entry GIFT_TEACH_MOVE, POISON_GAS, IgaGift8_Text, IgaGift8_Desc

TradeHouseGrannyGiftList: ; Flora's grotto roster (legacy label kept for dispatch ABI).
	db 9
	gift_entry GIFT_ITEM, NUGGET,     TradeHouseGift1_Text, TradeHouseGift1_Desc
	gift_entry GIFT_MON_EVOLVE, ODDISH | (BRIDGE_MON_FINALIZE_SPORE << 8), NoThanksText, TradeHouseGift2_Desc
	gift_entry GIFT_ITEM, MOON_STONE, TradeHouseGift3_Text, TradeHouseGift3_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_DRAINING, TradeHouseGift4_Text, TradeHouseGift4_Desc
	gift_entry GIFT_SELECTED_EFFECT, BRIDGE_SELECTED_EFFECT_STATUS_IMMUNITY, TradeHouseGift5_Text, TradeHouseGift5_Desc
	gift_entry GIFT_TEACH_MOVE, LEECH_SEED, TradeHouseGift6_Text, TradeHouseGift6_Desc
	gift_entry GIFT_ITEM, TM_MEGA_DRAIN, TradeHouseGift7_Text, TradeHouseGift7_Desc
	gift_entry GIFT_TEACH_MOVE, PETAL_DANCE, TradeHouseGift8_Text, TradeHouseGift8_Desc
	gift_entry GIFT_ITEM, LEAF_STONE, TradeHouseGift9_Text, TradeHouseGift9_Desc

OaksLabOakGiftList:
	db 7
	gift_entry GIFT_SPECIAL, BridgeOakExpertTraining, OaksLabGift7_Text, OaksLabGift7_Desc
	gift_entry GIFT_MON_EVOLVE, BULBASAUR | (BRIDGE_MON_FINALIZE_EARTHQUAKE << 8), NoThanksText, OaksLabGift1_Desc
	gift_entry GIFT_MON_EVOLVE, SQUIRTLE | (BRIDGE_MON_FINALIZE_AMNESIA << 8), NoThanksText, OaksLabGift2_Desc
	gift_entry GIFT_MON_EVOLVE, CHARMANDER | (BRIDGE_MON_FINALIZE_DRAGON << 8), NoThanksText, OaksLabGift3_Desc
	gift_entry GIFT_SPECIAL, BridgeOakPikachu, OaksLabGift4_Text, OaksLabGift4_Desc
	gift_entry GIFT_MON, EEVEE, OaksLabGift5_Text, OaksLabGift5_Desc
	gift_entry GIFT_GLOBAL_EFFECT, BRIDGE_EFFECT_MONEY, OaksLabGift6_Text, OaksLabGift6_Desc

; ---------------------------------------------------------------------------
; Menu name strings.
CopyCatGift1_Text: db "SUPER DITTO@"
CopyCatGift2_Text: db "MIMIC TM@"
CopyCatGift3_Text: db "PSYCHIC TM@"
CopyCatGift4_Text: db "MIRROR MOVE TUTOR@"
CopyCatGift5_Text: db "TRANSFORM TUTOR@"
CopyCatGift6_Text: db "NUGGET@"
CopyCatGift7_Text: db "SUBSTITUTE TM@"

BillGift1_Text: db "MAD SCIENCE@"
BillGift2_Text: db "EEVEE@"
BillGift3_Text: db "JOLTEON@"
BillGift4_Text: db "FLAREON@"
BillGift5_Text: db "VAPOREON@"
BillGift6_Text: db "DUPLICATE TRICK@"
BillGift7_Text: db "THUNDERBOLT TM@"

MrFujiGift1_Text: db "POKé FLUTE@"
MrFujiGift2_Text: db "#MON RESCUE@"
MrFujiGift3_Text: db "THICK CLUB@" ; unused - GIFT_MON_EVOLVE renders the label dynamically
MrFujiGift4_Text: db "GENE SPLICING@"
MrFujiGift5_Text: db "NIGHTSHADE TUTOR@"
MrFujiGift6_Text: db "CONFUSE RAY TUTOR@"
MrFujiGift7_Text: db "LICK TUTOR@"
MrFujiGift8_Text: db "M.GENE@"

CaptainGift1_Text: db "CUT HM@"
CaptainGift3_Text: db "SEA BLESSING@"
CaptainGift4_Text: db "LUCKY DUCK@"
CaptainGift5_Text: db "LAPRAS@"
CaptainGift6_Text: db "SURF HM@"
CaptainGift7_Text: db "CRABHAMMER TUTOR@"
CaptainGift8_Text: db "CRIT TRAINING@"
CaptainGift9_Text: db "CRIT MASTERY@"

FossilGift2_Text: db "FOSSILIZATION@"
FossilGift3_Text: db "FIRE STONE@"
FossilGift5_Text: db "AERODACTYL@"
FossilGift6_Text: db "PORYGON@"
FossilGift7_Text: db "METRONOME TM@"
FossilGift8_Text: db "SHRINK RAY@"
FossilGift9_Text: db "GROWTH RAY@"

FanClubGift1_Text: db "PP UP@"
FanClubGift2_Text: db "PONYTA@"
FanClubGift3_Text: db "RARE CANDY@"
FanClubGift4_Text: db "DROWZEE@"
FanClubGift5_Text: db "SPEAROW@"
FanClubGift6_Text: db "CUTE BOOST@"
FanClubGift7_Text: db "BETTER RARITY@"
FanClubGift8_Text: db "MIST STONE@"

WardenGift1_Text: db "STRENGTH HM@"
WardenGift2_Text: db "KANGASKHAN@"
WardenGift3_Text: db "SURF HM@"
WardenGift4_Text: db "TAUROS@"
WardenGift5_Text: db "BIG NUGGET@"
WardenGift6_Text: db "ATTACK BADGE@"
WardenGift7_Text: db "STAGGERING BLOWS@"

SchoolGift1_Text: db "SHARPEN TUTOR@"
SchoolGift2_Text: db "CALCIUM@"
SchoolGift3_Text: db "DOUBLE TEAM TM@"
SchoolGift5_Text: db "STAB MASTERY@"
SchoolGift6_Text: db "TYPE EXPERT@"
SchoolGift7_Text: db "REPEAT!@"

OldManGift1_Text: db "WEEDLE@"
OldManGift2_Text: db "RATTATA@"
OldManGift3_Text: db "REST TM@"
OldManGift4_Text: db "THUNDER WAVE TM@"
OldManGift5_Text: db "DULLED SENSES@"
OldManGift6_Text: db "COFFEE BOOST@"
OldManGift7_Text: db "DIZZY PUNCH@"
OldManGift8_Text: db "SPIKED DRINK@"

TrashedGift1_Text: db "LEMONADE@"
TrashedGift2_Text: db "SQUIRTLE@"
TrashedGift3_Text: db "BODY SLAM TM@"
TrashedGift4_Text: db "TAKE DOWN TM@"
TrashedGift5_Text: db "TARGET PRACTICE@"
TrashedGift6_Text: db "DEFENSE BADGE@"
TrashedGift7_Text: db "BODY ARMOR@"

MomGift1_Text: db "FULL RESTORE@"
MomGift2_Text: db "CHANSEY@"
MomGift3_Text: db "FULL HEAL@"
MomGift4_Text: db "RECOVER TUTOR@"
MomGift5_Text: db "SOFTBOILED TM@"
MomGift6_Text: db "REST TM@"
MomGift7_Text: db "NURTURING CARE@"
MomGift8_Text: db "MR.MIME@"
MomGift9_Text: db "SECOND CHANCE@"

IgaGift2_Text: db "GRIMER@"
IgaGift3_Text: db "TOXIC TM@"
IgaGift4_Text: db "DEADLY VENOM@"
IgaGift5_Text: db "POISON WARD@"
IgaGift6_Text: db "LIFE ORB@"
IgaGift7_Text: db "SHADOW STEP@"
IgaGift8_Text: db "POISON GAS@"

TradeHouseGift1_Text: db "NUGGET@"
TradeHouseGift3_Text: db "MOON STONE@"
TradeHouseGift4_Text: db "VERDANT DRAIN@"
TradeHouseGift5_Text: db "IMMUNITY@"
TradeHouseGift6_Text: db "LEECH SEED@"
TradeHouseGift7_Text: db "MEGA DRAIN TM@"
TradeHouseGift8_Text: db "PETAL DANCE@"
TradeHouseGift9_Text: db "LEAF STONE@"

OaksLabGift4_Text: db "LIGHT BALL PIKA@"
OaksLabGift5_Text: db "EEVEE@"
OaksLabGift6_Text: db "RESEARCH GRANT@"
OaksLabGift7_Text: db "EXPERT TRAINING@"

; ---------------------------------------------------------------------------
; Descriptions.
CopyCatGift1_Desc:
	text_far _CopyCatGift1Desc
	text_end
CopyCatGift2_Desc:
	text_far _CopyCatGift2Desc
	text_end
CopyCatGift3_Desc:
	text_far _CopyCatGift3Desc
	text_end
CopyCatGift4_Desc:
	text_far _CopyCatGift4Desc
	text_end
CopyCatGift5_Desc:
	text_far _CopyCatGift5Desc
	text_end
CopyCatGift6_Desc:
	text_far _CopyCatGift6Desc
	text_end
CopyCatGift7_Desc:
	text_far _CopyCatGift7Desc
	text_end

BillGift1_Desc:
	text_far _BillGift1Desc
	text_end
BillGift2_Desc:
	text_far _BillGift2Desc
	text_end
BillGift3_Desc:
	text_far _BillGift3Desc
	text_end
BillGift4_Desc:
	text_far _BillGift4Desc
	text_end
BillGift5_Desc:
	text_far _BillGift5Desc
	text_end
BillGift6_Desc:
	text_far _BillGift6Desc
	text_end
BillGift7_Desc:
	text_far _BillGift7Desc
	text_end

MrFujiGift1_Desc:
	text_far _MrFujiGift1Desc
	text_end
MrFujiGift2_Desc:
	text_far _MrFujiGift2Desc
	text_end
MrFujiGift3_Desc:
	text_far _MrFujiGift3Desc
	text_end
MrFujiGift4_Desc:
	text_far _MrFujiGift4Desc
	text_end
MrFujiGift5_Desc:
	text_far _MrFujiGift5Desc
	text_end
MrFujiGift6_Desc:
	text_far _MrFujiGift6Desc
	text_end
MrFujiGift7_Desc:
	text_far _MrFujiGift7Desc
	text_end

MrFujiGift8_Desc:
	text_far _MrFujiGift8Desc
	text_end

CaptainGift1_Desc:
	text_far _CaptainGift1Desc
	text_end
CaptainGift2_Desc:
	text_far _CaptainGift2Desc
	text_end
CaptainGift3_Desc:
	text_far _CaptainGift3Desc
	text_end
CaptainGift4_Desc:
	text_far _CaptainGift4Desc
	text_end
CaptainGift5_Desc:
	text_far _CaptainGift5Desc
	text_end
CaptainGift6_Desc:
	text_far _CaptainGift6Desc
	text_end
CaptainGift7_Desc:
	text_far _CaptainGift7Desc
	text_end

FossilGift1_Desc:
	text_far _FossilGift1Desc
	text_end
FossilGift2_Desc:
	text_far _FossilGift2Desc
	text_end
FossilGift3_Desc:
	text_far _FossilGift3Desc
	text_end
FossilGift4_Desc:
	text_far _FossilGift4Desc
	text_end
FossilGift5_Desc:
	text_far _FossilGift5Desc
	text_end
FossilGift6_Desc:
	text_far _FossilGift6Desc
	text_end
FossilGift7_Desc:
	text_far _FossilGift7Desc
	text_end

FanClubGift1_Desc:
	text_far _FanClubGift1Desc
	text_end
FanClubGift2_Desc:
	text_far _FanClubGift2Desc
	text_end
FanClubGift3_Desc:
	text_far _FanClubGift3Desc
	text_end
FanClubGift4_Desc:
	text_far _FanClubGift4Desc
	text_end    
FanClubGift5_Desc:
	text_far _FanClubGift5Desc
	text_end
    
WardenGift1_Desc:
	text_far _WardenGift1Desc
	text_end
WardenGift2_Desc:
	text_far _WardenGift2Desc
	text_end
WardenGift3_Desc:
	text_far _WardenGift3Desc
	text_end
WardenGift4_Desc:
	text_far _WardenGift4Desc
	text_end
WardenGift5_Desc:
	text_far _WardenGift5Desc
	text_end

SchoolGift1_Desc:
	text_far _SchoolGift1Desc
	text_end
SchoolGift2_Desc:
	text_far _SchoolGift2Desc
	text_end
SchoolGift3_Desc:
	text_far _SchoolGift3Desc
	text_end

OldManGift1_Desc:
	text_far _OldManGift1Desc
	text_end
OldManGift2_Desc:
	text_far _OldManGift2Desc
	text_end
OldManGift3_Desc:
	text_far _OldManGift3Desc
	text_end

TrashedGift1_Desc:
	text_far _TrashedGift1Desc
	text_end
TrashedGift2_Desc:
	text_far _TrashedGift2Desc
	text_end
TrashedGift3_Desc:
	text_far _TrashedGift3Desc
	text_end

MomGift1_Desc:
	text_far _MomGift1Desc
	text_end
MomGift2_Desc:
	text_far _MomGift2Desc
	text_end
MomGift3_Desc:
	text_far _MomGift3Desc
	text_end
MomGift4_Desc:
	text_far _MomGift4Desc
	text_end
MomGift5_Desc:
	text_far _MomGift5Desc
	text_end  
MomGift6_Desc:
	text_far _MomGift6Desc
	text_end
  
IgaGift1_Desc:
	text_far _IgaGift1Desc
	text_end
IgaGift2_Desc:
	text_far _IgaGift2Desc
	text_end
IgaGift3_Desc:
	text_far _IgaGift3Desc
	text_end

TradeHouseGift1_Desc:
	text_far _TradeHouseGift1Desc
	text_end
TradeHouseGift2_Desc:
	text_far _TradeHouseGift2Desc
	text_end
TradeHouseGift3_Desc:
	text_far _TradeHouseGift3Desc
	text_end

OaksLabGift1_Desc:
	text_far _OaksLabGift1Desc
	text_end
OaksLabGift2_Desc:
	text_far _OaksLabGift2Desc
	text_end
OaksLabGift3_Desc:
	text_far _OaksLabGift3Desc
	text_end

OaksLabGift4_Desc:
	text_far _OaksLabGift4Desc
	text_end

MACRO bridge_new_desc
\1_Desc:
	text_far _\1Desc
	text_end
ENDM

	bridge_new_desc CaptainGift8
	bridge_new_desc CaptainGift9
	bridge_new_desc FossilGift8
	bridge_new_desc FossilGift9
	bridge_new_desc FanClubGift6
	bridge_new_desc FanClubGift7
	bridge_new_desc FanClubGift8
	bridge_new_desc WardenGift6
	bridge_new_desc WardenGift7
	bridge_new_desc SchoolGift4
	bridge_new_desc SchoolGift5
	bridge_new_desc SchoolGift6
	bridge_new_desc SchoolGift7
	bridge_new_desc SchoolGift8
	bridge_new_desc OldManGift4
	bridge_new_desc OldManGift5
	bridge_new_desc OldManGift6
	bridge_new_desc OldManGift7
	bridge_new_desc OldManGift8
	bridge_new_desc TrashedGift4
	bridge_new_desc TrashedGift5
	bridge_new_desc TrashedGift6
	bridge_new_desc TrashedGift7
	bridge_new_desc TrashedGift8
	bridge_new_desc MomGift7
	bridge_new_desc MomGift8
	bridge_new_desc MomGift9
	bridge_new_desc IgaGift4
	bridge_new_desc IgaGift5
	bridge_new_desc IgaGift6
	bridge_new_desc IgaGift7
	bridge_new_desc IgaGift8
	bridge_new_desc TradeHouseGift4
	bridge_new_desc TradeHouseGift5
	bridge_new_desc TradeHouseGift6
	bridge_new_desc TradeHouseGift7
	bridge_new_desc TradeHouseGift8
	bridge_new_desc TradeHouseGift9
	bridge_new_desc OaksLabGift5
	bridge_new_desc OaksLabGift6
	bridge_new_desc OaksLabGift7
