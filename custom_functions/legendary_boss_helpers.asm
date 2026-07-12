; Legendary Boss Challenge — Helper Routines
; Lives in the "rogue" ROMX section (see main.asm). Callers in a different
; bank (e.g. scripts/*.asm map scripts) MUST use farcall, not call.

; ReverseLookupPokemonClass
; Input: b = species
; Output: c = class (1=pokeball, 2=greatball, 3=ultraball, 4=masterball/uber)
; Clobbers: a, e, hl
; Same scan pattern as PCTraderSuperNerdSetup (scripts/IndigoPlateauLobby.asm).
ReverseLookupPokemonClass::
	ld hl, pokemon_classes
	ld e, 0
.loopclass
	inc e
	ld a, [hli]
	cp b
	jr nz, .loopclass
	ld a, pokeball_pokemon_number
	ld c, 1
	cp e
	jr nc, .done
	ld a, greatball_pokemon_number
	inc c
	cp e
	jr nc, .done
	ld a, ultraball_pokemon_number
	inc c
	cp e
	jr nc, .done
	inc c                       ; masterball (also catches uber_class - no ceiling check, matches existing convention)
.done
	ret

; HasMasterballClassMon: Scan wPartySpecies (FF-terminated) for any
; masterball-class mon via the pokemon_classes reverse lookup.
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

; GetLegendaryForLeader: Return Mew or Mewtwo based on wGymLeaderNo.
; wGymLeaderNo: 4(Erika)->Mew, 6(Sabrina)->Mewtwo, 7(Blaine)->Mew, 8(Giovanni)->Mewtwo
; Output: a = species
GetLegendaryForLeader::
	ld a, [wGymLeaderNo]
	cp 4
	jr z, .returnMew
	cp 6
	jr z, .returnMewtwo
	cp 7
	jr z, .returnMew
	cp 8
	jr z, .returnMewtwo
	ld a, MEW                   ; fallback
	ret
.returnMew
	ld a, MEW
	ret
.returnMewtwo
	ld a, MEWTWO
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
; species directly instead. GetLegendaryForLeader is still correct for the
; IN-BATTLE substitution (PatchLegendaryBossSpecies), which reads wGymLeaderNo
; before EndOfBattle runs.
; Input: b = species to give (MEW or MEWTWO)
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
	push de                      ; ReverseLookupPokemonClass clobbers e - must preserve our write pointer
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
; (Moves struct byte 5) - same pattern as OverrideGamblerMoves. Works for any
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
; PatchLegendaryBossSpecies
; Called via farcall from ReadTrainer's .SpecialTrainer loop, right after
; farcall PatchRivalStarterSpecies (same call convention). If Challenge 11 is
; active, wGymLeaderNo is one of the four eligible leaders (4/6/7/8), and the
; mon just read into wCurPartySpecies is the team's ACE (last mon), substitute
; the fixed legendary (Mew/Mewtwo) into wCurPartySpecies before AddPartyMon.
;
; NOTE ON THE ACE PEEK: farcall (macros/farcall.asm -> Bankswitch) clobbers a,
; bc, and hl before jumping to the callee, so hl does NOT carry the caller's
; trainer-data cursor in here - only d/e survive a farcall. The caller peeks
; the byte AFTER the species (the level of the next mon, or the 0 terminator)
; and passes it in e. e == 0 means the mon just read is the last/ace mon.
; Input: e = terminator-peek byte (0 => this is the ace/last mon of the team)
; Clobbers: a  (reads e; leaves hl untouched - caller preserves its own cursor)
; ============================================================
PatchLegendaryBossSpecies::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_LEGENDARY_BOSS
	ret nz
	ld a, [wGymLeaderNo]
	cp 4
	jr z, .leaderOk
	cp 6
	jr z, .leaderOk
	cp 7
	jr z, .leaderOk
	cp 8
	jr z, .leaderOk
	ret                          ; not an eligible leader - no-op
.leaderOk
	ld a, e
	and a
	ret nz                       ; not the ace/last mon - no-op
	call GetLegendaryForLeader   ; a = MEW or MEWTWO (same bank, plain call)
	ld [wCurPartySpecies], a
	ret

; ============================================================
; ApplyLegendaryBossMoveset
; Called via farcall from ReadTrainer's .SpecialTrainer loop, right after
; AddPartyMon adds the just-loaded mon to the enemy party. If that mon is the
; legendary (Mew/Mewtwo - no vanilla trainer data uses these, so this species
; check alone is a safe gate), build the themed moveset and write it into the
; last-added ENEMY mon's MON_MOVES + MON_PP fields.
; Input: none (reads wCurPartySpecies / wEnemyPartyCount)
; Clobbers: a, b, c, d, e, hl
; ============================================================
ApplyLegendaryBossMoveset::
	ld a, [wCurPartySpecies]
	cp MEW
	jr z, .isLegendary
	cp MEWTWO
	ret nz                       ; not a legendary - no-op
.isLegendary
	ld b, a                      ; b = species (MEW/MEWTWO)
	call BuildLegendaryMoveset   ; writes wBuffer+6..9 (same bank, plain call)
	; hl = last-added enemy mon's MON_MOVES = wEnemyMon1Moves + (count-1)*struct
	ld a, [wEnemyPartyCount]
	dec a
	ld hl, wEnemyMon1Moves
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes               ; hl -> this mon's MON_MOVES
	call ApplyLegendaryMoveset   ; writes moves + PP (same bank, plain call)
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
; accepted AND the party still holds a masterball-class mon. The per-leader
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
	ld b, MEW                    ; Erika's legendary (see GetLegendaryForLeader)
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
	ld b, MEWTWO                 ; Sabrina's legendary (see GetLegendaryForLeader)
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
	ld b, MEW                    ; Blaine's legendary (see GetLegendaryForLeader)
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
	ld b, MEWTWO                 ; Giovanni's legendary (see GetLegendaryForLeader)
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

IF DEF(_DEBUG)
; Debug2ApplyRoundState  (debug builds only)
; Applies the Debug 2 new-game extras that only touch WRAM, so this can live
; here in the rogue bank (reached via farcall from PrepareNewGameDebug in bank1,
; which was over its size limit with this inline). Reads wBattleCount.
;   - Rival's starter = Porygon.
;   - Money = half of max (500000, 3-byte BCD $50 $00 $00).
;   - gyms completed = wBattleCount / 10 -> wObtainedBadges = (1 << gyms) - 1
;     (clamped to 8), overriding the shared 7-badge debug default.
;   - remainder = wBattleCount mod 10 -> rem >= 6 sets BIT_ROGUE_GYM_NEXT (gym
;     next), else clears it (route next), so the lobby door matches.
Debug2ApplyRoundState::
	ld a, PORYGON
	ld [wRivalStarter], a
	ld a, $50
	ld [wPlayerMoney], a
	xor a
	ld [wPlayerMoney + 1], a
	ld [wPlayerMoney + 2], a
	ld a, [wBattleCount]
	ld b, 0                    ; b = quotient = gyms completed
.div
	cp 10
	jr c, .divDone
	sub 10
	inc b
	jr .div
.divDone
	ld c, a                    ; c = remainder (0-9)
	ld a, b                    ; clamp gyms completed to the 8 badge bits
	cp 8
	jr c, .clampOk
	ld b, 8
.clampOk
	ld a, b                    ; wObtainedBadges = (1 << gyms) - 1 (0 if none)
	and a
	jr z, .writeBadges
	ld d, b
	xor a
.badgeLoop
	scf
	rla                        ; mask = (mask << 1) | 1
	dec d
	jr nz, .badgeLoop
.writeBadges
	ld [wObtainedBadges], a
	ld hl, wRogueFlagsBitfield
	ld a, c
	cp 6
	jr c, .routeNext
	set BIT_ROGUE_GYM_NEXT, [hl]
	jr .forcedStagePrompt
.routeNext
	res BIT_ROGUE_GYM_NEXT, [hl]
.forcedStagePrompt
	; Follow-up prompt: pick which specific gym (1-8) or route (1-21) the next
	; lobby door leads to, or leave it random. Entry 1 = random (no override);
	; entry N (N>=2) forces gym/route (N-1). The choice is contingent on the
	; battle count: the gym-vs-route flag (just set from the remainder)
	; selects the max, and _PickNextStage forces this index on lobby entry.
	; Uses the same counter UI as the battle-count prompt (font/text-box tiles
	; already loaded by caller).
	ld a, [wRogueFlagsBitfield]
	bit BIT_ROGUE_GYM_NEXT, a
	ld a, 22                   ; route next: 1 (random) + NUM_STAGE_MAPS (21) routes
	jr z, .haveMax
	ld a, 9                    ; gym next: 1 (random) + 8 gyms
.haveMax
	ld [wMaxItemQuantity], a
	xor a
	ld [wListMenuID], a
	call DisplayChooseQuantityMenu
	ld a, [wItemQuantity]
	dec a                       ; 1 (random) -> 0 (wDebug2ForcedStage's existing
	                             ; "no force" sentinel, see _PickNextStage);
	                             ; 2..max -> 1..(max-1), the 1-based gym/route
	                             ; index _PickNextStage already expects
	ld [wDebug2ForcedStage], a
	ret
ENDC
