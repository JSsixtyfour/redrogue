;replace random mew encounters with ditto if dex diploma not attained
DisallowWildMew:
	ld a, [wCurPartySpecies]	;get the current pokemon in question
	cp MEW	;is it mew? zet zero flag if true
	ret nz	;if not mew, then return
	;else we have a potential mew encounter on our hands
	;CheckEvent EVENT_90B
	jr z, .replace_mew	;if event 90B is zero, then diploma has not been granted. mew is not allowed.
	;CheckEvent EVENT_8C0
	jr z, .mew_allowed	;mew can appear if not already encountered
.replace_mew
	ld a, DITTO	;load the ditto constant
	ld [wCurPartySpecies], a	;overwrite mew with ditto
	ld [wEnemyMonSpecies2], a
	ret
.mew_allowed
;	;the slot that triggered the mew encounter has it's likelihood of a mew cut in half
;	;idea is to give mew a 0.6% encounter rate (lowest in the game)
;	ld a, [hRandomSub]
;	bit 0, a
;	jr nz, .replace_mew
	;going to encounter mew now
	;SetEvent EVENT_8C0 ;mew has been encountered now
	;ReSetEvent EVENT_8C2 ;turn on mew notification
	ret

	
	

;CheckIfPkmnReal:
;;set the carry if pokemon number in 'a' is found on the list of legit pokemon
;	push hl
;	push de
;	push bc
;	ld hl, ListRealPkmn
;	ld de, $0001
;	call IsInArray
;	pop bc
;	pop de
;	pop hl

;This function loads a random trainer class (value of $01 to $2F)
GetRandTrainer:
.reroll
	call Random
	and $30
	cp $30
	jr z, .reroll
	push bc
	ld b, a
	call Random
	and $0F
	add b
	pop bc
	and a
	jr z, .reroll
; wEngagedTrainerClass holds an OPP id, not a raw class: PlayTrainerMusic
; compares it against OPP_RIVAL1 and InitBattleEnemyParameters copies it
; straight into wCurOpponent. So the roll has to be offset-relative.
; This said `add $C8` (200), the OPP_ID_OFFSET from before it was lowered to
; 160 on 2026-09-10, which would have produced ids 201-247 = classes 41-87 and
; indexed TrainerDataPointers well past its last entry ($31). Harmless only
; because nothing calls this today - upstream shinpokered's two callers
; (ssanne6, undergroundpathwe) do not exist in this tree.
;
; The roll covers classes $01-$2F, i.e. YOUNGSTER through LANCE, which includes
; the gym leaders, the rivals, Oak and the Elite Four. Any future caller has to
; filter, or it will hand the player a random Lance.
	add OPP_ID_OFFSET
	ld [wEngagedTrainerClass], a
	ld a, 1
	ld [wEngagedTrainerSet], a
	ret

;gets a random pokemon and puts its hex ID in register a and wcf91
GetRandMon:
	push hl
	push bc
	; Challenge 6 (INCREASED_RARITY_FOES): bump class by 1 tier (lower b = rarer).
	; b=4=pokeball, b=3=greatball, b=2=ultraball, b=1=masterball. Cap at b=1.
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	jr z, .noRarityBump
	ld a, [wWitchChallenge]
	cp CHALLENGE_INCREASED_RARITY_FOES
	jr nz, .noRarityBump
	ld a, b
	cp 2
	jr c, .noRarityBump    ; already masterball (b=1), can't go rarer
	dec b
.noRarityBump
    ; b is INVERTED here relative to every other caller (4=pokeball .. 1=
    ; masterball), so map it onto the shared tier ids: tier = 4 - b.
    push de                       ; the roller uses de; callers expect it preserved
    ld a, RARITY_TIER_MASTERBALL + 1
    sub b
    ld b, a
    call RogueRollGroupForTier    ; a = group; b (tier) preserved
    jr c, .fallback
    call RogueGetTierEntry        ; hl = pair list, b = direct count
    jr z, .fallback
    ld a, b
    call RogueRollSpeciesInList   ; d = species, e = form
    jr .gotSpecies
.fallback
    ; No active group offers this tier - fall back to the Kanto pokeball list.
    ld a, SPECIES_GROUP_KANTO
    ld b, RARITY_TIER_POKEBALL
    call RogueGetTierEntry
    ld a, b
    call RogueRollSpeciesInList
