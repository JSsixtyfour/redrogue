; try to evolve the mon in [hWhichPokemon]
TryEvolvingMon:
	ld hl, wCanEvolveFlags
	xor a
	ld [hl], a
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, FLAG_SET
	call Evolution_FlagAction

; Shared by level-up, stone and trade evolution, including mid-battle level-ups.
EvolutionAfterBattle:
	; Mid-battle level-ups cannot inherit a previous stone/trade context.
	ldh a, [hIsInBattle]
	and a
	jr z, .contextReady
	xor a
	ld [wForceEvolution], a
.contextReady
	ldh a, [hTileAnimations]
	push af
	xor a
	ld [wEvolutionOccurred], a
	dec a
	ldh [hWhichPokemon], a
	push hl
	push bc
	push de
	ld hl, wPartyCount
	push hl

Evolution_PartyMonLoop: ; loop over party mons
	ld hl, hWhichPokemon
	inc [hl]
	pop hl
	inc hl
	ld a, [hl]
	cp $ff ; have we reached the end of the party?
	jp z, .done
	ld [wEvoOldSpecies], a
	push hl
	; Fusion (Phase 3): fusions never evolve - skip immediately if this party
	; mon is flagged as the fusion. de = struct base is IsFusionMon's input
	; (NOT hl - farcall clobbers hl as its own jump vector; see
	; IsFusionMon's doc comment in custom_functions/func_fusion.asm). hl is
	; already saved on the stack above (this loop's own convention), so it's
	; free to clobber here.
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	farcall IsFusionMon
	jp nz, Evolution_PartyMonLoop  ; is the fusion - skip to next mon
	; Special form (func_special_form.asm): SF_NO_EVOLVE (Light Ball Pikachu)
	; also never evolves. Every evolution path - after-battle level-up, stone
	; item use, and Rare Candy - funnels through this loop, so this one check
	; covers them all. GetSpecialFormCaps returns caps in e (not a - farcall
	; clobbers a); de = this mon's struct base on entry (d preserved, e = caps out).
	farcall GetSpecialFormCaps
	bit SF_NO_EVOLVE, e
	jp nz, Evolution_PartyMonLoop
	; Paradox forms and plain Farfetch'd never evolve (FormNoEvolve).
	call IsPartyMonEvoBlocked
	jp c, Evolution_PartyMonLoop
	ldh a, [hWhichPokemon]
	ld c, a
	ld hl, wCanEvolveFlags
	ld b, FLAG_TEST
	call Evolution_FlagAction
	ld a, c
	and a ; is the mon's bit set?
	jp z, Evolution_PartyMonLoop ; if not, go to the next mon
	ld a, [wEvoOldSpecies]
	dec a
	ld b, 0
	ld hl, EvosMovesPointerTable
	add a
	rl b
	ld c, a
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	push hl
	ld a, [wCurPartySpecies]
	push af
	xor a ; PLAYER_PARTY_DATA
	ld [wMonDataLocation], a
	call LoadMonData
	pop af
	ld [wCurPartySpecies], a
	pop hl

.evoEntryLoop ; loop over evolution entries
	ld a, [hli]
	and a ; have we reached the end of the evolution data?
	jr z, Evolution_PartyMonLoop
	ld b, a ; evolution type
	ld a, [wForceEvolution]
	and a
	jr z, .normalEvolutionChecks
	ld a, [wEvoStoneItemID]
	cp MIST_STONE
	jr nz, .normalEvolutionChecks
	ld a, b
	cp EVOLVE_ITEM
	jr nz, .mistSkipRequirement
	inc hl                       ; ignore required item
.mistSkipRequirement
	inc hl                       ; ignore minimum level
	ld a, [wEvoNewSpecies]
	cp [hl]
	jr z, .mistDoEvolution
	inc hl
	jp .evoEntryLoop
.mistDoEvolution
	ld a, [wLoadedMonLevel]
	jr .doEvolution
.normalEvolutionChecks
	ld a, b
	cp EVOLVE_TRADE
	jr z, .checkTradeEvo
; not trade evolution
	ld a, [wLinkState]
	cp LINK_STATE_TRADING
	jp z, Evolution_PartyMonLoop ; if trading, go the next mon
	ld a, b
	cp EVOLVE_ITEM
	jr z, .checkItemEvo
	ld a, [wForceEvolution]
	and a
	jp nz, Evolution_PartyMonLoop
	ld a, b
	cp EVOLVE_LEVEL
	jr z, .checkLevel
.checkTradeEvo
	ld a, [wLinkState]
	cp LINK_STATE_TRADING
	jr nz, .tradeLevelEvo
; Trading bypasses the level requirement; hl must point at the target species.
	inc hl
	ld a, [wLoadedMonLevel]
	jr .doEvolution
.tradeLevelEvo
; Otherwise use the authored level threshold, only on ordinary level-up checks.
	ld a, [wForceEvolution]
	and a
	jp nz, .nextEvoEntry1
	jr .checkLevel
.checkItemEvo
	ld a, [hli]
	ld e, a ; evolution item (de is scratch in this loop)
	; Trade context was rejected above; require explicit stone use.
	ld a, [wForceEvolution]
	and a
	jp z, .nextEvoEntry1
	; wCurItem aliases the species; use the stable stone-menu item ID. A form
	; may need a different stone than the entry names (Alolan Vulpix: Ice).
	call EvoStoneMatchesUsed ; was the evolution item in this entry used?
	jp nz, .nextEvoEntry1 ; if not, go to the next evolution entry
.checkLevel
	ld a, [hli] ; level requirement
	ld b, a
	ld a, [wLoadedMonLevel]
	cp b ; is the mon's level greater than the evolution requirement?
	jp c, .nextEvoEntry2 ; if so, go the next evolution entry
.doEvolution
; Species Groups Phase 2: every evolution method converges here, with hl on the
; target species byte and a holding the mon's level. An evolution whose TARGET
; belongs to a locked or toggled-off species group must not fire - otherwise a
; Kanto Poliwhirl becomes a Johto Politoed with Johto locked, and a Piloswine
; becomes a Warp-group Mamoswine with Kanto Time Warp locked. Gating per ENTRY
; rather than per species keeps split evolutions independent: with Johto off
; and Warp on, Scyther still reaches Kleavor even though Scizor is blocked.
;
; The check is a farcall (RogueIsSpeciesEvolutionAllowed is in the rarity bank),
; which destroys a/b/c/h/l - so the level goes on the stack and hl is saved
; around it. `pop hl` does not touch flags, so the callee's carry survives to
; the branch below; the later `pop af` is only reached after that branch.
	push af                      ; mon level, consumed just below
	push hl                      ; evo-table cursor
	ld e, [hl]                   ; target species - in e, NOT a: Bankswitch's
	                             ; first instruction overwrites a, so an `a`
	                             ; input cannot survive a farcall
	farcall RogueIsSpeciesEvolutionAllowedFar
	pop hl
	jr nc, .evoBlocked
; The species check above cannot see eeveelution FORMS: Espeon is JOLTEON form
; 1, and JOLTEON is Kanto, so Leaf/Moon Stones made Leafeon/Sylveon in a
; Kanto-only run. A form-setting stone evolution also asks the roller's form
; gate (IsFormAllowed), so the two can never disagree.
	push hl
	ld c, [hl]                   ; target species
	call IsEvoStoneFormAllowed
	pop hl                       ; pop does not disturb flags
	jr c, .evoGroupActive
.evoBlocked
	pop af                       ; discard the saved level, keep the stack even
	jp .nextEvoEntry2            ; hl is still on the species byte - skip past it
.evoGroupActive
	pop af
	ld [wCurEnemyLevel], a
	ld a, 1
	ld [wEvolutionOccurred], a
	push hl
	ld a, [hl]
	ld [wEvoNewSpecies], a
	ldh a, [hWhichPokemon]
	ld hl, wPartyMonNicks
	call GetPartyMonName
	call CopyToStringBuffer
	ld hl, IsEvolvingText
	call PrintText
	ld c, 50
	call DelayFrames
	xor a
	ldh [hAutoBGTransferEnabled], a
	hlcoord 0, 0
	lb bc, 12, 20
	call ClearScreenArea
	ld a, $1
	ldh [hAutoBGTransferEnabled], a
	ld a, $ff
	ldh [hUpdateSpritesEnabled], a
	call ClearSprites
	ld a, [wEvoNewSpecies]     ; the animation's new pic and palette need the
	ld c, a                    ; evolved form (A-Ninetales, Espeon), which
	call GetEvolvedForm        ; ApplyEvoStoneForm only writes afterwards
	ld [wEvoNewForm], a
	callfar EvolveMon
	jp c, CancelledEvolution
	ld hl, EvolvedText
	call PrintText
	pop hl
	ld a, [hl]
	ld [wCurSpecies], a
	ld [wLoadedMonSpecies], a
	ld [wEvoNewSpecies], a
	ld a, MONSTER_NAME
	ld [wNameListType], a
	ld a, BANK(TrainerNames) ; bank is not used for monster names
	ld [wPredefBank], a
	push hl
	call PublishEvolvedNameForm ; "into SYLVEON", not "into VAPOREON"
	pop hl
	call GetName
	push hl
	ld hl, IntoText
	call PrintText_NoCreatingTextBox
	ld a, SFX_GET_ITEM_2
	call PlaySoundWaitForCurrent
	call WaitForSoundToFinish
	ld c, 40
	call DelayFrames
	call ClearScreen
	call RenameEvolvedMon
; Species Groups Phase 2R (plan 2R.8a). This USED TO BE a hand-rolled copy of
; GetMonHeader - the same wPokedexNum save/restore, the same IndexToPokedex, the
; same AddNTimes into BaseStats, the same wMonHIndex write - reading the ROM
; table directly. There were exactly TWO direct readers of BaseStats in the whole
; tree, GetMonHeader and this one, and because the form hook lives inside
; GetMonHeader this copy silently bypassed it: an Alolan Meowth evolving into
; Persian got vanilla Persian's stats, types and sprite, and the recalculation
; below baked them in.
;
; Replaced with the real call, which fixes the bypass and deletes a duplicated
; table walk. PublishFormContext carries the mon's OWN form (from wLoadedMon,
; which still holds the pre-evolution struct) onto the NEW species, so
; Meowth+Alolan -> Persian+Alolan. Form-preserving evolution is the default and
; this is what implements it for the header; the flag itself already survives,
; because the party struct is copied back from wLoadedMon afterwards.
	call ApplyEvoStoneForm ; Phase 2R: form-SETTING evolutions (eeveelutions)
	ld hl, wLoadedMon
	call PublishFormContext
	call GetMonHeader
	ld hl, wLoadedMonHPExp - 1
	ld de, wLoadedMonStats
	ld b, $1
	push bc
	push hl
	farcall PrepareFusionAndBridgeRayCalcStats
	pop hl
	pop bc
	call CalcStats
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld e, l
	ld d, h
	push hl
	push bc
	ld bc, MON_MAXHP
	add hl, bc
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ld hl, wLoadedMonMaxHP + 1
	ld a, [hld]
	sub c
	ld c, a
	ld a, [hl]
	sbc b
	ld b, a
	ld hl, wLoadedMonHP + 1
	ld a, [hl]
	add c
	ld [hld], a
	ld a, [hl]
	adc b
	ld [hl], a
	dec hl
	pop bc
	call CopyData
	ld a, [wCurSpecies]
	ld [wPokedexNum], a
	xor a
	ld [wMonDataLocation], a
	; Battle EXP already offered every crossed-level move before evolution, using
	; the species that existed at each point in the timeline. Do not add a second,
	; evolved-species move at the same final level. Stone, trade, and Rare Candy
	; evolutions occur out of battle and retain the established behavior below.
	ldh a, [hIsInBattle]
	and a
	jr nz, .skipPostEvolutionLevelMove
; Re-publish before the learnset read. The header loaded up at the evolution's
; own PublishFormContext/GetMonHeader pair is the right one, but
; PrepareFusionAndBridgeRayCalcStats sits between it and here and may load a
; header of its own; that would leave wMonHFormSpecies naming a different mon
; and GetEvosMovesEntry would silently fall back to the base species' learnset.
; wLoadedMon still holds this mon's struct (the CopyData above copies FROM it),
; so its MON_CATCH_RATE still carries the form, and wCurSpecies is already the
; POST-evolution species - which is what the new learnset should be keyed on.
	ld hl, wLoadedMon
	call PublishFormContext
	call GetMonHeader
	call LearnMoveFromLevelUp
	jr .finishedPostEvolutionLevelMove
.skipPostEvolutionLevelMove
	ld a, [wCurSpecies]
	ld [wCurPartySpecies], a
.finishedPostEvolutionLevelMove
	; NOTE: this LearnMoveFromLevelUp is the EVOLUTION path (learn the NEW
	; species' moves after evolving) - NOT the normal level-up path. A fusion
	; can never evolve (Phase 3 blocks it), so no fusion hook belongs here.
	; The real level-up learn sites are experience.asm (battle level-up) and
	; item_effects.asm (rare candy); the Phase 5b hook lives there.
	pop hl
	; SetPartyMonTypes normally replaces both stored types with the evolved
	; species' base types. Preserve MON_TYPE2 for a type variant so evolution
	; cannot silently change the variant while leaving its flag set.
	push hl
	push hl
	ld bc, MON_CATCH_RATE
	add hl, bc
	bit BIT_TYPE_VARIANT, [hl]
	pop hl
	jr z, .setBaseEvolutionTypes
	push hl
	ld bc, MON_TYPE2
	add hl, bc
	ld a, [hl]
	pop hl
	push af
	predef SetPartyMonTypes
	pop af
	pop hl
	ld bc, MON_TYPE2
	add hl, bc
	ld [hl], a
	jr .evolutionTypesSet
.setBaseEvolutionTypes
	predef SetPartyMonTypes
	pop hl
.evolutionTypesSet
	ldh a, [hIsInBattle]
	and a
	call z, Evolution_ReloadTilesetTilePatterns
	predef IndexToPokedex
	ld a, [wPokedexNum]
	dec a
	ld c, a
	ld b, FLAG_SET
	ld hl, wPokedexOwned
	push bc
	call Evolution_FlagAction
	pop bc
	ld hl, wPokedexSeen
	call Evolution_FlagAction
	pop de
	pop hl
	ld a, [wLoadedMonSpecies]
	ld [hl], a
	push hl
	ld l, e
	ld h, d
	jr .nextEvoEntry2

.nextEvoEntry1
	inc hl

.nextEvoEntry2
	inc hl
	jp .evoEntryLoop

.done
	xor a
	ld [wForceEvolution], a
	ld [wEvoStoneItemID], a
	pop de
	pop bc
	pop hl
	pop af
	ldh [hTileAnimations], a
	ld a, [wLinkState]
	cp LINK_STATE_TRADING
	ret z
	ldh a, [hIsInBattle]
	and a
	ret nz
	ld a, [wEvolutionOccurred]
	and a
	call nz, PlayDefaultMusic
	ret

RenameEvolvedMon:
; Renames the mon to its new, evolved form's standard name unless it had a
; nickname, in which case the nickname is kept.
;
; Both name lookups must be FORM-aware. A form's name lives in its form record
; and GetMonName only returns it when a form context is published for that
; exact species. Without it, an A-Vulpix's "A-VULPIX" never matched the plain
; "VULPIX" and was misread as a nickname (stuck forever), and an Eevee that
; became Sylveon (VAPOREON form 2) was renamed "VAPOREON". wLoadedMon still
; holds the PRE-evolution struct here: ApplyEvoStoneForm runs after this.
	ASSERT wCurSpecies == wNameListIndex ; save+restore wCurSpecies while using wNameListIndex
	ld a, [wCurSpecies]
	push af
	ld a, [wMonHIndex]
	ld [wNameListIndex], a
	ld [wFormContextSpecies], a  ; old side: the mon's own, current form
	ld a, [wLoadedMon + MON_CATCH_RATE]
	and FORM_MASK
	rlca                         ; bits 5-6 -> 0-3
	rlca
	rlca
	ld [wFormContextForm], a
	call GetName
	pop af
	ld [wCurSpecies], a
	ld hl, wNameBuffer
	ld de, wStringBuffer
.compareNamesLoop
	ld a, [de]
	inc de
	cp [hl]
	inc hl
	ret nz
	cp '@'
	jr nz, .compareNamesLoop
	call PublishEvolvedNameForm  ; new side: the form it evolves into. Before
	                             ; `ld bc`: it clobbers bc, CopyData's length
	ldh a, [hWhichPokemon]
	ld bc, NAME_LENGTH
	ld hl, wPartyMonNicks
	call AddNTimes
	push hl
	call GetName
	ld hl, wNameBuffer
	pop de
	jp CopyData

; Publishes the form the evolving mon WILL have, so the next GetName names it
; (SYLVEON, A-PERSIAN) instead of the bare species. Separate from
; PublishFormContext because the new form is not in any struct yet.
; IN:  wCurSpecies = species being evolved into; wLoadedMon = the mon BEFORE
;      evolution (GetEvolvedForm's contract)
; CLOBBERS: af, b, c, hl
PublishEvolvedNameForm:
	ld a, [wCurSpecies]
	ld c, a
	call GetEvolvedForm
	ld [wFormContextForm], a
	ld a, [wCurSpecies]
	ld [wFormContextSpecies], a
	ret

CancelledEvolution:
	ld hl, StoppedEvolvingText
	call PrintText
	call ClearScreen
	pop hl
	ldh a, [hIsInBattle]
	and a
	call z, Evolution_ReloadTilesetTilePatterns
	jp Evolution_PartyMonLoop

EvolvedText:
	text_far _EvolvedText
	text_end

IntoText:
	text_far _IntoText
	text_end

StoppedEvolvingText:
	text_far _StoppedEvolvingText
	text_end

IsEvolvingText:
	text_far _IsEvolvingText
	text_end

Evolution_ReloadTilesetTilePatterns:
	ld a, [wLinkState]
	cp LINK_STATE_TRADING
	ret z
; Shin Red import Phase 6: if the mon learned a move after evolving there is still a
; text box on screen at this point, and ReloadTilesetTilePatterns turns the LCD off and
; back on, which makes that box visibly flicker. White out first so the reload is not
; seen.
	call GBPalWhiteOutWithDelay3
	jp ReloadTilesetTilePatterns

LearnMoveFromLevelUp:
	ld a, [wPokedexNum] ; species
	ld [wCurPartySpecies], a
	call GetEvosMovesEntry ; the form's learnset if the loaded header carries one
.skipEvolutionDataLoop ; loop to skip past the evolution data, which comes before the move data
	ld a, [hli]
	and a ; have we reached the end of the evolution data?
	jr nz, .skipEvolutionDataLoop ; if not, jump back up
.learnSetLoop ; loop over the learn set until we reach a move that is learnt at the current level or the end of the list
	ld a, [hli]
	and a ; have we reached the end of the learn set?
	jr z, .done ; if we've reached the end of the learn set, jump
	ld b, a ; level the move is learnt at
	ld a, [wCurEnemyLevel]
	cp b ; is the move learnt at the mon's current level?
	ld a, [hli] ; move ID
	jr nz, .learnSetLoop
; A mon can be taught more than one move at the same level. hl is the learnset
; cursor and is about to be repurposed to walk the mon's current move list, so
; save it and resume the scan afterwards instead of falling into .done, which
; silently dropped every move after the first one at this level.
	push hl
	ld d, a ; ID of move to learn
	ld a, [wMonDataLocation]
	and a
	jr nz, .next
; If [wMonDataLocation] is 0 (PLAYER_PARTY_DATA), get the address of the mon's
; current moves in party data. Every call to this function sets
; [wMonDataLocation] to 0 because other data locations are not supported.
; If it is not 0, this function will not work properly.
	ld hl, wPartyMon1Moves
	ldh a, [hWhichPokemon]
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
.next
	ld b, NUM_MOVES
.checkCurrentMovesLoop ; check if the move to learn is already known
	ld a, [hli]
	cp d
	jr z, .nextLearnSetEntry ; if already known, jump
	dec b
	jr nz, .checkCurrentMovesLoop
	ld a, d
	ld [wMoveNum], a
	ld [wNamedObjectIndex], a
	call GetMoveName
	call CopyToStringBuffer
	predef LearnMove
.nextLearnSetEntry
	pop hl ; learnset cursor saved above
	jr .learnSetLoop
.done
	ld a, [wCurPartySpecies]
	ld [wPokedexNum], a
	ret

; writes the moves a mon has at level [wCurEnemyLevel] to [de]
; move slots are being filled up sequentially and shifted if all slots are full
WriteMonMoves:
	call GetPredefRegisters
	push hl
	push de
	push bc
; de is the destination move slots and must survive; GetEvosMovesEntry does not
; touch it. bc is already saved above, so clobbering it here is free.
	ld a, [wCurPartySpecies]
	call GetEvosMovesEntry
.skipEvoEntriesLoop
	ld a, [hli]
	and a
	jr nz, .skipEvoEntriesLoop
	jr .firstMove
.nextMove
	pop de
.nextMove2
	inc hl
.firstMove
	ld a, [hli]       ; read level of next move in learnset
	and a
	jp z, .done       ; end of list
	ld b, a
	ld a, [wCurEnemyLevel]
	cp b
	jp c, .done       ; mon level < move level (assumption: learnset is sorted by level)
	ld a, [wLearningMovesFromDayCare]
	and a
	jr z, .skipMinLevelCheck
	ld a, [wDayCareStartLevel]
	cp b
	jr nc, .nextMove2 ; min level >= move level

.skipMinLevelCheck

; check if the move is already known
	push de
	ld c, NUM_MOVES
.alreadyKnowsCheckLoop
	ld a, [de]
	inc de
	cp [hl]
	jr z, .nextMove
	dec c
	jr nz, .alreadyKnowsCheckLoop

; try to find an empty move slot
	pop de
	push de
	ld c, NUM_MOVES
.findEmptySlotLoop
	ld a, [de]
	and a
	jr z, .writeMoveToSlot2
	inc de
	dec c
	jr nz, .findEmptySlotLoop

; no empty move slots found
	pop de
	push de
	push hl
	ld h, d
	ld l, e
	call WriteMonMoves_ShiftMoveData ; shift all moves one up (deleting move 1)
	ld a, [wLearningMovesFromDayCare]
	and a
	jr z, .writeMoveToSlot

; shift PP as well if learning moves from day care
	push de
	ld bc, MON_PP - (MON_MOVES + 3)
	add hl, bc
	ld d, h
	ld e, l
	call WriteMonMoves_ShiftMoveData ; shift all move PP data one up
	pop de

.writeMoveToSlot
	pop hl
.writeMoveToSlot2
	ld a, [hl]
	ld [de], a
	ld a, [wLearningMovesFromDayCare]
	and a
	jr z, .nextMove

; write move PP value if learning moves from day care
	push hl
	ld a, [hl]
	ld hl, MON_PP - MON_MOVES
	add hl, de
	push hl
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld de, wBuffer
	ld a, BANK(Moves)
	call FarCopyData
	ld a, [wBuffer + 5]
	pop hl
	ld [hl], a
	pop hl
	jr .nextMove

.done
	pop bc
	pop de
	pop hl
	ret

; shifts all move data one up (freeing 4th move slot)
WriteMonMoves_ShiftMoveData:
	ld c, NUM_MOVES - 1
.loop
	inc de
	ld a, [de]
	ld [hli], a
	dec c
	jr nz, .loop
	ret

Evolution_FlagAction:
	predef_jump FlagActionPredef
    
; From here, Move Relearner-related code -PvK
;joenote - custom function by Mateo for move relearner
PrepareRelearnableMoveList:: ; I don't know how the fuck you're a single colon in shin pokered but it sure as shit doesn't work here - PvK
; Loads relearnable move list to wRelearnableMoves.
; Input: party mon index = [hWhichPokemon]
	; Get mon id.
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl] ; a = mon id
	ld [wCurSpecies], a	;joenote - put mon id into wram for potential later usage of GetMonHeader
; Load THIS mon's header, with its form applied, before anything below reads a
; learnset or wMonHMoves. That used to happen only down at .done (the level-0
; move scan) and without a published context, so the relearner offered an Alolan
; Marowak vanilla Marowak's starting moves AND vanilla Marowak's learnset.
; PublishFormContext takes the struct base in hl and reads the form out of its
; MON_CATCH_RATE; the GetMonHeader at .done is then a same-species reload, which
; ApplyFormOverride's refresh guard re-applies the same form to.
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1
	ld bc, wPartyMon2 - wPartyMon1
	call AddNTimes
	call PublishFormContext
	call GetMonHeader
	; Get pointer to evos moves data.
	ld a, [wCurSpecies]
	call GetEvosMovesEntry
	push hl ; hl = pointer to evos moves data for our mon
	; Get pointer to mon's currently-known moves.
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1Level
	ld bc, wPartyMon2 - wPartyMon1
	call AddNTimes
	ld a, [hl]
	ld b, a
	push bc
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1Moves
	ld bc, wPartyMon2 - wPartyMon1
	call AddNTimes
	pop bc
	ld d, h
	ld e, l
	pop hl
	; Skip over evolution data.
.skipEvoEntriesLoop
	ld a, [hli]
	and a
	jr nz, .skipEvoEntriesLoop
	; Write list of relearnable moves, while keeping count along the way.
	; de = pointer to mon's currently-known moves
	; hl = pointer to moves data for our mon
	;  b = mon's level
	ld c, 0 ; c = count of relearnable moves
	xor a
	ld [wMoveBuffer], a ; initialize the output count before the first append
.loop
	ld a, [hli]
	and a
	jr z, .done
	cp b
	jr c, .addMove
	jr nz, .done
.addMove
	ld a, [hli] ; move id
	; Save the level and learnset cursor; the helper returns the new count in c.
	push bc
	push hl
	call .AppendRelearnableMove
	pop hl
	pop af
	ld b, a ; restore the mon level saved in b, keeping helper's count in c
	jr .loop
.done	


;joenote - start checking for level-0 moves
	xor a
	ld b, a	;b will act as a counter, as there can only be up to 4 level-0 moves
	call GetMonHeader ;mon id already stored earlier in wd0b5. Same-species
	                  ;reload: ApplyFormOverride's refresh guard re-applies the
	                  ;form published at the top of this routine, so wMonHMoves
	                  ;below is the FORM's level-1 moves.
	ld hl, wMonHMoves
.loop2
	ld a, b	;get the current loop counter into a
	cp $4
	jr nc, .done2	;if gone through 4 moves already, reached the end of the list. move to done2.
	ld a, [hl]	;load move
	and a
	jr z, .done2	;if move has id 0, list has reached the end early. move to done2.
	; Preserve the base-move index and source cursor; the helper handles both
	; known-move filtering and deduplication against the existing output list.
	push bc
	push hl
	call .AppendRelearnableMove
	pop hl
	pop af
	ld b, a ; restore the base-move index saved in b
	inc hl	;increment to the next level-0 move
	inc b	;increment the loop counter
	jr .loop2
	
.done2
	ld b, 0
	ld hl, wMoveBuffer + 1
	add hl, bc
	ld a, $ff
	ld [hl], a
	ld hl, wMoveBuffer
	ld [hl], c
	ret

.AppendRelearnableMove
; Input: a = move id, de = pointer to mon's currently-known moves, c = output count
; Output: c = updated output count. Preserves de.
	ld b, a
	push de
	; Check if move is already known by our mon.
	ld a, [de]
	cp b
	jr z, .alreadyKnown
	inc de
	ld a, [de]
	cp b
	jr z, .alreadyKnown
	inc de
	ld a, [de]
	cp b
	jr z, .alreadyKnown
	inc de
	ld a, [de]
	cp b
	jr z, .alreadyKnown
	pop de
	; Check if move is already in the output list. Keep the input count in c
	; across this scan so duplicate candidates return the unchanged count.
	ld a, [wMoveBuffer]
	and a
	jr z, .appendMove
	push bc
	ld c, a
	ld hl, wMoveBuffer + 1
	ld a, b
.bufferLoop
	cp [hl]
	jr z, .alreadyInBuffer
	inc hl
	dec c
	jr nz, .bufferLoop
	pop bc
.appendMove
	ld a, b
	ld hl, wMoveBuffer
	inc [hl]
	ld c, [hl]
	ld b, 0
	add hl, bc
	ld [hl], a
	ret
.alreadyInBuffer
	pop bc
	ret
.alreadyKnown
	pop de
	ret

; Modified version of Move Relearner code used for Move Tutors
PrepareMoveTutorList::
; Loads relearnable move list to wRelearnableMoves.
; Input: party mon index = [hWhichPokemon]
	; Get mon id.
	ldh a, [hWhichPokemon]
	ld c, a
	ld b, 0
	ld hl, wPartySpecies
	add hl, bc
	ld a, [hl] ; a = mon id
	ld [wCurSpecies], a	;joenote - put mon id into wram for potential later usage of GetMonHeader
	; Get pointer to evos moves data.
	dec a
	ld c, a
	ld b, 0
	ld hl, EvosMovesPointerTable
	add hl, bc
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a  ; hl = pointer to evos moves data for our mon
	push hl
	; Get pointer to mon's currently-known moves.
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1Level
	ld bc, wPartyMon2 - wPartyMon1
	call AddNTimes
	ld a, [hl]
	ld b, a
	push bc
	ldh a, [hWhichPokemon]
	ld hl, wPartyMon1Moves
	ld bc, wPartyMon2 - wPartyMon1
	call AddNTimes
	pop bc
	ld d, h
	ld e, l
	pop hl
	; Skip over evolution data.
.skipEvoEntriesLoop
	ld a, [hli]
	and a
	jr nz, .skipEvoEntriesLoop
.skipLearnsetLoop
	ld a, [hli]
	and a
	jr nz, .skipLearnsetLoop
	; Write list of move tutor moves, while keeping count along the way.
	; de = pointer to mon's currently-known moves
	; hl = pointer to moves data for our mon
	;  b = mon's level
	ld c, 0 ; c = count of relearnable moves
.loop
	ld a, [hli]
	and a
	jr z, .done
	cp b
	jr c, .addMove
	jr nz, .done
.addMove
	push bc
	ld a, [hli] ; move id
	ld b, a
	; Check if move is already known by our mon.
	push de
	ld a, [de]
	cp b
	jr z, .knowsMove
	inc de
	ld a, [de]
	cp b
	jr z, .knowsMove
	inc de
	ld a, [de]
	cp b
	jr z, .knowsMove
	inc de
	ld a, [de]
	cp b
	jr z, .knowsMove
.tutorableMove
	pop de
	push hl
	; Add move to the list, and update the running count.
	ld a, b
	ld b, 0
	ld hl, wMoveBuffer + 1
	add hl, bc
	ld [hl], a
	pop hl
	pop bc
	inc c
	jr .loop
.knowsMove
	pop de
	pop bc
	jr .loop
.done	
	ld b, 0
	ld hl, wMoveBuffer + 1
	add hl, bc
	ld a, $ff
	ld [hl], a
	ld hl, wMoveBuffer
	ld [hl], c
	ret


INCLUDE "data/pokemon/evos_moves.asm"

; ---------------------------------------------------------------------------
; ApplyEvoStoneForm  (Species Groups Phase 2R)
;
; Almost every evolution is form-PRESERVING and needs no help: the party struct
; is copied back from wLoadedMon and nothing touches its MON_CATCH_RATE, so an
; Alolan Meowth simply stays Alolan as a Persian.
;
; The eeveelutions are the exception. Espeon, Umbreon, Leafeon, Glaceon and
; Sylveon ship as FORMS of the three Kanto eeveelutions rather than as species
; of their own, so Eevee -> Espeon has to change both the species AND the form.
; The 4-byte evolution record has no room for a form, so the mapping lives here.
;
; Keyed on the stone AND the target species, which is not redundant: MOON_STONE
; also evolves Nidorino, Nidorina, Clefairy and Jigglypuff, and none of those
; may pick up Sylveon's form index. Keying on the stone alone would hand form 2
; to every Nidoking in the game.
;
; INPUT:  wCurSpecies = the species being evolved INTO
;         wEvoStoneItemID = the stone used (0 on a level/trade evolution)
; OUTPUT: wLoadedMon's MON_CATCH_RATE form bits set, if this is a form evolution
; CLOBBERS: af, bc, hl
;
; Runs BEFORE PublishFormContext at the call site, so the header load that
; follows already sees the NEW form.
; ---------------------------------------------------------------------------
ApplyEvoStoneForm:
	ld a, [wCurSpecies]
	ld c, a
	call GetEvolvedForm
	rrca                       ; 0-3 -> bits 5-6
	rrca
	rrca
	ld b, a
	ld hl, wLoadedMon + MON_CATCH_RATE
	ld a, [hl]
	and FORM_MASK ^ $FF        ; clear any inherited form, keep the other flags
	or b
	ld [hl], a
	ret

; IN:  c = species being evolved into, wEvoStoneItemID, wLoadedMon = the mon
;      BEFORE evolution
; OUT: a = the form index (0..3) it will have: the EvoStoneForms entry for a
;      form-setting stone evolution, else the mon's own form (form-preserving)
; CLOBBERS: af, bc, hl (de PRESERVED). Shared by ApplyEvoStoneForm, the
; evolution animation (wEvoNewForm) and the name, so they can never disagree.
GetEvolvedForm:
	call FindEvoStoneForm
	ret c                      ; form-SETTING stone evolution
	ld a, [wLoadedMon + MON_CATCH_RATE]
	and FORM_MASK
	ret z                      ; base form evolves into the base form
	rlca                       ; bits 5-6 -> 0-3
	rlca
	rlca
; Form-preserving, but only into a form that exists: Galarian Farfetch'd ->
; Sirfetch'd has no SIRFETCHD form 1, so it lands on form 0 rather than keeping
; a dangling form bit.
	push de
	ld d, c                    ; d = species being evolved into
	ld e, a                    ; e = form (only d/e cross a farcall)
	push de
	farcall IsFormRecordedFar
	pop de                     ; pops and loads do not disturb the flags
	ld a, e
	pop de
	ret c
	xor a                      ; no such record: plain evolved species
	ret

; IN:  c = species being evolved into, wEvoStoneItemID
; OUT: carry SET, a = form index (1..NUM_FORM_SLOTS) if this stone evolution SETS
;      a form (EvoStoneForms hit); carry CLEAR otherwise (level/trade evolution,
;      or an ordinary form-preserving stone evolution)
; CLOBBERS: af, b, hl
FindEvoStoneForm:
	ld a, [wEvoStoneItemID]
	and a                      ; clears carry
	ret z                      ; level or trade evolution
	ld b, a
	ld hl, EvoStoneForms
.loop
	ld a, [hl]
	and a                      ; clears carry
	ret z                      ; end of table: an ordinary stone evolution
	cp b
	jr nz, .next
	inc hl
	ld a, [hl]
	dec hl
	cp c
	jr z, .found
.next
	inc hl
	inc hl
	inc hl
	jr .loop

.found
	inc hl
	inc hl
	ld a, [hl]
	and NUM_FORM_SLOTS
	scf
	ret

; May this evolution's stone-set form appear in this run? Form-preserving
; evolutions always pass: the mon already has its form, and blocking it would
; strand e.g. an Alolan Meowth whose group was toggled off mid-run.
; IN:  c = species being evolved into, wEvoStoneItemID
; OUT: carry SET = allowed
; CLOBBERS: af, bc, de, hl
IsEvoStoneFormAllowed:
	call FindEvoStoneForm
	ccf                        ; no form-setting entry -> carry set -> allow
	ret c
	ld d, c                    ; d = species
	ld e, a                    ; e = form (only d/e cross a farcall)
	farcall IsFormUnlockedFar
	ret                        ; flags survive the Bankswitch return

EvoStoneForms:
; db <stone>, <target species>, <form index>
	db LEAF_STONE,  FLAREON,  1 ; Leafeon
	db SUN_STONE,   JOLTEON,  1 ; Espeon
	db DUSK_STONE,  JOLTEON,  2 ; Umbreon
	db ICE_STONE,   VAPOREON, 1 ; Glaceon
	db MOON_STONE,  VAPOREON, 2 ; Sylveon
	db 0 ; terminator

; Is the stone the player used the one THIS mon needs for an EVOLVE_ITEM entry?
; Usually that is the entry's own stone, but a form listed in FormEvoStones
; swaps it: Alolan Vulpix keeps VulpixEvosMoves' single FIRE_STONE -> NINETALES
; entry and answers to ICE_STONE instead. Swapping the stone, rather than adding
; a second NINETALES entry, keeps a plain Vulpix off the Ice Stone and keeps the
; Mist Stone chooser from offering NINETALES twice. Evolution preserves the form,
; so the result is Alolan Ninetales with no EvoStoneForms entry.
;
; Farcall-safe: the stone goes in e and the answer comes back in the flags,
; which survive the Bankswitch return.
; IN:  e = the stone an EVOLVE_ITEM entry names; wLoadedMon = the evolving mon
; OUT: z SET if wEvoStoneItemID is the stone this mon needs for that entry
; CLOBBERS: af, e  (bc, d, hl PRESERVED - the evolution parser's hl is live)
EvoStoneMatchesUsed::
	push bc
	push hl
	ld a, [wLoadedMon + MON_CATCH_RATE]
	and FORM_MASK
	rlca                       ; bits 5-6 -> 0-3
	rlca
	rlca
	ld c, a                    ; c = the mon's form
	ld a, [wLoadedMonSpecies]
	ld b, a                    ; b = the mon's species
	ld hl, FormEvoStones
.loop
	ld a, [hli]
	and a
	jr z, .compare             ; terminator: the entry's stone stands
	cp b
	jr nz, .skipForm
	ld a, [hli]
	cp c
	jr nz, .skipStone
	ld e, [hl]                 ; this form's stone replaces the entry's
	jr .compare
.skipForm
	inc hl
.skipStone
	inc hl
	jr .loop
.compare
	ld a, [wEvoStoneItemID]
	cp e
	pop hl                     ; pops do not disturb the flags
	pop bc
	ret

FormEvoStones:
; db <species>, <form index>, <stone that replaces the EVOLVE_ITEM entry's>
	db VULPIX, 1, ICE_STONE ; Alolan Vulpix -> Alolan Ninetales
	db 0 ; terminator

; Does the party mon in slot hWhichPokemon belong to a (species, form) that never
; evolves? Checked once per mon at the top of the evolution loop, so it blocks
; every method (level, stone, Mist Stone, trade, Rare Candy); the party menu's
; ABLE/NOT ABLE and the Mist Stone chooser ask too, so neither offers one.
; Reads the party struct, not wLoadedMon: the Mist Stone chooser runs after the
; party menu, when wLoadedMon holds whichever mon was drawn last.
; IN:  hWhichPokemon = party slot
; OUT: carry SET = this mon never evolves (flags survive a farcall return)
; CLOBBERS: af, bc, hl (de PRESERVED)
IsPartyMonEvoBlocked::
	ldh a, [hWhichPokemon]
	ld hl, wPartyMons
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld a, [hl]                 ; species
	push af
	ld bc, MON_CATCH_RATE
	add hl, bc
	ld a, [hl]
	and FORM_MASK
	rlca                       ; bits 5-6 -> 0-3
	rlca
	rlca
	ld c, a                    ; c = form
	pop af
	ld b, a                    ; b = species
	jr IsFormNoEvolve

; The same question for a mon that is not in the party yet: the trainer party
; builder asks it before ScaleTrainer_evolution, with the pool entry's form.
; IN:  d = species, e = form index
; OUT: carry SET = never evolves (flags survive the farcall return)
; CLOBBERS: af, bc, hl (de PRESERVED)
IsFormNoEvolveFar::
	ld b, d
	ld c, e
	; fall through
; IN: b = species, c = form. OUT/CLOBBERS as above.
IsFormNoEvolve:
	ld hl, FormNoEvolve
.loop
	ld a, [hli]
	and a                      ; clears carry
	ret z                      ; terminator: evolves normally
	cp b
	ld a, [hli]                ; loads do not disturb the flags
	jr nz, .loop
	cp c
	jr nz, .loop
	scf
	ret

FormNoEvolve:
; db <species>, <form index>
	db JIGGLYPUFF, 1 ; Scream Tail: paradox
	db MAGNETON,   1 ; Sandy Shocks: paradox
	db FARFETCHD,  0 ; plain Farfetch'd: only Galarian Farfetch'd -> Sirfetch'd
	db 0 ; terminator
