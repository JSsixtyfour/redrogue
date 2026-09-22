; Boss battle uses the cave's real TalkToTrainer/def_trainers path (see
; PROCEDURAL_STAGE_FUNDAMENTALS.md) - the boss is sprite slot 1, engaged
; normally by pressing A on it, or forced via the flank-tile guard in
; ProceduralForestDefaultScript below (see that function's comment).
;
; Reused events (never concurrent with cave/cemetery, all reset at Pallet Town
; entry by PFPreloadForest/PFRollBoss):
;   EVENT_BEAT_PC_BOSS  - boss defeated / offered (bit-aligned for slot-1 trainer)
;   EVENT_PC_BUDGET_ENDED / EVENT_PC_CALMED_SHOWN - wild budget calmed message

ProceduralForest_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
; Fresh entry: show the four item pokeballs.
	ld a, TOGGLE_WILD_AREA_POKEBALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_WILD_AREA_POKEBALL_4
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Show the boss only if it hasn't been beaten yet.
	CheckEvent EVENT_BEAT_PC_BOSS
	jr nz, .afterSetup
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Phase 7 rollout: reveal the stage-event NPC slots, but only for the
	; slots this event actually uses. Same idiom as the cave's own script -
	; the staged sprite doubles as the "slot in use" flag.
	farcall StageEventShowCaveNpcs
.afterSetup
	; --- Phase 7 rollout: stage-event arrival -----------------------------
	; Byte-for-byte the same shape as the cave's own .afterSetup block - see
	; that file for the full reasoning (arrival fires on load rather than the
	; player's first step, the phase field IS the one-shot, good NPCs skip
	; the vanish).
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .afterStageEvent
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	jr z, .afterStageEvent          ; no event armed on this wild area
	ld a, [wStageEvent]
	and STAGE_EVENT_PHASE_MASK
	jr nz, .afterStageEvent         ; already spoken
	; THE TYPE GATE MOVED UP HERE 2026-09-17, from four instructions below the
	; DisplayTextID. Joy and Jenny are meant to be FOUND - "they should just
	; exist in their spots as something the player can find without any prior
	; warning" - but gating AFTER the greeting meant a good NPC still walked up
	; and delivered the villain's arrival box the instant the map faded in.
	; Testing here skips the theft AND the greeting and drops the phase straight
	; to SETTLED, past HIDING, so the recovery block below (which only opens on
	; HIDING) stays shut for them too. The placement routine carries the
	; matching test, so they start at the hideout instead of at the entrance.
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	cp STAGE_EVENT_JOY
	jr nc, .goodNpcSettle           ; JOY/JENNY - no theft, no greeting, no vanish
	; REORDERED 2026-09-17: the theft now runs BEFORE the greeting, so the
	; greeting can NAME what was taken - StageEventPrintLootLine, called
	; from the arrival text handler, reads the record this call writes.
	; On screen the beat still reads threat -> loss -> escape, because the
	; loot line prints as the second half of the same box sequence.
	farcall StageEventDoTheft
	ld a, TEXT_PROCEDURALFOREST_STAGE_EVENT
	ldh [hTextID], a
	call DisplayTextID
	farcall PFStageEventVanish      ; fade out, relocate, fade in; -> HIDING
	jr .afterStageEvent
.goodNpcSettle
	ld a, [wStageEvent]
	and ~STAGE_EVENT_PHASE_MASK & $ff
	or STAGE_EVENT_PHASE_SETTLED << STAGE_EVENT_PHASE_SHIFT
	ld [wStageEvent], a
.afterStageEvent
	; Wild budget calmed check — runs every frame, independent of boss state.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .afterCalm
	CheckEvent EVENT_PC_CALMED_SHOWN
	jr nz, .afterCalm
	CheckEvent EVENT_PC_BUDGET_ENDED
	jr z, .afterCalm
	SetEvent EVENT_PC_CALMED_SHOWN
	ld a, TEXT_PROCEDURALFOREST_CALMED
	ldh [hTextID], a
	call DisplayTextID
.afterCalm
	; --- Phase 7 rollout: recovery, once the villain is beaten -------------
	; Byte-for-byte the same shape as the cave's own recovery block.
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	jr z, .afterRecovery            ; no event armed
	ld a, [wStageEvent]
	and STAGE_EVENT_PHASE_MASK
	cp STAGE_EVENT_PHASE_HIDING << STAGE_EVENT_PHASE_SHIFT
	jr nz, .afterRecovery           ; not robbed-and-hiding, so nothing owed
	CheckEvent EVENT_BEAT_STAGE_EVENT_NPC_1
	jr nz, .recover
	CheckEvent EVENT_BEAT_STAGE_EVENT_NPC_2
	jr z, .afterRecovery
.recover
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .afterRecovery
	farcall Delay3
	; GiveBack stores its own result into wStageEventScratch. It cannot hand
	; it back in `a`: farcall returns through Bankswitch, which ends with
	; `ld a, b` = this script's ROM bank.
	farcall StageEventGiveBack      ; -> wStageEventScratch, -> SETTLED or OWED
	; Both NPCs used to be hidden here. 1C leaves them standing so a
	; hand-over that found no room can be retried by talking to them, so the
	; partner is marked beaten instead of removed - see the cave's copy of
	; this block for the full reasoning.
	SetEvent EVENT_BEAT_STAGE_EVENT_NPC_1
	SetEvent EVENT_BEAT_STAGE_EVENT_NPC_2
	ld a, TEXT_PROCEDURALFOREST_STAGE_RECOVER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.afterRecovery
	; One-time join offer, shown after the boss is beaten and the end-battle
	; text has fully cleared (same shape PowerPlant uses for its reward).
	CheckEvent EVENT_PC_BOSS_OFFERED
	jr nz, .runScripts
	CheckEvent EVENT_BEAT_PC_BOSS
	jr z, .runScripts
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	jr nz, .runScripts
	SetEvent EVENT_PC_BOSS_OFFERED
	; Wild-area boss credits. This is where the award has to live, NOT in
	; TrainerBattleVictory: the boss is declared OW_POKEMON, so it fights as a
	; WILD battle (hIsInBattle = 1) and both callers of that routine return
	; before reaching its credits block. The .wildAreaBossCredits branch that
	; used to sit there tested these same three maps and was unreachable from
	; the day it was written - wild-area bosses had never actually paid out.
	;
	; Here instead, because this one-shot is already exactly the right event:
	; guarded by EVENT_PC_BOSS_OFFERED so it fires once, gated on
	; EVENT_BEAT_PC_BOSS so it fires only on a real defeat, and it costs
	; Battle Core (bank $0F) nothing at all.
	;
	; RogueAwardCredits1 draws nothing - it adds to wPlayerCoins and
	; wCreditsEarnedThisRun and returns - so it is safe to run immediately
	; before the join-offer text box.
	farcall RogueAwardCredits1
	farcall Delay3
	ld a, TEXT_PROCEDURALFOREST_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralForestTrainerHeaders
	; PICK THE HEADER BLOCK THAT MATCHES THE ENGAGED TRAINER. Measured bug,
	; 2026-09-17 ("it battles you, the battle ends, it sees you and battles
	; you again"). ExecuteCurMapScriptInTable stores whatever hl it is given
	; into wTrainerHeaderPtr on EVERY tick, and EndTrainerBattle later takes
	; the flag BIT from wTrainerHeaderFlagBit - cached by TalkToTrainer from
	; the ENGAGED trainer's own header - but re-reads the flag BYTE POINTER
	; from wTrainerHeaderPtr, i.e. from the table base.
	;
	; Vanilla never trips on this because `dw wEventFlags + (event -
	; CURRENT_TRAINER_BIT) / 8` is CONSTANT across one consecutive
	; def_trainers block: every trainer in a block shares a byte, so the base
	; header's byte is right for all of them. This map has TWO blocks with
	; DIFFERENT bytes, so the NPC's bit was being written into the boss's
	; byte - the NPC's own event never got set, it never read as beaten, and
	; it re-engaged forever.
	;
	; Gating on wTrainerHeaderFlagBit rather than on hActiveSpriteIndex is
	; deliberate: it is the exact value EndTrainerBattle will pair with this
	; pointer, so the bit and the byte cannot disagree. It is 0 whenever no
	; trainer is engaged (CheckFightingMapTrainers zeroes it), which selects
	; the full table for the ordinary sight-range scan.
	ld a, [wTrainerHeaderFlagBit]
	cp 6
	jr c, .haveTrainerHeaders
	ld hl, PFStageNpc1Header
.haveTrainerHeaders
	ld de, ProceduralForest_ScriptPointers
	ld a, [wProceduralForestCurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralForestCurScript], a
	ret

ProceduralForestTrainerHeaders:
	def_trainers 1  ; boss is slot 1; CheckForEngagingTrainers uses CURRENT_TRAINER_BIT
	                ; as the sprite slot, so this must match the boss's object_event position.
	                ; EVENT_BEAT_PC_BOSS % 8 == 1 == 1 % 8 to satisfy trainer ASSERT.
PFBossTrainerHeader:
	trainer EVENT_BEAT_PC_BOSS, 0, ProceduralForestBossBattleText, ProceduralForestBossBattleText, ProceduralForestBossBattleText
	; Slots 2-5 are pokeballs, so resume the trainer-bit sequence at object
	; slot 6, where the Phase 7 stage-event NPCs live - same shape as the
	; cave's own header.
	def_trainers 6
PFStageNpc1Header:
	trainer EVENT_BEAT_STAGE_EVENT_NPC_1, 4, PFStageEventHideoutText, PFStageEventDefeatText, PFStageEventAfterText
PFStageNpc2Header:
	trainer EVENT_BEAT_STAGE_EVENT_NPC_2, 4, PFStageEventHideoutText, PFStageEventDefeatText, PFStageEventAfterText
	db -1 ; end

ProceduralForest_ScriptPointers:
	def_script_pointers
	dw_const ProceduralForestDefaultScript,     SCRIPT_PROCEDURALFOREST_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle,  SCRIPT_PROCEDURALFOREST_START_BATTLE
	dw_const EndTrainerBattle,                       SCRIPT_PROCEDURALFOREST_END_BATTLE
	;dw_const ProceduralForestPlayerMovingScript,     SCRIPT_PROCEDURALFOREST_PLAYER_MOVING
	;dw_const ProceduralForestBossBattleScript,       SCRIPT_PROCEDURALFOREST_BOSS_BATTLE

; Default state: normal sight-range trainer check, PLUS a flank-tile guard.
; The boss is STAY (never turns to look around), so CheckForEngagingTrainers/
; TrainerEngage's sight-range scan only ever looks in its one facing
; direction - it can never catch a player slipping past on the OTHER tile of
; the 2-tile-wide (north exit) or 2-tile-tall (west/east exit) gap, since the
; boss only ever guards the exit's own first warp tile (see PFinalizeForest's
; edge-aware boss-placement math in procedural_forest_gen.asm). Rather than
; inventing a parallel wCurOpponent-driven battle (cemetery's mechanism - see
; PROCEDURAL_STAGE_FUNDAMENTALS.md's warning against mixing the two for a
; stage with a real boss sprite), force the EXACT SAME TalkToTrainer sequence
; that pressing A on the boss would run.
ProceduralForestDefaultScript:
	CheckEvent EVENT_BEAT_PC_BOSS
	jp nz, CheckFightingMapTrainers
	; Sprite StateData2 MapX/MapY are in SPRITE coordinate space = player
	; space (wXCoord/wYCoord) + 4 (the centered-player offset: a sprite on the
	; player's own tile reads MapY = wYCoord+4). Convert to player space with
	; -4 before comparing, or the trigger fires 4 tiles off in both axes
	; ("miles off but still functions" bug).
	;
	; The unguarded flank tile depends on the exit edge: north exit -> boss
	; guards the LEFT tile of the 2-wide gap, flank is one tile RIGHT of the
	; boss; west/east exit -> boss guards the TOP tile of the 2-tall gap,
	; flank is one tile BELOW the boss (PFinalizeForest's boss-placement math
	; always puts the boss's own plain-space coordinate exactly on the exit's
	; first warp tile, on whichever axis runs along the edge). sProcForestExitEdge
	; is SRAM - must open it explicitly, scripts don't run with SRAM enabled
	; by default (same dance the old, superseded proximity design below used).
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcForestExitEdge]
	ld c, a                          ; c = edge, survives the close below
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a

	ld a, c
	and a
	jr z, .flankNorth

.flankNotNorth
	; West/East: same column as boss, one row below.
	ld a, [wSprite01StateData2MapX]
	sub 4
	ld b, a
	ld a, [wXCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	ld a, [wSprite01StateData2MapY]
	sub 4
	inc a                            ; one tile below the boss
	ld b, a
	ld a, [wYCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	jr .flankHit

.flankNorth
	ld a, [wSprite01StateData2MapY]
	sub 4
	ld b, a
	ld a, [wYCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	ld a, [wSprite01StateData2MapX]
	sub 4                            ; sprite space -> player space
	inc a                            ; one tile right of the boss
	ld b, a
	ld a, [wXCoord]
	cp b
	jp nz, CheckFightingMapTrainers

.flankHit
	; Trigger the EXACT interaction pressing A on the boss runs: dispatch its
	; object text. TEXT_PROCEDURALFOREST_BOSS == 1 == the boss's sprite slot, so
	; DisplayTextID sets hActiveSpriteIndex = 1 and the whole
	; ProceduralForestBossText -> TalkToTrainer chain runs THROUGH the text
	; engine, which is what actually starts the battle. (Calling TalkToTrainer
	; directly from here does not - it just sets the end-battle flags without
	; ever entering battle, so the offer code fires on the next frame instead.)
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_PROCEDURALFOREST_BOSS
	ldh [hTextID], a
	call DisplayTextID
	ret

; Old cemetery-4-style proximity design, superseded by ProceduralForestDefaultScript
; above (kept only as historical reference - do not reintroduce wCurOpponent here).
;ProceduralForestDefaultScriptOLD:
;	CheckEvent EVENT_BEAT_PC_BOSS
;	jp nz, CheckFightingMapTrainers
;	; Read the per-run exit column from SRAM → boss tile X = 4*exitI+2 / +3.
;	ld a, RAMG_SRAM_ENABLE
;	ld [rRAMG], a
;	ld a, BMODE_ADVANCED
;	ld [rBMODE], a
;	xor a
;	ld [rRAMB], a
;	ld a, [sProcForestExitI]
;	ld b, a
;	ld a, BMODE_SIMPLE
;	ld [rBMODE], a
;	ld [rRAMG], a
;	ld a, b
;	add a, a
;	add a, a
;	add a, 2                    ; a = bossX = 4*exitI+2 (left exit tile X)
;	ld b, a                     ; b = bossX
;	; Player must be near the top of the map (exit is on the north edge).
;	ld a, [wYCoord]
;	cp 5
;	jp nc, CheckFightingMapTrainers
;	; Player X must be in [bossX, bossX+1] (the 2-tile-wide exit column).
;	ld a, [wXCoord]
;	cp b
;	jp c, CheckFightingMapTrainers    ; playerX < bossX
;	sub b
;	cp 2
;	jp nc, CheckFightingMapTrainers   ; playerX >= bossX+2
;	; --- trigger the boss battle (cemetery-4 mechanism) ---
;	xor a
;	ldh [hJoyHeld], a
;	ld a, TEXT_PROCEDURALFOREST_BOSS
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, [wRoguePokemon1]
;	ld [wCurOpponent], a               ; overworld loop starts a wild battle
;	farcall PCGetBossLevel             ; wCurEnemyLevel from wBattleCount
;	ld a, SCRIPT_PROCEDURALFOREST_BOSS_BATTLE
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret

; Wait for the boss battle to finish, then either offer to join (win) or push
; the player back down the corridor (loss/flee — though fleeing is blocked, a
; whiteout or the enemy fainting the player returns here). Mirrors cemetery 4.
;ProceduralForestBossBattleScript:
;	ldh a, [hIsInBattle]
;	cp $ff
;	jp z, ProceduralForestDefaultScript
;	ld a, PAD_BUTTONS | PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ld a, [wStatusFlags3]
;	bit BIT_TALKED_TO_TRAINER, a
;	ret nz
;	call UpdateSprites
;	ld a, PAD_CTRL_PAD
;	ldh [hJoyIgnore], a
;	ld a, [wBattleResult]
;	and a
;	jr nz, .didNotDefeat
;	; Won — offer the boss to join, then hide its sprite (frees the exit).
;	SetEvent EVENT_BEAT_PC_BOSS
;	ld a, TEXT_PROCEDURALFOREST_BOSS_OFFER
;	ldh [hTextID], a
;	call DisplayTextID
;	ld a, TOGGLE_FOREST_BOSS
;	ld [wToggleableObjectIndex], a
;	predef HideObject
;	xor a
;	ldh [hJoyIgnore], a
;	ld a, SCRIPT_PROCEDURALFOREST_DEFAULT
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret
;.didNotDefeat
;	ld a, $1
;	ldh [hSimulatedJoypadStatesIndex], a
;	ld a, PAD_DOWN
;	ld [wSimulatedJoypadStatesEnd], a
;	xor a
;	ld [wSpritePlayerStateData2MovementByte1], a
;	ld [wOverrideSimulatedJoypadStatesMask], a
;	ld hl, wStatusFlags5
;	set BIT_SCRIPTED_MOVEMENT_STATE, [hl]
;	;ld a, SCRIPT_PROCEDURALFOREST_PLAYER_MOVING
;	ld [wProceduralCave1CurScript], a
;	ld [wCurMapScript], a
;	ret

ProceduralForestPlayerMovingScript:
	ldh a, [hSimulatedJoypadStatesIndex]
	and a
	ret nz
	call Delay3
	xor a
	ld [wProceduralCave1CurScript], a
	ld [wCurMapScript], a
	ret

; Join offer — same shape as cave/cemetery. Shown via DisplayTextID (from the
; BossBattle win path) so the text box/font are set up properly.
ProceduralForestBossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName
	ld hl, PFBossJoinText
	call PrintText
	call YesNoChoice
	ld a, [hCurrentMenuItem]
	and a
	jr nz, .done
	farcall PCGetBossLevel
	ld a, [wRoguePokemon1]
	ld b, a
	ld a, [wCurEnemyLevel]
	ld c, a
	call GivePokemon
.done
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef HideObject
	jp TextScriptEnd

ProceduralForestInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralForestCurScript], a
	jp TextScriptEnd

; Shown the instant the boss battle triggers ("<NAME> blocks the path!").
ProceduralForestBossText:
; text_asm MUST be first byte - this is a text pointer, raw opcodes
	; would be read as text commands without it.
	text_asm
	push bc
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName             ; fill wNameBuffer before TalkToTrainer runs
	pop bc
	ld hl, .goBattle
	ret
.goBattle:
	; Go straight to battle - name display is in ProceduralCave1BossBattleText
	; (what TalkToTrainer shows), so there's only one text box, one A press.
	text_asm
	ld hl, PFBossTrainerHeader
	jr ProceduralForestInitBattleScript
    
; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralCave1BossText before TalkToTrainer ran.
ProceduralForestBossBattleText:
	text_far _PCBossEncounterText   ; "<NAME>!" + text_promptbutton (one A press)
	text_asm
	ld a, [wRoguePokemon1]
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd
	; NOTE: do NOT touch wCurMapScript or wProceduralCave1CurScript here.
	; TalkToTrainer increments wCurMapScript after this text returns, and
	; StartTrainerBattle increments it again. Setting it here corrupts
	; the state machine and causes a post-battle freeze.

PFBossBlocksText:
	text_ram wNameBuffer
	text " blocks"
	line "the path!"
	prompt

PFBossJoinText:
	text_far _PCBossJoinText
	text_end

ProceduralForestCalmedText:
	text_far _PCWildCalmedText
	text_end

; Cavern-style readable sign — same variant system as the cave's PCSignText.
PFSignText:
	text_asm
	; Read sign variant from SRAM (rolled at preload, stable for the whole run).
	; Use call PrintText — ld hl/ret causes TX_START to pop the text stream
	; pointer as the tile cursor, so line 1 writes off-screen (invisible).
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcForestSignVariant]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, b
	and a
	jr nz, .showBoss
	ld hl, PFSignItemsText
	jr .show
.showBoss
	ld hl, PFSignBossText
.show
	call PrintText
	ld hl, .signEnd    ; point NextTextCommand at TX_END for clean exit
	jp TextScriptEnd
.signEnd
	text_end

PFSignItemsText:
	text_far _PFSignItemsText
	text_end

PFSignBossText:
	text_far _PFSignBossText
	text_end

; --- Phase 7 rollout: stage-event NPCs (object slots 6-7) -----------------
; Byte-for-byte the same shape as the cave's own dispatch (scripts/
; ProceduralCave1.asm), reusing the SAME shared strings in text/StageEvents.asm
; - only the per-type pick/dispatch code is duplicated, per that file's own
; header ("The Forest, Facility and Cemetery reuse these strings as they grow
; their own NPC slots").

PFStageEventArrivalText:
	text_asm
	ld hl, PFStageEventArrivalTexts
	call PFStageEventPickText
	call PrintText
	farcall StageEventPrintLootLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

PFStageEventHideoutText:
	text_asm
	ld hl, PFStageEventHideoutTexts
	call PFStageEventPickText
	call PrintText
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; The END-BATTLE beat: what the trainer says the instant the player wins.
;
; THIS IS THE ONLY STAGE-EVENT TEXT NOT FIRED THROUGH DisplayTextID.
; engine/battle/core.asm calls PrintEndBattleText directly, which means two
; things that are not true anywhere else in this file:
;
;   1. There is no AfterDisplayingTextID wait afterwards, so the string has to
;      carry its own `prompt`. Without one the box printed and returned and
;      the "got money for winning" box drew straight over the top of it.
;   2. PrintEndBattleText has ALREADY written "<CLASS>: " into the box from
;      _TrainerNameText before handing the stream here.
;
; (2) is why this RETURNS hl instead of doing `call PrintText` the way every
; other handler here does. PrintText goes through DisplayTextBoxID, which
; redraws the message box - and TextBoxBorder blanks the interior - so calling
; it wiped the trainer's name three frames after it appeared. That flash was
; the reported bug. Continuing the stream leaves the name where it is and the
; defeat line flows on after it, exactly like a route trainer.
;
; bc IS THE LIVE TILE CURSOR and PFStageEventPickText destroys it (it uses bc
; as the table offset). That is precisely the misprint the Cave's PCSignText
; header warns about - TX_START then places line 1 at a garbage coordinate, off
; screen. Saving bc across the call is what makes the `ld hl` / `ret` shape
; legal here; do not drop the push/pop.
;
PFStageEventDefeatText:
	text_asm
	push bc
	ld hl, PFStageEventDefeatTexts
	call PFStageEventPickText
	pop bc
	ret

; What a beaten stage-event NPC says when talked to again (1C, 2026-09-22).
; The body is StageEventPrintAfterLine in bank $3A, shared by all four stages
; - see the Cave's copy of this stub for why it is not inline.
PFStageEventAfterText:
	text_asm
	farcall StageEventPrintAfterLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; Dispatch and strings are in bank $3A - see the Cave's copy of this stub.
PFStageEventRecoverText:
	text_asm
	farcall StageEventPrintRecoverLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

PFStageEventNpc1Text:
	text_asm
	ld hl, PFStageNpc1Header
	jp ProceduralForestInitBattleScript

PFStageEventNpc2Text:
	text_asm
	ld hl, PFStageNpc2Header
	jp ProceduralForestInitBattleScript

; INPUT: hl = a six-entry table of text pointers, ordered by STAGE_EVENT_*
; type starting at type 1. OUTPUT: hl = the entry for the currently armed
; event. Same logic as the cave's own PCStageEventPickText, duplicated rather
; than shared - map scripts are not guaranteed same-bank, and both are tiny.
; bc is free to clobber (see the cave's version for why).
PFStageEventPickText:
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	dec a
	add a, a
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

PFStageEventArrivalTexts:
	dw PFStageArrivalJessieJames  ; STAGE_EVENT_JESSIE_JAMES
	dw PFStageArrivalPsychic      ; STAGE_EVENT_PSYCHIC
	dw PFStageArrivalBurglar      ; STAGE_EVENT_BURGLAR
	dw PFStageArrivalJoy          ; STAGE_EVENT_JOY
	dw PFStageArrivalJenny        ; STAGE_EVENT_JENNY
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFStageEventArrivalTexts needs a row per stage-event type"

PFStageEventHideoutTexts:
	dw PFStageHideoutJessieJames
	dw PFStageHideoutPsychic
	dw PFStageHideoutBurglar
	dw PFStageHideoutJoy
	dw PFStageHideoutJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFStageEventHideoutTexts needs a row per stage-event type"

PFStageEventDefeatTexts:
	dw PFStageDefeatJessieJames
	dw PFStageDefeatPsychic
	dw PFStageDefeatBurglar
	dw PFStageDefeatJoy
	dw PFStageDefeatJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFStageEventDefeatTexts needs a row per stage-event type"

PFStageArrivalJessieJames:
	text_far _StageEventArrivalJessieJamesText
	text_end
PFStageArrivalPsychic:
	text_far _StageEventArrivalPsychicText
	text_end
PFStageArrivalBurglar:
	text_far _StageEventArrivalBurglarText
	text_end
PFStageArrivalJoy:
	text_far _StageEventArrivalJoyText
	text_end
PFStageArrivalJenny:
	text_far _StageEventArrivalJennyText
	text_end

PFStageHideoutJessieJames:
	text_far _StageEventHideoutJessieJamesText
	text_end
PFStageHideoutPsychic:
	text_far _StageEventHideoutPsychicText
	text_end
PFStageHideoutBurglar:
	text_far _StageEventHideoutBurglarText
	text_end
PFStageHideoutJoy:
	text_far _StageEventHideoutJoyText
	text_end
PFStageHideoutJenny:
	text_far _StageEventHideoutJennyText
	text_end

PFStageDefeatJessieJames:
	text_far _StageEventDefeatJessieJamesText
	text_end
PFStageDefeatPsychic:
	text_far _StageEventDefeatPsychicText
	text_end
PFStageDefeatBurglar:
	text_far _StageEventDefeatBurglarText
	text_end
PFStageDefeatJoy:
	text_far _StageEventDefeatJoyText
	text_end
PFStageDefeatJenny:
	text_far _StageEventDefeatJennyText
	text_end

ProceduralForest_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING: see scripts/ProceduralCave1.asm's copy of this
	; note. The first wNumSprites entries must be the objects' own text, in
	; slot order, or DisplayTextID's .spriteHandling branch reroutes any
	; script-fired constant whose value is <= the object count. Measured here
	; before the reorder: CALMED printed the stage NPC's line.
	dw_const ProceduralForestBossText, TEXT_PROCEDURALFOREST_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFOREST_POKEBALL_4
	dw_const PFStageEventNpc1Text, TEXT_PROCEDURALFOREST_STAGE_NPC_1
	dw_const PFStageEventNpc2Text, TEXT_PROCEDURALFOREST_STAGE_NPC_2
	; --- end of the object block (7 objects); script-only ids follow ---
	dw_const ProceduralForestBossOfferText, TEXT_PROCEDURALFOREST_BOSS_OFFER
	dw_const PCWildCalmedText, TEXT_PROCEDURALFOREST_CALMED
	EXPORT TEXT_PROCEDURALFOREST_CALMED ; used by engine/battle/wild_encounters.asm
	dw_const PFSignText, TEXT_PROCEDURALFOREST_SIGN
	dw_const PFStageEventArrivalText, TEXT_PROCEDURALFOREST_STAGE_EVENT
	dw_const PFStageEventRecoverText, TEXT_PROCEDURALFOREST_STAGE_RECOVER