.gotSpecies
    ld a, e
    ld [wSpawnForm], a
    ld a, d
    pop de
    ld [wCurPartySpecies], a
.done
pop bc
pop hl
RET
	
;generates a randomized 6-party enemy trainer roster
; difficulty ramps up every ROUND_BATTLES battles won: within each round,
; wBattleCount mod ROUND_BATTLES = 1..ROUTE_BATTLES-1 are the route trainers,
; FINAL_ROUTE_STEP is the final (strongest) route trainer, FIRST_GYM_STEP..
; FINAL_GYM_TRAINER_STEP are the gym trainers, and step 0 is the gym leader
; (handled separately by InitGymBattle, never reaches GetRandRoster).
; wBattleCount/ROUND_BATTLES (integer) gives the "round" (0-7 for gyms 1-8, 8
; for Victory Road), matching up with the gym leader's tier for that round.
; route trainers use trainer_difficulty_settings, gym trainers use the
; separate, higher-level trainer_difficulty_settings_gym table.
GetRandRoster:
	push bc
	push de
    push hl
    ld a, [wBattleCount]	; load how many battles the player has won
    cp LAST_ROUND_BATTLECOUNT + 1
    jr c, .noClampRound
    ld a, LAST_ROUND_BATTLECOUNT                ; clamp to round 9's settings (Victory Road/Elite Four)
.noClampRound
    ld b, 0                 ; b = round index (0-8)
.getRoundIndex
    cp ROUND_BATTLES
    jr c, .gotRoundIndex
    sub ROUND_BATTLES
    inc b
    jr .getRoundIndex
.gotRoundIndex
    ; a = step within the round (constants/round_constants.asm).
    ; A Money Match fights as route step MONEY_MATCH_STEP of this round,
    ; whatever the count's own step is; the PokeManiac (a subroom resident on
    ; the same path) as the route's last trainer, FINAL_ROUTE_STEP (user,
    ; 2026-10-14: "the 4th trainer of a route"). RogueBattleRound applies the
    ; same override for the moveset row, so the two always agree.
    ld hl, wMoneyMatchState
    bit BIT_MONEY_MATCH_ACTIVE, [hl]
    jr z, .stepReady
    ld a, [wTrainerClass]
    cp POKEMANIAC
    ld a, MONEY_MATCH_STEP
    jr nz, .stepReady
    ld a, FINAL_ROUTE_STEP
.stepReady
    ; route steps, then gym steps -> pick the matching table.
    ld hl, trainer_difficulty_settings
    cp FIRST_GYM_STEP
    jr c, .pickedTable
    ld hl, trainer_difficulty_settings_gym
.pickedTable
    ; the final trainer of each tier (last route trainer, last gym trainer)
    ; gets the level bonus and rarer class distribution, signalled via
    ; wRogueFlagsBitfield bit 1 for GetRandRosterLoop
    cp FINAL_ROUTE_STEP
    jr z, .isFinalTrainer
    cp FINAL_GYM_TRAINER_STEP
    jr nz, .notFinalTrainer
.isFinalTrainer
    ld a, [wRogueFlagsBitfield]
    set 1, a
    jr .gotFlag
.notFinalTrainer
    ld a, [wRogueFlagsBitfield]
    res 1, a ; clears out the flag for bonus level so a regular trainer doesn't receive it
.gotFlag
    ld [wRogueFlagsBitfield], a

    ld a, b                 ; each settings block is 11 bytes
    ld d, a                 ; d = b
    add a, a                ; *2
    add a, a                ; *4
    add a, a                ; *8
    add a, d                ; *9
    add a, d                ; *10
    add a, d                ; *11
    ld c, a                 ; offset is placed in c
    ld b, 0
    add hl, bc              ; offset it added to pointer to get round
	jp GetRandRosterLoop


GetRandRosterLoop:
	ld c, [hl]   ; load level range
    inc hl      ; move to next byte, minimum level
    ld e, [hl]  ; load minimum level
    inc hl      ; move to next byte, normal class counts start
    ld a, [wRogueFlagsBitfield]
    bit 1, a
    jr z, .maybeShrink
; final route trainer: apply the level bonus and use the rarer class distribution
    inc hl
    inc hl
    inc hl
    inc hl      ; hl = level bonus byte
    ld a, [hl]
    add a, e
    ld e, a
    inc hl      ; hl = final-trainer class counts
    jr .overloopSetup

