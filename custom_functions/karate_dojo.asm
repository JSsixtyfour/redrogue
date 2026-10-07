; Karate Master mini-boss reward (MINIBOSS_FRAMEWORK.md, KARATE_MINIBOSS_PLAN.md).
;
; The Dojo offers two of three named special-form #MON and the player takes
; one. This is deliberately NOT the bridge gift system: no BridgeGiverMapTable
; row, no wGift1-3, no EVENT_BRIDGE_RECEIVE_GIFT. It borrows the bridge menu's
; layout and only calls the stateless far helpers (evolve-by-level resolve,
; special-form finalize, stat recalc).
;
; The excluded index (0-2) is rolled by the Dojo's setup block into
; EVENT_DOJO_EXCLUDED_BIT0/1; the two offered rows are the other two indices
; in ascending order, then NO THANKS.
;
; Its own section: "Hidden Events 2" (the bridge menu's bank) is full. PINNED to
; $08: left floating, first fit dropped its ~480 B into bank $01 in the release
; ROMs and left $01 with 19 B (project_romx_firstfit_bank_pressure). $08 had
; 2.1 KB+ free in all three ROMs (ROM_BIBLE.md 2026-09-29).

SECTION "Karate Dojo Reward", ROMX, BANK[$08]

DEF KARATE_DOJO_OFFERED  EQU 2              ; mon rows shown; NO THANKS is row 2
DEF KARATE_DOJO_ENTRY_SIZE EQU 5            ; species, prefix ptr, desc ptr

; Row index = excluded-index space. The prefix is a menu label only: the mon's
; stored nickname stays the plain species name (10-character limit).
KarateDojoRewards:
	db MACHOP
	dw KarateNoGuardPrefix, KarateNoGuardDesc
	db HITMONLEE
	dw KarateLimberPrefix, KarateLimberDesc
	db HITMONCHAN
	dw KarateMysticPrefix, KarateMysticDesc
	ASSERT @ - KarateDojoRewards == 3 * KARATE_DOJO_ENTRY_SIZE

; ---------------------------------------------------------------------------
; KarateDojoRewardMenu (farcall from the Dojo's text_asm)
; OUT: carry = a #MON was given (party or box); nc = NO THANKS / B / full.
; ---------------------------------------------------------------------------
KarateDojoRewardMenu::
	ld hl, wStatusFlags5
	set BIT_NO_TEXT_DELAY, [hl]
	xor a
	ldh [hCurrentMenuItem], a
	ld [wLastMenuItem], a
	ld a, PAD_A | PAD_B | PAD_UP | PAD_DOWN
	ld [wMenuWatchedKeys], a
	ld a, KARATE_DOJO_OFFERED
	ld [wMaxMenuItem], a         ; max index = the NO THANKS row
	ld a, $04
	ld [wTopMenuItemY], a
	ld a, $01
	ld [wTopMenuItemX], a
	hlcoord 0, 2
	lb bc, 6, 18
	call TextBoxBorder
	call KarateDojoPlaceNames
	; Same as BridgeGiftMenu: freeze object rendering so map actors can't
	; composite over the names, and restore the caller's state afterwards.
	ldh a, [hUpdateSpritesEnabled]
	push af
	ld a, $ff
	ldh [hUpdateSpritesEnabled], a
	call ClearSprites
	call DelayFrame
	xor a
	call KarateDojoPrintDesc
.menuLoop
	call HandleMenuInput
	bit B_PAD_A, a
	jr nz, .aPressed
	bit B_PAD_B, a
	jr nz, .noChoice
	ldh a, [hCurrentMenuItem]
	call KarateDojoPrintDesc
	jr .menuLoop
.aPressed
	ldh a, [hCurrentMenuItem]
	cp KARATE_DOJO_OFFERED
	jr z, .noChoice
	call KarateDojoGive          ; carry = given
	jr .restore
.noChoice
	and a
.restore
	pop bc                       ; b = saved hUpdateSpritesEnabled; flags kept
	ld a, b
	ldh [hUpdateSpritesEnabled], a
	ld hl, wStatusFlags5
	res BIT_NO_TEXT_DELAY, [hl]  ; res leaves carry alone
	ret

; ---------------------------------------------------------------------------
; out: a = excluded row index (0-2). Clobbers f, b.
KarateDojoExcludedIndex:
	ld b, 0
	CheckEvent EVENT_DOJO_EXCLUDED_BIT0
	jr z, .bit1
	inc b
.bit1
	CheckEvent EVENT_DOJO_EXCLUDED_BIT1
	jr z, .done
	inc b
	inc b
.done
	ld a, b
	ret

; in: a = menu index (0-1) ; out: hl -> that row's KarateDojoRewards entry.
; Menu index k maps to row k, skipping the excluded row. Clobbers af, bc.
KarateDojoEntryForMenuIndex:
	ld c, a
	call KarateDojoExcludedIndex
	cp c
	ld a, c
	jr z, .skip
	jr nc, .haveRow              ; excluded > k: row k unaffected
.skip
	inc a                        ; excluded <= k: step past it
.haveRow
	ld hl, KarateDojoRewards
	ld bc, KARATE_DOJO_ENTRY_SIZE
	jp AddNTimes

; in: a = base species ; out: a = species evolved to the reward level.
KarateDojoResolveSpecies:
	ld e, a
	farcall BridgeResolveEvolveSpeciesFar ; e in/out; state-free helper
	ld a, e
	ret

; ---------------------------------------------------------------------------
; Rows 4 and 6: prefix + resolved species name. Row 8: NO THANKS.
KarateDojoPlaceNames:
	ld c, 0
.loop
	ld a, c
	cp KARATE_DOJO_OFFERED
	jr z, .noThanks
	push bc
	call KarateDojoEntryForMenuIndex
	ld a, [hli]                  ; base species
	push hl
	call KarateDojoResolveSpecies
	ld [wNamedObjectIndex], a
	xor a
	ld [wFormContextForm], a     ; no stale form context on the name
	call GetMonName              ; -> wNameBuffer
	pop hl
	ld a, [hli]
	ld e, a
	ld d, [hl]                   ; de = prefix string
	pop bc
	push bc
	ld a, c
	add a
	add 4                        ; row = 4 + 2*index
	push de                      ; coordinate helper clobbers the prefix pointer
	call KarateDojoCoordRow2
	pop de
	call PlaceString             ; bc = cursor just past the prefix
	ld h, b
	ld l, c
	ld de, wNameBuffer
	call PlaceString
	pop bc
	inc c
	jr .loop
.noThanks
	ld a, 4 + 2 * KARATE_DOJO_OFFERED
	call KarateDojoCoordRow2
	ld de, KarateNoThanksText
	jp PlaceString

; in: a = row ; out: hl = tilemap coord at column 2 of that row. Clobbers de.
KarateDojoCoordRow2:
	ld l, a
	ld h, 0
	ld d, h
	ld e, l
	add hl, hl                   ; *2
	add hl, hl                   ; *4
	add hl, de                   ; *5
	add hl, hl                   ; *10
	add hl, hl                   ; *20 (SCREEN_WIDTH)
	ld de, wTileMap + 2
	add hl, de
	ret

; in: a = menu index ; prints that row's description in the bottom text box.
KarateDojoPrintDesc:
	cp KARATE_DOJO_OFFERED
	jr z, .empty
	call KarateDojoEntryForMenuIndex
	ld bc, 3
	add hl, bc                   ; -> desc ptr
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp PrintText
.empty
	ld hl, KarateNoThanksDesc
	jp PrintText

; ---------------------------------------------------------------------------
; in: a = menu index (0-1). Gives the resolved species at the reward level,
; flags it as a special form, and recalculates a party Hitmonchan so the
; Mystic stat swap lands immediately (a boxed one recalcs on withdrawal).
; out: carry = given.
KarateDojoGive:
	call KarateDojoEntryForMenuIndex
	ld a, [hl]                   ; base species
	call KarateDojoResolveSpecies
	push af                      ; resolved species
	xor a
	ld [wSpawnForm], a           ; a fixed species, never a form
	farcall GetBridgeRewardMonLevelFar ; e = reward level (state-free)
	pop af
	ld b, a
	ld c, e
	call GivePokemon
	ret nc                       ; party and box full
	ld e, BRIDGE_MON_FINALIZE_SPECIAL
	farcall BridgeFinalizeGiftMonFar ; sets BIT_SPECIAL_FORM; de = new struct
	ld a, [wAddedToParty]
	and a
	jr z, .done                  ; boxed: no stats stored yet
	ld a, [de]
	cp HITMONCHAN
	jr nz, .done
	farcall BridgeRecalcStatsFar ; de = struct
.done
	scf
	ret

; ---------------------------------------------------------------------------
KarateNoGuardPrefix: db "NO GUARD @"
KarateLimberPrefix:  db "LIMBER @"
KarateMysticPrefix:  db "MYSTIC @"
KarateNoThanksText:  db "NO THANKS@"

KarateNoGuardDesc:
	text "Its moves never"
	line "miss, and neither"
	cont "do the foe's!"
	done

KarateLimberDesc:
	text "Can't be"
	line "paralyzed."
	done

KarateMysticDesc:
	text "Its ATTACK and"
	line "SPECIAL stats are"
	cont "swapped."
	done

KarateNoThanksDesc:
	text ""
	done
