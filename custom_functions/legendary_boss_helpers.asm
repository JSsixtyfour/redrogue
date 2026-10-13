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

; ============================================================
; LegendaryBossTable
; Challenge 11's leaders and the legendaries each can field, keyed on TRAINER
; CLASS. Never key this on wGymLeaderNo: Kanto and Johto share 1-8 (Morty and
; Erika are both 4, Pryce and Blaine both 7), and gyms are drawn in a random
; order every run, so neither the number nor a "gym N" says who the leader is.
;
; Row: db class, count, species x count. Terminated by db 0.
; The witch's offer gate (witch_setup.asm) checks the same seven leaders by
; their gym MAP, since at lobby time no battle has set wTrainerClass. Keep the
; two lists in step.
; ============================================================
LegendaryBossTable:
	db ERIKA,    2, MEW, CELEBI
	db SABRINA,  4, MEWTWO, MEW, CELEBI, LUGIA
	db BLAINE,   2, MEW, HO_OH
	db GIOVANNI, 1, MEWTWO
	db FALKNER,  2, LUGIA, HO_OH
	db MORTY,    1, HO_OH
	db PRYCE,    1, CELEBI
	db 0

; GetLegendaryPoolForClass
; Input:  a = trainer class
; Output: carry SET -> hl = the row's count byte, species follow it
;         carry CLEAR -> the class has no legendary
; Clobbers: a, b, hl
GetLegendaryPoolForClass::
	ld b, a
	ld hl, LegendaryBossTable
.loop
	ld a, [hli]
	and a
	ret z                        ; end of table; `and a` cleared carry
	cp b
	jr z, .found
	ld a, [hli]                  ; count: skip that many species
	add l
	ld l, a
	jr nc, .loop
	inc h
	jr .loop
.found
	scf
	ret

; RollLegendaryBossAce
; The Challenge 11 swap, farcalled by the party spec builder for a team's LAST
; slot (its ace) after the slot's species is final and before AddPartyMon
; creates it (rogue_build_party.asm PartyGenLegendaryBossAce). Every input
; comes from WRAM and the answer goes back in WRAM plus carry, because a
; farcall keeps only d, e and the flags.
;
; If the bargain is accepted, the challenge is Legendary Boss and this
; trainer's class has a pool, rolls one species from the pool into
; wCurPartySpecies and records it in wLegendaryBossSpecies, which the
; post-battle trade reads (wGymLeaderNo is zeroed by then).
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
	call GetLegendaryPoolForClass
	ret nc
	ld a, [hli]
	ld c, a
	call Rangerandom             ; a = 0..count-1; preserves hl
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl]
	ld [wCurPartySpecies], a
	ld [wLegendaryBossSpecies], a
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
; BuildLegendaryMoveset / BuildMewMoveset / BuildMewtwoMoveset
; Builds the themed 4-move set for the gym leader's battle-team legendary
; (Step 4 consumes this; the traded copy is intentionally left with whatever
; the normal engine path gives it - see plan doc).
; Input: b = species (MEW or MEWTWO)
; Output: wBuffer+6..9 = 4 move IDs
; Clobbers: a, b, c, d, hl
;
; Mew:    Swords Dance, Earthquake, {Body Slam | Hyper Beam}, Softboiled
; Mewtwo: Amnesia, {Psychic | Thunderbolt | Submission}, {Thunderbolt | Ice Beam}, Recover
;         (de-dup: slot 3 never rolls Thunderbolt if slot 2 already did)
; ============================================================
BuildLegendaryMoveset::
	ld a, b
	cp MEWTWO
	jr z, BuildMewtwoMoveset
	; fall through to BuildMewMoveset (default/fallback = Mew)

BuildMewMoveset:
	ld a, SWORDS_DANCE
	ld [wBuffer + 6], a
	ld a, EARTHQUAKE
	ld [wBuffer + 7], a

	ld c, 2
	call Rangerandom             ; a = 0/1
	and a
	jr nz, .slot3HyperBeam
	ld a, BODY_SLAM
	jr .gotSlot3
.slot3HyperBeam
	ld a, HYPER_BEAM
.gotSlot3
	ld [wBuffer + 8], a

	ld a, SOFTBOILED
	ld [wBuffer + 9], a
	ret

BuildMewtwoMoveset:
	ld a, AMNESIA
	ld [wBuffer + 6], a

	ld c, 3
	call Rangerandom             ; a = 0(Psychic)/1(Thunderbolt)/2(Submission)
	ld d, a                      ; stash roll - survives Rangerandom (only touches af/bc)
	cp 1
	jr z, .slot2Thunderbolt
	cp 2
	jr z, .slot2Submission
	ld a, PSYCHIC_M
	jr .gotSlot2
.slot2Thunderbolt
	ld a, THUNDERBOLT
	jr .gotSlot2
.slot2Submission
	ld a, SUBMISSION
.gotSlot2
	ld [wBuffer + 7], a

	ld a, d
	cp 1                          ; was slot 2 Thunderbolt?
	jr z, .slot3ForceIceBeam
	ld c, 2
	call Rangerandom              ; a = 0(Thunderbolt)/1(Ice Beam)
	and a
	jr z, .slot3Thunderbolt
	ld a, ICE_BEAM
	jr .gotSlot3
.slot3Thunderbolt
	ld a, THUNDERBOLT
	jr .gotSlot3
.slot3ForceIceBeam
	ld a, ICE_BEAM
.gotSlot3
	ld [wBuffer + 8], a

	ld a, RECOVER
	ld [wBuffer + 9], a
	ret