; Varied party sizes (BALANCE_PHASE5_PLAN.md D, 2026-09-28): a normal (not
; final) trainer whose team would be ROSTER_VARY_MIN_SIZE..ROSTER_FULL_SIZE-1
; mons fields one fewer, half the time. The final trainer of each block keeps
; the full size, full-size (6) teams never vary, and a 2-mon team never drops
; to 1. The dropped mon is the first one rolled, i.e. the commonest class.
; Bit 7 of c (the level range, always small) carries "skip one" into .loop,
; which clears it on the first mon; every other register here is live.
.maybeShrink
    push hl
    ld a, [hli]
    add [hl]
    inc hl
    add [hl]
    inc hl
    add [hl]    ; a = team size from the four class counts
    pop hl
    cp ROSTER_VARY_MIN_SIZE
    jr c, .overloopSetup
    cp ROSTER_FULL_SIZE
    jr nc, .overloopSetup
    call Random ; preserves bc/de/hl
    rrca
    jr nc, .overloopSetup
    set 7, c
.overloopSetup

;.highest_level_set:
	;push bc
	;ld a, d     ; places highest level in a
;    sub a, e    ; subtract minimum level from a
;	ld c, a     ; place difference in c
;.calibrate1	    ; subtract result from the highest party level or make it zero if it underflows
;	ld a, d     ; places highest level in a
;	sub a, c    ; subtract to get lowest level
;    dec c       ; lower c if the result is below 2
;	jr c, .calibrate1 
;	ld e, a	    ; places calibrated level in e
	;pop bc
    ;push bc
	;push de
    ld b, 0x4   ; overarching loop

	.overloop
    ld  a, [hl] ; load number of pokemon/loops
    cp  a, 0
    jp  z, .miniloop    ; overarching class loop
    ld  d, a
    
    .loop
    bit 7, c
    jr z, .keepMon
    res 7, c    ; varied party size: skip this one mon (see .maybeShrink)
    jp .nextMon
.keepMon
    ; No-duplicates retry budget, kept on the stack because every register in
    ; this loop is live. Popped after AddPartyMon below.
    ld a, PARTY_GEN_MAX_RETRIES
.rerollMon
    push af
    ; Gambler's Paradise: draw species from the Gambler pool (PARTY_ROSTER.md
    ; "## Gamblers", party roster Phase 6) instead of the rarity-class roll.
    ; Level logic below is unchanged, and so is the evolution: the forced moves
    ; come later, from MIX_GAMBLER, keyed on the species actually fielded.
    ld a, [wTrainerClass]
    cp GAMBLER
    jr nz, .useRandMon
    ld a, [wMoneyMatchState]        ; a Money Match Gambler rolls like a
    bit BIT_MONEY_MATCH_ACTIVE, a   ; route trainer (Phase M)
    jr nz, .useRandMon
    push hl
    push bc
    push de
    ld e, POOL_BAND_Gambler_Fod1
    farcall RogueDrawFromPoolFar ; wCurPartySpecies; clobbers everything
    xor a
    ld [wSpawnForm], a            ; this species-only pool explicitly selects form 0
    pop de
    pop bc
    pop hl
    jr .gotMon
.useRandMon
    call GetRandMon
.gotMon
	ld a, ENEMY_PARTY_DATA
	ld [wMonDataLocation], a
    call Rangerandom
	add a, e   ; minimum level added to random number
	ld [wCurEnemyLevel], a  ; place level of pokemon in
	call RogueApplyTrainerLevelModifiers
	; Resolve the selected species against its final trainer level before it is
	; copied into the enemy party. GetRandMon returns the species through
	; wCurPartySpecies, while EvolveMonByLevel expects it in d. Preserve every
	; live roster-loop register: b/d are loop counters, e is the minimum level,
	; and hl points into the difficulty settings.
	push hl
	push bc
	push de
	ld a, [wSpawnForm]
	cp NUM_FORM_SLOTS + 1
	jr c, .literalRosterForm
	xor a
.literalRosterForm
	ld e, a
	ld a, [wCurPartySpecies]
	ld d, a
	farcall EvolvePoolMon
	ld a, e
	ld [wSpawnForm], a
	pop de
	pop bc
	pop hl
