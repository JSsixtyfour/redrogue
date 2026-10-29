; Legendary Boss Challenge — Helper Routines
; Lives in the "rogue" ROMX section (see main.asm). Callers in a different
; bank (e.g. scripts/*.asm map scripts) MUST use farcall, not call.

; ReverseLookupPokemonClass
; Input: b = species
; Output: c = class (1=pokeball, 2=greatball, 3=ultraball, 4=masterball/uber)
; Clobbers: a, hl  (b and de preserved)
;
; Thin adapter over RogueClassifySpeciesLegacy (engine/pokemon/rarity.asm, same
; bank, so a plain call reaches it). It used to hand-scan the flat rarity table
; with no bounds check, which ran off the end of the table for any species not
; in a pool.
ReverseLookupPokemonClass::
	push bc
	push de                      ; RogueClassifySpecies uses de as its scan cursors
	ld a, b
	call RogueClassifySpeciesLegacy
	jr nc, .ok
	ld c, 1                      ; unknown species - treat as pokeball class
.ok
	ld a, c
	pop de
	pop bc
	ld c, a
	ret

; HasMasterballClassMon: Scan wPartySpecies (FF-terminated) for any
; masterball-class mon via the ReverseLookupPokemonClass adapter.
; Output: carry set (true) if found, carry clear (false) if not.
; Clobbers: a, b, c, e, hl
HasMasterballClassMon::
	ld hl, wPartySpecies
.loop
	ld a, [hl]
	cp $FF
	jr z, .notFound
	ld b, a
	push hl
	call ReverseLookupPokemonClass  ; c = class
	pop hl
	ld a, c
	cp 4
	jr z, .found
	inc hl
	jr .loop
.notFound
	and a                        ; clear carry = not found
	ret
.found
	scf                          ; set carry = found
	ret

; LegendaryBossTable (the leaders and the legendaries each can field) and its
; lookup live in custom_functions/endless.asm with LegendaryPoolUnowned, which
; filters each pool to species the player does not own. This bank had no room.

; RollLegendaryBossAce
; The Challenge 11 swap, farcalled by the party spec builder for a team's LAST
; slot (its ace) after the slot's species is final and before AddPartyMon
; creates it (rogue_build_party.asm PartyGenLegendaryBossAce). Every input
; comes from WRAM and the answer goes back in WRAM plus carry, because a
; farcall keeps only d, e and the flags.
;
; If the bargain is accepted, the challenge is Legendary Boss and this
; trainer's class has a pool member the player does not own yet, rolls one of
; those into wCurPartySpecies and records it in wLegendaryBossSpecies, which the
; post-battle trade reads (wGymLeaderNo is zeroed by then). Also writes the
; ace's wSpawnForm: 0, except Giovanni's Mewtwo, which is Armored Mewtwo. The
; trade gives that same Mewtwo armored (OfferLegendaryTradeGiovanni).
; Output: carry SET if the ace was swapped
; Clobbers: a, b, c, d, e, hl
RollLegendaryBossAce::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .no
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	jr nz, .no
	ld a, [wTrainerClass]
	ld e, a
	ld d, 1                      ; pick
	farcall LegendaryPoolUnowned ; carry, e = species; keeps d/e and the flags
	ret nc
	ld a, e
	ld [wCurPartySpecies], a
	ld [wLegendaryBossSpecies], a
	ld b, a
	ld a, [wTrainerClass]
	cp GIOVANNI
	ld a, 0                      ; `ld`, not `xor`: the cp's flags reach the jr
	jr nz, .setForm
	ld a, b
	cp MEWTWO
	ld a, 0
	jr nz, .setForm
	ld a, ARMORED_MEWTWO_FORM
.setForm
	ld [wSpawnForm], a
	scf
	ret
.no
	and a
	ret

; LegendaryLeaderTradeSetup
; Scans the party for masterball-class mons, picks one at random, and sets
; up the standard rogue in-game trade WRAM fields so RogueDoInGameTradeDialogue
; can run: player must give the chosen masterball mon, receives the legendary
; passed in b. Caller should confirm HasMasterballClassMon first.
;
; NOTE: takes the legendary species directly (b) rather than deriving it from
; wGymLeaderNo, because every OfferLegendaryTrade<Leader> caller runs from a
; post-battle map script - by then EndOfBattle has already gone through
; EnterMap -> ClearVariablesOnEnterMap, which zeroes wLoneAttackNo. That byte
; is aliased to wGymLeaderNo (ram/wram.asm - two labels on one db, not a
; UNION), so a wGymLeaderNo read here always sees 0, not the leader that was
; just fought. Each caller already knows its own leader, so it passes the
; species directly instead, from wLegendaryBossSpecies (written by
; RollLegendaryBossAce when the ace was swapped).
; Input: b = species to give
; Clobbers: a, b, c, d, e, hl
LegendaryLeaderTradeSetup::
	push bc                      ; preserve input species (b) across the scan below, which reuses b/c as scratch
	ld hl, wPartySpecies
	ld de, wAllSpecies
.scanLoop
	ld a, [hl]
	cp $FF
	jr z, .scanDone
	ld b, a                      ; species to classify
	push hl
	push de                      ; belt-and-braces: ReverseLookupPokemonClass preserves de now, but this write pointer is load-bearing
	call ReverseLookupPokemonClass  ; c = class
	pop de
	pop hl
	ld a, c
	cp 4
	jr nz, .scanNext
	ld a, b                      ; masterball-class species found
	ld [de], a
	inc de
.scanNext
	inc hl
	jr .scanLoop
.scanDone
	; count = de - wAllSpecies (always < 256, safe as an 8-bit low-byte diff)
	ld a, e
	ld hl, wAllSpecies
	sub l
	ld c, a                      ; c = count of masterball mons found
	call Rangerandom             ; a = [0, c-1]
	ld hl, wAllSpecies
	ld d, 0
	ld e, a
	add hl, de
	ld a, [hl]                   ; a = chosen masterball species to give
	ld [wroguenpctradegive], a

	pop bc                       ; restore input species (b = MEW or MEWTWO)
	xor a                        ; formless here (OfferLegendaryTradeCommon arms
	ld [wroguenpctradeform], a   ; Giovanni's Mewtwo after); also clears any
	                             ; form a previous TRADE_FOR_RANDOM offer left
    ld a, b
    ld [wroguenpctradeget], a
    ld [wNamedObjectIndex], a   ; place pokemon id in spot for GetMonName
    call GetMonName         ; get name of pokemon to receive
    ld hl, wNameBuffer      ; name address
    ld de, wroguenpctradename   ; load name into this location
    ld bc, NAME_LENGTH      ; name length
    call CopyData           ; copy name to location

	; RogueDoInGameTradeDialogue uses this byte as a raw index (0/1/2) into
	; InGameTradeTextPointers to pick the wanna-trade/no-trade/etc text table -
	; without it explicitly set, it holds whatever was last here and can index
	; wildly out of bounds (matches random_pokemon_selection.asm:228, the other
	; working caller, which sets the same field for the same reason).
	ld a, TRADE_DIALOGSET_LEGENDARY
	ld [wroguenpctradedialogue], a
	ret

; ============================================================
; Gym-specific legendary trade offer helpers (Step 5)
;
; IMPORTANT: these are NOT called raw from the gym map script. They are
; dispatched as text_asm handlers via DisplayTextID (see each gym's
; <Gym><Leader>TradeText entry), exactly like the lobby's PCTraderSuperNerdText.
; That matters: RogueDoInGameTradeDialogue's text/menu only renders while the
; text display is OPEN (DisplayTextID's init brings the window on-screen via
; hWY and enables the VBlank tilemap->VRAM transfer; CloseTextDisplay tears it
; down). A raw farcall from a post-battle map step runs AFTER the TM text's
; DisplayTextID already closed the display, so nothing renders (blank offer,
; sprite-only party menu). Running them through DisplayTextID gives them the
; same open-display context the TM texts above them already use.
;
; The gym script pre-gates with IsLegendaryTradeReady + a CheckEvent on the
; per-gym offer flag, so DisplayTextID is only invoked when a trade will
; actually happen (otherwise it would draw an empty text box). The redundant
; checks inside each helper are defense-in-depth.
;
; Callers in different banks (gym scripts) MUST use farcall.
; ============================================================

; ============================================================
; Challenge 11's witch gate, door line, gym-entry enforcement and dice warning.
;
; GYM LEADERS HAVE NO ORDER: the lobby's two doors lead to two random unbeaten
; badge slots (wGymChoice), and wRunGymLineup holds each slot's leader as a
; TRAINER CLASS. So "does this door lead to a legendary" is the same class
; lookup the swap uses, LegendaryBossTable, and the two can never drift apart.
; ============================================================

; LegendaryBossDoors
; Output: e bit 0 = door 1's gym has a legendary, bit 1 = door 2's. 0 when no
;         pair is latched. With one gym left both doors share a slot, so both
;         bits agree.
; Clobbers: a, b, c, d, hl
LegendaryBossDoors::
	ld e, 0
	ld a, [wGymChoice]
	bit BIT_GYM_CHOICE_LATCHED, a
	ret z
	ld d, a
	and GYM_CHOICE_DOOR1_MASK
	call SlotIsLegendaryBoss
	jr nc, .door2
	set 0, e
.door2
	ld a, d
	and GYM_CHOICE_DOOR2_MASK
	rrca
	rrca
	rrca
	ASSERT GYM_CHOICE_DOOR2_SHIFT == 3
	call SlotIsLegendaryBoss
	ret nc
	set 1, e
	ret

; SlotIsLegendaryBoss
; Input:  a = badge slot (0-7)
; Output: carry SET if that slot's lineup leader has a LegendaryBossTable row
;         with a species the player does not own yet. Every Challenge 11 gate
;         (the witch's offer, the door line, the wrong-door check) asks this, so
;         an owned-out leader is never a legendary door.
;         An unrolled lineup (old saves, never at 4+ badges) counts as no.
; Clobbers: a, b, c, hl. Preserves de.
SlotIsLegendaryBoss::
	ld c, a
	ld b, 0
	ld hl, wRunGymLineup
	add hl, bc
	ld a, [hl]
	and a
	ret z                        ; `and a` cleared carry
	push de
	ld e, a
	ld d, 0                      ; count only: consumes no RNG
	farcall LegendaryPoolUnowned
	pop de                       ; pop keeps the carry
	ret

; IsLegendaryBossOfferable: the witch's gate for Challenge 11.
; Carry SET when: not the finale, at least 4 badges (so the next gym is gym 5-8,
; whatever leaders those are), at least one door leads to a leader with a
; legendary, and the party holds a masterball-class mon to trade.
; Clobbers: a, b, c, d, e, hl
IsLegendaryBossOfferable::
	ld a, [wObtainedBadges]
	cp $FF
	jr z, .no                    ; finale: no gym is next
	ld b, 0
	ld c, NUM_BADGES
.count
	add a
	jr nc, .notSet
	inc b
.notSet
	dec c
	jr nz, .count
	ld a, b
	cp 4
	jr c, .no
	call LegendaryBossDoors
	ld a, e
	and a
	ret z                        ; no eligible door; `and a` cleared carry
	jp HasMasterballClassMon     ; carry = has one
.no
	and a
	ret

; WitchLegendaryOfferCheck  (farcall, from PCWitchText's text_asm)
; Re-checks the doors LIVE when the player talks to her: the door dice can
; reroll the pair after PCWitchSetup rolled the offer. If Challenge 11 is on
; offer and neither door qualifies any more, she withdraws: wWitchChallenge = 0
; so nothing downstream sees an offer, and every later talk this visit lands
; on the same withdrawal (a visible witch with challenge 0 only happens here).
; Output: carry SET = carry on with the offer; CLEAR = she withdrew, end text.
WitchLegendaryOfferCheck::
	ld a, [wWitchChallenge]
	and a
	jr z, .withdrawn
	cp CHALLENGE_LEGENDARY_BOSS
	jr nz, .go
	call LegendaryBossDoors
	ld a, e
	and a
	jr nz, .go
	ld [wWitchChallenge], a      ; a = 0
.withdrawn
	ld hl, WitchLegendaryWithdrawText
	call PrintText
	and a
	ret
.go
	scf
	ret

; WitchLegendaryDoorLine  (farcall, from PCWitchText after the challenge text)
; Names the door whose leader holds the legendary: taking the other one breaks
; the bargain (LegendaryBossEnteredSlot). WitchLegendaryOfferCheck already
; proved at least one door qualifies.
WitchLegendaryDoorLine::
	call LegendaryBossDoors
	ld hl, WitchLegendaryEitherDoorText
	ld a, e
	cp %11
	jr z, .print
	ld hl, WitchLegendaryDoor1Text
	dec a
	jr z, .print
	ld hl, WitchLegendaryDoor2Text
.print
	jp PrintText

; LegendaryBossEnteredSlot  (from RogueGymChoiceMapLoad, same bank)
; Called when the map just loaded is the gym of latched slot a. If Challenge 11
; is active and that gym's leader has no legendary, the player took the wrong
; door: the bargain breaks. Silent here (a map load is no text context); the
; witch named the door when the bargain was struck.
; Input: a = badge slot entered. Preserves c (the caller's wGymChoice copy).
LegendaryBossEnteredSlot::
	ld b, a
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz
	push bc
	ld a, b
	call SlotIsLegendaryBoss
	pop bc
	ret c
	; fallthrough
; Ends the bargain with nothing granted: Challenge 11's prize id is the 0
; sentinel, and with the accepted bit clear the next lobby grants nothing.
BreakLegendaryBargain:
	xor a
	ld [wWitchChallenge], a
	ld hl, wRogueFlagsBitfield
	res BIT_WITCH_ACCEPTED, [hl]
	ret

; DoorDiceLegendaryWarning  (from RogueItemUseDoorDice, same bank, before a
; charge is spent). Rerolling the doors after striking Challenge 11's bargain
; would move the legendary's door, so the player is warned first.
; Output: carry SET = roll (YES, or no bargain at stake; on YES the bargain is
;         broken); carry CLEAR = NO, cancel without spending a charge.
DoorDiceLegendaryWarning::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .roll
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	jr nz, .roll
	ld hl, DoorDiceLegendaryWarnText
	call PrintText
	call YesNoChoice
	ldh a, [hCurrentMenuItem]
	and a
	ret nz                       ; NO; `and a` cleared carry
	call BreakLegendaryBargain
.roll
	scf
	ret

WitchLegendaryWithdrawText:
	text_far _WitchLegendaryWithdrawText
	text_end

WitchLegendaryDoor1Text:
	text_far _WitchLegendaryDoor1Text
	text_end

WitchLegendaryDoor2Text:
	text_far _WitchLegendaryDoor2Text
	text_end

WitchLegendaryEitherDoorText:
	text_far _WitchLegendaryEitherDoorText
	text_end

DoorDiceLegendaryWarnText:
	text_far _DoorDiceLegendaryWarnText
	text_end

; IsLegendaryTradeReady: shared pre-dispatch gate. Carry set if Challenge 11 is
; accepted, a legendary was fielded (wLegendaryBossSpecies nonzero) AND the
; party still holds a masterball-class mon. The per-leader
; "already offered" event is a compile-time constant, so the caller checks it
; separately with CheckEvent.
; Clobbers: a, b, c, e, hl
IsLegendaryTradeReady::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .notReady
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	jr nz, .notReady
	ld a, [wLegendaryBossSpecies]
	and a
	jr z, .notReady              ; this leader fielded no legendary: nothing to trade
	call HasMasterballClassMon   ; returns carry set if a masterball mon is present
	ret
.notReady
	and a                        ; clear carry = not ready
	ret

; Per-leader entry points. Each names its own "already offered" event, the
; one thing that differs between leaders; the species is whatever the battle
; actually fielded (wLegendaryBossSpecies). Gym scripts farcall these.
; legendary_trade_entry <event>, <species this leader fields armored, 0 = none>
MACRO legendary_trade_entry
	ld hl, wEventFlags + (\1) / 8
	ld e, 1 << ((\1) % 8)
	ld d, \2
	jr OfferLegendaryTradeCommon
ENDM

OfferLegendaryTradeErika::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_GYM5, 0
OfferLegendaryTradeSabrina::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_GYM6, 0 ; her Mewtwo is plain
OfferLegendaryTradeBlaine::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_GYM7, 0
OfferLegendaryTradeGiovanni::
	; Armored Mewtwo, as RollLegendaryBossAce fielded it.
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_GYM8, MEWTWO
OfferLegendaryTradeFalkner::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_FALKNER, 0
OfferLegendaryTradeMorty::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_MORTY, 0
OfferLegendaryTradePryce::
	legendary_trade_entry EVENT_OFFERED_LEGENDARY_TRADE_PRYCE, 0

; OfferLegendaryTradeCommon
; Input: hl = the leader's EVENT_OFFERED_LEGENDARY_TRADE_* byte in wEventFlags,
;        e = that event's bit mask (a runtime CheckEvent/SetEvent, since the
;        macros only take a constant),
;        d = the species this leader fields armored (0 = none)
OfferLegendaryTradeCommon:
	ld a, [hl]
	and e
	ret nz                       ; already offered, no-op
	push hl
	push de
	call IsLegendaryTradeReady   ; accepted, Challenge 11, a fielded legendary, a masterball mon
	jr nc, .popRet
	ld a, [wLegendaryBossSpecies]
	ld b, a
	call LegendaryLeaderTradeSetup ; offers it formless
	pop de
	push de                      ; d = this leader's armored species
	ld a, [wLegendaryBossSpecies]
	cp d
	jr nz, .formless
	ld a, ARMORED_MEWTWO_FORM
	ld [wroguenpctradeform], a
.formless
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a          ; InGameTrade_DoTrade indexes wCompletedInGameTradeFlags by
	                             ; wWhichTrade; TRADE_FOR_RANDOM is FLAG_RESET every lobby entry
	; Dispatched as a text_asm, so the display is already open - no
	; hAutoBGTransferEnabled poke needed. But DisplayTextID does NOT clear
	; hJoyIgnore, and the gym's post-battle handler set it to PAD_CTRL_PAD
	; (masks the d-pad), which would freeze the trade's party-menu cursor -
	; clear it so the player can pick a mon to give.
	xor a
	ldh [hJoyIgnore], a
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	predef RogueDoInGameTradeDialogue
	pop af
	ldh [hTileAnimations], a
	; Only mark the offer done (suppressing both the immediate re-fire and the
	; .afterBeat re-offer) if the trade actually COMPLETED. On decline/wrong-mon
	; the flag stays clear, so talking to the leader again re-offers it.
	ld hl, wCompletedInGameTradeFlags
	ld a, TRADE_FOR_RANDOM
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	pop de
	pop hl
	ld a, c
	and a
	ret z                        ; not traded - leave the offer available
	ld a, [hl]
	or e
	ld [hl], a                   ; SetEvent
	ret
.popRet
	pop de
	pop hl
	ret