; ============================================================
; ApplyLegendaryMoveset
; Writes the 4 moves built by BuildLegendaryMoveset (wBuffer+6..9) into a
; target mon's MON_MOVES field, and rewrites MON_PP from each move's base PP
; (Moves struct byte 5) - the pattern the old OverrideGamblerMoves used. Works for any
; MON_MOVES pointer (enemy or player array); caller computes the base.
; Input: hl = pointer to target mon's MON_MOVES field (4 bytes)
; Clobbers: a, b, c, d, e, hl
; ============================================================
ApplyLegendaryMoveset::
	ld de, wBuffer + 6           ; source: 4 built move IDs
	ld b, NUM_MOVES
.copyLoop
	ld a, [de]
	ld [hl], a                    ; MON_MOVES[slot] = move id
	push bc
	push de
	push hl
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes                ; hl -> move struct (Moves bank)
	ld de, wBuffer
	ld a, BANK(Moves)
	call FarCopyData               ; wBuffer+0..5 = move struct
	pop hl                         ; hl = MON_MOVES[slot]
	push hl
	ld bc, MON_PP - MON_MOVES
	add hl, bc                     ; hl -> MON_PP[slot]
	ld a, [wBuffer + 5]            ; base PP
	ld [hl], a
	pop hl                         ; hl = MON_MOVES[slot]
	pop de                         ; source ptr
	pop bc                         ; move counter
	inc hl                         ; next MON_MOVES slot
	inc de                         ; next source move
	dec b
	jr nz, .copyLoop
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

; Erika (Gym 5, EVENT_OFFERED_LEGENDARY_TRADE_GYM5)
OfferLegendaryTradeErika::
	CheckEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM5
	ret nz                       ; already offered, no-op
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z                        ; challenge not accepted
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz                       ; wrong challenge
	call HasMasterballClassMon   ; same bank, plain call
	ret nc                       ; no masterball mon in party
	ld a, [wLegendaryBossSpecies] ; the species this battle actually fielded
	and a
	ret z                        ; no swap happened (e.g. a reload cleared it)
	ld b, a
	call LegendaryLeaderTradeSetup   ; same bank, plain call
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
	ld a, c
	and a
	ret z                        ; not traded - leave the offer available
	SetEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM5
	ret

; Sabrina (Gym 6, EVENT_OFFERED_LEGENDARY_TRADE_GYM6)
OfferLegendaryTradeSabrina::
	CheckEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM6
	ret nz
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz
	call HasMasterballClassMon
	ret nc
	ld a, [wLegendaryBossSpecies] ; the species this battle actually fielded
	and a
	ret z                        ; no swap happened (e.g. a reload cleared it)
	ld b, a
	call LegendaryLeaderTradeSetup
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
	xor a
	ldh [hJoyIgnore], a          ; clear the gym's PAD_CTRL_PAD d-pad mask so the
	                             ; party-menu cursor can move (see OfferLegendaryTradeErika)
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	predef RogueDoInGameTradeDialogue
	pop af
	ldh [hTileAnimations], a
	ld hl, wCompletedInGameTradeFlags   ; only mark done on a completed trade
	ld a, TRADE_FOR_RANDOM
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	ld a, c
	and a
	ret z                        ; declined/wrong mon - leave the offer available
	SetEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM6
	ret

; Blaine (Gym 7, EVENT_OFFERED_LEGENDARY_TRADE_GYM7)
OfferLegendaryTradeBlaine::
	CheckEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM7
	ret nz
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz
	call HasMasterballClassMon
	ret nc
	ld a, [wLegendaryBossSpecies] ; the species this battle actually fielded
	and a
	ret z                        ; no swap happened (e.g. a reload cleared it)
	ld b, a
	call LegendaryLeaderTradeSetup
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
	xor a
	ldh [hJoyIgnore], a          ; clear the gym's PAD_CTRL_PAD d-pad mask so the
	                             ; party-menu cursor can move (see OfferLegendaryTradeErika)
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	predef RogueDoInGameTradeDialogue
	pop af
	ldh [hTileAnimations], a
	ld hl, wCompletedInGameTradeFlags   ; only mark done on a completed trade
	ld a, TRADE_FOR_RANDOM
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	ld a, c
	and a
	ret z                        ; declined/wrong mon - leave the offer available
	SetEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM7
	ret

; Giovanni (Gym 8, EVENT_OFFERED_LEGENDARY_TRADE_GYM8)
OfferLegendaryTradeGiovanni::
	CheckEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM8
	ret nz
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz
	call HasMasterballClassMon
	ret nc
	ld a, [wLegendaryBossSpecies] ; the species this battle actually fielded
	and a
	ret z                        ; no swap happened (e.g. a reload cleared it)
	ld b, a
	call LegendaryLeaderTradeSetup
	ld a, TRADE_FOR_RANDOM
	ld [wWhichTrade], a
	xor a
	ldh [hJoyIgnore], a          ; clear the gym's PAD_CTRL_PAD d-pad mask so the
	                             ; party-menu cursor can move (see OfferLegendaryTradeErika)
	ldh a, [hTileAnimations]
	push af
	xor a
	ldh [hTileAnimations], a
	predef RogueDoInGameTradeDialogue
	pop af
	ldh [hTileAnimations], a
	ld hl, wCompletedInGameTradeFlags   ; only mark done on a completed trade
	ld a, TRADE_FOR_RANDOM
	ld c, a
	ld b, FLAG_TEST
	predef FlagActionPredef
	ld a, c
	and a
	ret z                        ; declined/wrong mon - leave the offer available
	SetEvent EVENT_OFFERED_LEGENDARY_TRADE_GYM8
	ret