; No duplicates on a rolled roster. Tested HERE, after the evolve, because
; wEnemyPartySpecies holds fielded species: a Kabuto drawn next to a built
; Kabutops would pass a pre-evolve test and then become a second Kabutops (the
; NO_DUPES bug class, rogue_build_party.asm). Eevee needs no special case, the
; evolve above was the real one. Bounded, then accepted, so a small pool cannot
; hang. Gamblers keep their themed pool as drawn.
	ld a, [wTrainerClass]
	cp GAMBLER
	jr nz, .checkUnique
	ld a, [wMoneyMatchState]        ; a Money Match Gambler is a route
	bit BIT_MONEY_MATCH_ACTIVE, a   ; trainer: no duplicates either
	jr z, .rosterUnique
.checkUnique
	call RosterSpeciesAlreadyUsed
	jr nc, .rosterUnique
	pop af                  ; retry budget
	dec a
	jr nz, .rerollMon
	push af                 ; out of retries: accept the duplicate
.rosterUnique
; wSpawnForm already holds this explicit pool entry's evolved form.
IF FORCE_TRAINER_FORM_TEST
; ⚠ TEMPORARY - see FORCE_TRAINER_FORM_TEST in pokemon_data_constants.asm.
; Forces the whole enemy roster to Alolan Grimer so the stored-form send-out path
; can be observed without waiting on two random rolls to line up.
	ld a, GRIMER
	ld [wCurPartySpecies], a
	ld a, 1                 ; agrimer.asm is form_record GRIMER, 1
	ld [wSpawnForm], a
ENDC
	call AddPartyMon    ; add the pokemon
	pop af                  ; retry budget
.nextMon
	dec d           ; decrease loop/run through pokemon
    jp nz, .loop    ; pokeball class loop (jp: the Money Match checks pushed it out of jr range)

.miniloop
    inc hl          ; next class
    dec b           ; decrease overarching loop
    jp nz, .overloop    ; overarching class loop

;end of loop
	pop de
	pop bc
    pop hl
	xor a	;set the zero flag before returning
	ret

; ============================================================
; RosterSpeciesAlreadyUsed
; Carry set if wCurPartySpecies is already in wEnemyPartySpecies ($FF
; terminated; ReadTrainer starts it empty). Preserves bc/de/hl.
; ============================================================
RosterSpeciesAlreadyUsed:
	push hl
	push bc
	ld a, [wCurPartySpecies]
	ld b, a
	ld hl, wEnemyPartySpecies
.loop
	ld a, [hli]
	cp $FF
	jr z, .done             ; carry clear: a == $FF
	cp b
	jr nz, .loop
	scf
.done
	pop bc
	pop hl
	ret

INCLUDE "data/balance/trainer_levels.asm"

; Applies all active trainer-level modifiers after a base level is written.
; No register arguments. Clobbers a and the Divide/Multiply HRAM scratch;
; preserves bc, de, and hl for callers that are walking trainer data.
RogueApplyTrainerLevelModifiers::
	call RogueApplyWitchLevelBonus
	call RogueApplyDifficulty
	ret

; Challenge 5 (INCREASED_LEVELS): add ~10% of level, minimum +1.
; This retains the existing multiplier and overflow behavior, but preserves
; the roster-loop registers so the helper is safe for every trainer path.
RogueApplyWitchLevelBonus::
	ld a, [wRogueFlagsBitfield]
	bit BIT_WITCH_ACCEPTED, a
	ret z
	ld a, [wWitchChallenge]
	cp CHALLENGE_INCREASED_LEVELS
	ret nz
	push bc
	push de
	push hl
	ld a, [wCurEnemyLevel]
	ld b, a
	ldh [hMultiplicand+2], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand+1], a
	ld a, 26
	ldh [hMultiplier], a
	call Multiply              ; level * 26; hProduct+2 = high byte ≈ level/10
	ldh a, [hProduct+2]
	and a
	jr nz, .hasLvlBonus
	ld a, 1                    ; minimum +1
.hasLvlBonus
	add b
	jr nc, .lvlBonusOk
	ld a, 255
.lvlBonusOk
	ld [wCurEnemyLevel], a
	pop hl
	pop de
	pop bc
	ret

; Adjusts wCurEnemyLevel by the player's LEVELS setting (wOptions2 bits 0-2):
; level +/- level*|pct|//100 with pct = DifficultyLevelPct[setting] (signed).
; No register arguments.  Clobbers a and the Multiply/Divide HRAM scratch.
RogueApplyDifficulty::
	ld a, [wOptions2]
	and DIFFICULTY_MASK
	cp NUM_AI_DIFFICULTY_ROWS
	ret nc                       ; corrupt option byte: leave the level untouched
	push bc
	push de
	push hl
	ld c, a
	ld b, 0
	ld hl, DifficultyLevelPct
	add hl, bc
	ld a, [hl]                   ; a = signed percent
	and a
	jr z, .done                  ; 0%: the balance baseline (HARD)
	ld e, a                      ; e bit 7 = lower
	bit 7, a
	jr z, .gotMagnitude
	cpl
	inc a                        ; |pct|
.gotMagnitude
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, [wCurEnemyLevel]
	ld d, a                      ; d = base level
	ldh [hMultiplicand + 2], a
	call Multiply                ; level * |pct| <= 255 * 128, fits hProduct+2/+3
	ldh a, [hProduct + 2]
	ldh [hDividend], a
	ldh a, [hProduct + 3]
	ldh [hDividend + 1], a
	ld a, 100
	ldh [hDivisor], a
	ld b, 2                      ; 2-byte dividend
	call Divide
	ldh a, [hQuotient + 3]
	ld c, a                      ; c = delta

	bit 7, e
	jr z, .harder
; lower, floor at 1
	ld a, d
	sub c
	jr c, .floor
	and a
	jr nz, .store
.floor
	ld a, 1
	jr .store
.harder
	ld a, d
	add c
	jr c, .ceiling
	cp 101
	jr c, .store
.ceiling
	ld a, 100
.store
	ld [wCurEnemyLevel], a
.done
	pop hl
	pop de
	pop bc
	ret

; RogueApplyDifficulty for a level that is not in wCurEnemyLevel, for callers in
; another bank. INPUT/OUTPUT: e = level (e survives a farcall both ways; a does
; not). wCurEnemyLevel is saved and restored around the call.
RogueApplyDifficultyE::
	ld a, [wCurEnemyLevel]
	push af
	ld a, e
	ld [wCurEnemyLevel], a
	call RogueApplyDifficulty
	ld a, [wCurEnemyLevel]
	ld e, a
	pop af
	ld [wCurEnemyLevel], a
	ret

; Signed level percent per stored DIFFICULTY_* value (balance_constants.asm).
DifficultyLevelPct:
	db LOW(DIFF_LEVEL_PCT_NORMAL)
	db LOW(DIFF_LEVEL_PCT_EASY)
	db LOW(DIFF_LEVEL_PCT_VERY_EASY)
	db LOW(DIFF_LEVEL_PCT_HARD)
	db LOW(DIFF_LEVEL_PCT_VERY_HARD)
	assert @ - DifficultyLevelPct == NUM_AI_DIFFICULTY_ROWS, \
		"DifficultyLevelPct must have one entry per difficulty"

; ============================================================================
; Mid-battle evolution (Extreme Yellow import).
; A mon that levels up mid-battle evolves at once if the trainer still has
; Pokemon left, instead of waiting for EndOfBattle.
; ============================================================================

RogueTryMidBattleEvolution::
	ldh a, [hIsInBattle]
	cp 2
	ret nz                      ; only trainer battles have an enemy party
	farcall AnyEnemyPokemonAliveCheck
	ret z                       ; last opponent: let EndOfBattle evolve normally

; Only the ACTIVE mon evolves mid-battle.  wCanEvolveFlags has one bit per party
; slot (set by GainExperience on level-up, bench mons included via Exp. All);
; the bench bits are held back and restored so EndOfBattle evolves those mons.
	ld a, [wPlayerMonNumber]
	inc a
	ld b, a
	xor a
	scf
.maskLoop
	rla
	dec b
	jr nz, .maskLoop            ; a = the active mon's flag bit
	ld b, a
	ld a, [wCanEvolveFlags]
	ld c, a
	and b
	ret z                       ; active mon didn't level: leave flags for EndOfBattle
	ld a, b
	cpl
	and c
	push af                     ; bench flags, active bit cleared (tried once only)
	ld a, b
	ld [wCanEvolveFlags], a
	predef EvolutionAfterBattle
	pop af
	ld [wCanEvolveFlags], a

; wEvolutionOccurred is set before the evolution screen, so it is also set when
; the player cancels with B.  Either way the screen was cleared and the music /
; audio bank were switched, so the battle view must be rebuilt.
	ld a, [wEvolutionOccurred]
	and a
	ret z
	jp RogueRefreshBattleMonAfterEvolution

; LoadBattleMonFromParty (engine/battle/core.asm) WITHOUT its trailing stat-mod
; reset, so boosts, drops, Substitute and status all survive the evolution.
RogueRefreshBattleMonAfterEvolution:
	ld a, [wPlayerMonNumber]
	ld bc, PARTYMON_STRUCT_LENGTH
	ld hl, wPartyMon1Species
	call AddNTimes
	ld de, wBattleMonSpecies
	ld bc, wBattleMonDVs - wBattleMonSpecies
	call CopyData
	ld bc, MON_DVS - MON_OTID
	add hl, bc
	ld de, wBattleMonDVs
	ld bc, MON_PP - MON_DVS
	call CopyData
	ld de, wBattleMonPP
	ld bc, NUM_MOVES
	call CopyData
	ld de, wBattleMonLevel
	ld bc, wBattleMonPP - wBattleMonLevel
	call CopyData

	ld a, [wBattleMonSpecies]
	ld [wBattleMonSpecies2], a
	ld [wCurSpecies], a
	call GetMonHeader
	ld hl, wPartyMonNicks
	ld a, [wPlayerMonNumber]
	call SkipFixedLengthTextEntries
	ld de, wBattleMonNick
	ld bc, NAME_LENGTH
	call CopyData
	ld hl, wBattleMonLevel
	ld de, wPlayerMonUnmodifiedLevel
	ld bc, 1 + NUM_STATS * 2
	call CopyData
	xor a
	ld [wCalculateWhoseStats], a
	farcall CalculateModifiedStats
	farcall ApplyBurnAndParalysisPenaltiesToPlayer
	farcall ApplyEarnedStatBoosts

; AnimateSendingOutMon draws the small "in battle" sprite while hIsInBattle is
; set.  Clear it across that one predef only, to get the full-size back pic.
	predef LoadMonBackPic
	xor a
	ldh [hStartTileID], a
	hlcoord 4, 11
	ldh a, [hIsInBattle]
	push af
	xor a
	ldh [hIsInBattle], a
	predef AnimateSendingOutMon
	pop af
	ldh [hIsInBattle], a

; EvolveMon started MUSIC_SAFARI_ZONE then hit SFX_STOP_ALL_MUSIC, and
; EvolutionAfterBattle deliberately skips PlayDefaultMusic while in battle
; (engine/pokemon/evos_moves.asm:281-287), so nothing is playing here.  It also
; skips the tileset reload (:242-244), so the HUD tile patterns need restoring.
	farcall PlayBattleMusic
	farcall LoadHudTilePatterns
	farcall DrawPlayerHUDAndHPBar
	call SaveScreenTilesToBuffer1
	ret

; Rangerandom moved to home/random.asm (HOME bank) so every bank can reach it
; with a plain `call` - it used to live here (bank 07 / "rogue" section) and
; every cross-bank caller was using a plain `call` instead of `farcall`,
; silently executing whatever happened to be at that address in the caller's
; own bank instead of this function.

;GetWeightedLevel:
;	ld a, [wPartyCount]
;	dec a
;	jp z, GetHighestLevel
;
;	push hl
;	push bc
;	push de
;	
;	ld hl, wBoxDataEnd+5	;need 6 bytes of working space
;	
;	ld de, wPartyMenuHPBarColors
;	ld a, [wPartyCount]
;	ld c, a
;.loop
;	ld a, [de]
;	ld [hld], a
;	inc de
;	dec c
;	jr nz, .loop
;
;	ld a, [wPartyCount]
;	ld c, a
;.loop2
;	inc hl
;	dec c
;	jr nz, .loop2
;	
;	ld d, h
;	ld e, l
;	
;.sortingpass
;	ld h, d
;	ld l, e
;	ld a, [wPartyCount]	;if in this sorting pass loop, then this number is 2 to 6
;	dec a
;	ld c, a
;.loop3A
;	ld a, [hld]
;	cp [hl]
;	jr c, .swapping
;	dec c
;	jr z, .weight	;if an entire pass was made with no swapping, then the bytes are sorted
;	jr .loop3A
;.swapping
;	;current [HL] is greater than [HL+1] which is in A
;	;need to swap them
;	ld b, a
;	ld a, [hli]
;	ld [hld], a
;	ld a, b
;	ld [hl], a
;	;did the swap
;	;if this is the end of the pass, do another pass
;	dec c
;	jr z, .sortingpass
;	;else keep looping through this pass
;.loop3B
;	ld a, [hld]
;	cp [hl]
;	jr c, .swapping
;	dec c
;	jr z, .sortingpass	;if the pass is complete, then then do another pass because a swap was done
;	jr .loop3B
;	
;.weight
;	ld h, d
;	ld l, e
;	ld a, [wPartyCount]
;	ld c, a
;	dec c	
;	ld d, 1
;	ld e, 1
;.loop4
;	dec hl
;	ld a, [hl]
;.loop4sub1
;	srl a
;	dec e
;	jr nz, .loop4sub1
;	ld [hl], a
;	inc d
;	ld e, d
;	dec c
;	jr nz, .loop4
;
;.summation
;	ld de, $0000
;	ld a, [wPartyCount]
;	ld c, a
;.loop5
;	ld a, [hli]
;	add e
;	ld e, a
;	ld a, d
;	adc d
;	ld d, a
;	dec c
;	jr nz, .loop5	
;
;.multiplication	;do x32
;	ld c, 5
;.loop6
;	sla e
;	rl d
;	dec c
;	jr nz, .loop6
;
;.prepareDividend
;	ld a, d
;	ld [hDividend+0], a
;	ld a, e
;	ld [hDividend+1], a
;	xor a
;	ld [hDividend+2], a
;	ld [hDividend+3], a
;
;.getdivisor
;	ld a, [wPartyCount]
;	ld c, a
;	dec c
;	ld a, 32
;	ld b, 32
;.loop7
;	srl b
;	add b
;	dec c
;	jr nz, .loop7
;	ld [hDivisor], a
;
;	ld b, 2
;	call Divide
;	ld a, [hQuotient+3]
;	
;	pop de
;	pop bc
;	pop hl
;	ret
;	
;
;	
;GetHighestLevel:	;gets the highest party level into A
;; UPDATE, should look to current battle count
;	push hl
;	push bc
;	ld hl, wPartyMenuHPBarColors
;	ld a, [wPartyCount]	;1 to 6
;	ld b, a	;use b for countdown
;.loadHigher
;	ld a, [hl]
;.keepCurrent
;	dec b
;	jr z, .highestLVLfound
;	inc hl
;	cp a, [hl]
;	jr c, .loadHigher
;	jr .keepCurrent
;.highestLVLfound
;	pop bc
;	pop hl
;	ret
	
	
;implement a function to scale trainer levels
ScaleTrainer:
	call ScaleTrainer_level
	call ScaleTrainer_evolution
	ret
	
ScaleTrainer_level:
	;CheckEvent EVENT_90C
	ret z
	push bc

	ld a, [wGymLeaderNo]
	and a
	;jr nz, .hard	;if fighting a boss like a gym leader, use the harder level scaling
	;ld a, [wOptions]
	;bit BIT_BATTLE_HARD, a
	;jr z, .normal	;if it's a regular trainer but playing on hard mode, use the harder level scaling
;.hard
	;call GetHighestLevel
	;jr .got_level
.normal
	;call GetWeightedLevel
.got_level
	push af
	ld a, [wCurEnemyLevel]
	ld b, a
	pop af
	
	;at this line, B holds current enemy level and A holds highest/weighted party level
	cp b
	pop bc
	ret c
	ret z
	
	push bc
	ld [wCurEnemyLevel], a
	call Random
	and $03
	ld b, a
	ld a, [wGymLeaderNo]
	and a
	jr z, .notboss
	ld a, [wCurEnemyLevel]
	add b
	call PreventARegOverflow
	ld [wCurEnemyLevel], a
	call Random
	and $03
	ld b, a
.notboss
	ld a, [wCurEnemyLevel]
	add b
	call PreventARegOverflow
	ld [wCurEnemyLevel], a
	pop bc
	ret

ScaleTrainer_evolution:
	; Trainer species evolve at the same displayed levels as player species.
	farcall EvolveMonByLevel
	ret


	

;this will prevent an overflow of the A register
;typically for custom functions that increase enemy levels
;defaulted to 255 on an overflow
;call after a value was just added to register A
PreventARegOverflow:
	ret nc	;return if there was no overflow
	;else set A to the max
	ld a, $FF
	ret



; d = Current Gym Leader/Battle, ie. OPP_BROCK
InitGymBattle::
    ld a, d
	ld [wCurOpponent], a
	ld a, [wBattleCount]
    ldh [hDividend], a          ; place battle count in dividend
    ld   a, ROUND_BATTLES
    ldh [hDivisor], a           ; leader is fought at count = round * ROUND_BATTLES
    ld b, $1                    ; b determines how many bytes the number is, do not remove!
    call Divide
    ldh   a, [hQuotient+3]      ; load in quotient
    sub a, 1                    ; subtract for multiplication to get base trainer number
    ldh [hMultiplicand+2], a    ; place number in for multiplication
    ld a, 3                     ; multiply by 3, which is the amount of teams per each ranking
    ldh [hMultiplier], a        ; place amount of class in multiplier
    call Multiply               ; multiply number by 3, to get our base number
    ldh   a, [hProduct+3]       ; load product into a
    add a, 1                    ; add one (not zero based), to get trainer number base
    push af
    ld c, 3                     ; amount of options per rankings
    call Rangerandom
    ld b, a                     ; load random number into b
    pop af
    add a, b                    ; add random number to base trainer to get party
    ld [wTrainerNo], a          ; set trainer no within gym leaders options
    ld a, 1
	ld [wIsTrainerBattle], a    ; start battle
	; Keep gym-next through the battle's map reload. The leader's post-battle
	; badge script clears it only after the win is finalized; clearing it here
	; makes gym B look like a completed gym A at a pair badge count.
	ret

; d = Current Elite Four member, ie. OPP_LORELEI
; Tier is derived LINEARLY from wBattleCount (86/87/88/89 -> tier 0-3), unlike
; InitGymBattle's round-based math - the Elite Four is fought at a fixed battle
; count range, not on the /10 grid gym leaders use. Does NOT touch wGymLeaderNo
; (leave it 0 - a nonzero value triggers gym-leader victory music and the
; Challenge 11 legendary-ace substitution) and does NOT touch wRogueFlagsBitfield
; bit 0 (route/gym alternation - irrelevant here, the final sequence has fixed
; room routing instead).
InitElite4Battle::
	ld a, d
	ld [wCurOpponent], a
	ld a, [wBattleCount]
	sub a, E4_FIRST_BATTLECOUNT ; tier 0 at the first E4 battle
	cp a, NUM_E4_BATTLES
	jr c, .tierOk
	ld a, NUM_E4_BATTLES - 1    ; clamp to the last tier if called out of range
.tierOk
	ld b, a
	ld a, 3                     ; 3 teams per tier
	ldh [hMultiplicand+2], a
	ld a, b
	ldh [hMultiplier], a
	call Multiply                ; base = tier * 3
	ldh a, [hProduct+3]
	add a, 1                     ; +1 (party data is 1-based)
	push af
	ld c, 3                      ; amount of variants per tier
	call Rangerandom
	ld b, a                      ; random variant into b
	pop af
	add a, b                     ; base + random variant
	ld [wTrainerNo], a
	ld a, 1
	ld [wIsTrainerBattle], a     ; start battle
	ret


; If the species about to be loaded is the rival starter placeholder,
; replace it with the rival's actual rogue starter (wRivalStarter), evolved
; to match wCurEnemyLevel. Works for any trainer/location.
; Input: wCurPartySpecies = species byte just read from trainer data
PatchRivalStarterSpecies::
	push hl
	push bc
	push de
	ld a, [wCurPartySpecies]
	cp RIVAL_STARTER_PLACEHOLDER
	jr nz, .done
	xor a
	ld [wSpawnForm], a
	ld a, [wRivalStarter]
	ld [wCurPartySpecies], a
	ld d, a
	call ScaleTrainer_evolution
; Eevee's shared evolution path chooses a species AND a form. Authored
; parties do not roll forms, so publish that choice here for both loaders.
	ld a, [wPendingEeveeForm]
	bit 7, a
	jr z, .done
	and %11
	ld [wSpawnForm], a
	xor a
	ld [wPendingEeveeForm], a
.done
	pop de
	pop bc
	pop hl
	ret
