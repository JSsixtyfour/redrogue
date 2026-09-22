; Close copy of scripts/ProceduralCave1.asm (the fundamentals-mandated baseline
; for a stage with a real overworld boss sprite - see PROCEDURAL_STAGE_FUNDAMENTALS.md).
; Reused events (never concurrent with cave/forest/cemetery, all reset at Pallet
; lobby assignment by PFacPreload):
;   EVENT_BEAT_PC_BOSS  - boss defeated / offered (bit-aligned for slot-1 trainer)
;   EVENT_PC_BOSS_OFFERED
;   EVENT_PC_BUDGET_ENDED / EVENT_PC_CALMED_SHOWN - wild budget calmed message

ProceduralFacility_Script:
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
	; Fresh generation also restores all four fake balls. Their independent
	; trainer events and toggle bits keep defeated balls hidden on re-entry.
	ld a, TOGGLE_FACILITY_FAKE_BALL_1
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_FACILITY_FAKE_BALL_2
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_FACILITY_FAKE_BALL_3
	ld [wToggleableObjectIndex], a
	predef ShowObject
	ld a, TOGGLE_FACILITY_FAKE_BALL_4
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Show the boss only if it hasn't been beaten yet.
	CheckEvent EVENT_BEAT_PC_BOSS
	jr nz, .afterSetup
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef ShowObject
	; Phase 7 rollout: reveal the stage-event NPC slots (10-11), but only for
	; the slots this event actually uses.
	farcall PFacShowStageEventNpcs
.afterSetup
	; --- Phase 7 rollout: stage-event arrival -----------------------------
	; Byte-for-byte the same shape as the cave's own .afterSetup block.
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
	ld a, TEXT_PROCEDURALFACILITY_STAGE_EVENT
	ldh [hTextID], a
	call DisplayTextID
	farcall PFacStageEventVanish    ; fade out, relocate, fade in; -> HIDING
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
	ld a, TEXT_PROCEDURALFACILITY_CALMED
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
	CheckEvent EVENT_BEAT_FACILITY_STAGE_NPC_1
	jr nz, .recover
	CheckEvent EVENT_BEAT_FACILITY_STAGE_NPC_2
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
	SetEvent EVENT_BEAT_FACILITY_STAGE_NPC_1
	SetEvent EVENT_BEAT_FACILITY_STAGE_NPC_2
	ld a, TEXT_PROCEDURALFACILITY_STAGE_RECOVER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.afterRecovery
	; One-time join offer, shown after the boss is beaten and the end-battle
	; text has fully cleared (same shape cave/forest use).
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
	ld a, TEXT_PROCEDURALFACILITY_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralFacilityTrainerHeaders
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
	cp 10
	jr c, .haveTrainerHeaders
	ld hl, PFacStageNpc1Header
.haveTrainerHeaders
	ld de, ProceduralFacility_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

ProceduralFacility_ScriptPointers:
	def_script_pointers
	dw_const ProceduralFacilityDefaultScript,       SCRIPT_PROCEDURALFACILITY_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALFACILITY_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALFACILITY_END_BATTLE

; The fixed-facing boss guards one of the two exit tiles through ordinary
; trainer sight. Detect the unguarded flank and dispatch the same object text
; interaction used when the player presses A, matching Procedural Forest.
ProceduralFacilityDefaultScript:
	CheckEvent EVENT_BEAT_PC_BOSS
	jp nz, CheckFightingMapTrainers
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	ld a, BANK(sProcFacilityStagingBuffer)
	ld [rRAMB], a
	ld a, [sProcFacilityExitEdge]
	ld c, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ASSERT RAMG_SRAM_DISABLE == BMODE_SIMPLE
	ld [rRAMG], a
	ld a, c
	and a
	jr z, .flankNorth
	; West/East: same column as boss, one tile below.
	ld a, [wSprite01StateData2MapX]
	sub 4
	ld b, a
	ld a, [wXCoord]
	cp b
	jp nz, CheckFightingMapTrainers
	ld a, [wSprite01StateData2MapY]
	sub 4
	inc a
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
	sub 4
	inc a
	ld b, a
	ld a, [wXCoord]
	cp b
	jp nz, CheckFightingMapTrainers
.flankHit
	xor a
	ldh [hJoyHeld], a
	ld a, TEXT_PROCEDURALFACILITY_BOSS
	ldh [hTextID], a
	call DisplayTextID
	ret

; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text on the cave).
ProceduralFacilityBossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName               ; fill wNameBuffer for the offer text
	ld hl, PFacBossJoinText
	call PrintText
	call YesNoChoice              ; yes -> carry set
    ld a, [hCurrentMenuItem]
	and a
	jr nz, .done ; if player chose No
	farcall PCGetBossLevel        ; sets wCurEnemyLevel from wBattleCount
	ld a, [wRoguePokemon1]
	ld b, a                       ; b = species
	ld a, [wCurEnemyLevel]
	ld c, a                       ; c = level
	call GivePokemon
.done
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef HideObject
	jp TextScriptEnd

PFacBossJoinText:
	text_far _PCBossJoinText
	text_end

PFacWildCalmedText:
	text_far _PCWildCalmedText
	text_end

ProceduralFacility_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING: see scripts/ProceduralCave1.asm's copy of this
	; note. The first wNumSprites entries must be the objects' own text, in
	; slot order, or DisplayTextID's .spriteHandling branch reroutes any
	; script-fired constant whose value is <= the object count. Measured here
	; before the reorder: CALMED printed the stage NPC's line.
    dw_const ProceduralFacilityBossText, TEXT_PROCEDURALFACILITY_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALFACILITY_WILD_AREA_POKEBALL_4
	dw_const ProceduralFacilityFakeBall1Text, TEXT_PROCEDURALFACILITY_FAKE_BALL_1
	dw_const ProceduralFacilityFakeBall2Text, TEXT_PROCEDURALFACILITY_FAKE_BALL_2
	dw_const ProceduralFacilityFakeBall3Text, TEXT_PROCEDURALFACILITY_FAKE_BALL_3
	dw_const ProceduralFacilityFakeBall4Text, TEXT_PROCEDURALFACILITY_FAKE_BALL_4
	dw_const PFacStageEventNpc1Text, TEXT_PROCEDURALFACILITY_STAGE_NPC_1
	dw_const PFacStageEventNpc2Text, TEXT_PROCEDURALFACILITY_STAGE_NPC_2
	; --- end of the object block (11 objects); script-only ids follow ---
	dw_const ProceduralFacilityBossOfferText, TEXT_PROCEDURALFACILITY_BOSS_OFFER
	dw_const PFacWildCalmedText, TEXT_PROCEDURALFACILITY_CALMED
	EXPORT TEXT_PROCEDURALFACILITY_CALMED ; used by engine/battle/wild_encounters.asm
	dw_const PFacStageEventArrivalText, TEXT_PROCEDURALFACILITY_STAGE_EVENT
	dw_const PFacStageEventRecoverText, TEXT_PROCEDURALFACILITY_STAGE_RECOVER

ProceduralFacilityTrainerHeaders:
PFacBossTrainerHeader:
	; EVENT_BEAT_PC_BOSS is shared with the other procedural maps. Emit this
	; established slot-1 header directly so the event-layout generator can treat
	; the new slot-6-through-9 quartet as its own aligned trainer run.
	ASSERT EVENT_BEAT_PC_BOSS % 8 == 1
	db 1
	db 0
	dw wEventFlags + (EVENT_BEAT_PC_BOSS - 1) / 8
	dw ProceduralFacilityBossBattleText, ProceduralFacilityBossBattleText
	dw ProceduralFacilityBossBattleText, ProceduralFacilityBossBattleText
	; Slots 2-5 are items, so resume the trainer-bit sequence at object slot 6.
	def_trainers 6
PFacFakeBall1Header:
	trainer EVENT_BEAT_FACILITY_FAKE_BALL_1, 0, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText
PFacFakeBall2Header:
	trainer EVENT_BEAT_FACILITY_FAKE_BALL_2, 0, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText
PFacFakeBall3Header:
	trainer EVENT_BEAT_FACILITY_FAKE_BALL_3, 0, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText
PFacFakeBall4Header:
	trainer EVENT_BEAT_FACILITY_FAKE_BALL_4, 0, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText, ProceduralFacilityFakeBallBattleText
	; Slots 6-9 are the four fake balls above, so resume the trainer-bit
	; sequence at object slot 10, where the Phase 7 stage-event NPCs live -
	; the facility is the one stage that could not reuse slots 6-7.
	def_trainers 10
PFacStageNpc1Header:
	trainer EVENT_BEAT_FACILITY_STAGE_NPC_1, 4, PFacStageEventHideoutText, PFacStageEventDefeatText, PFacStageEventAfterText
PFacStageNpc2Header:
	trainer EVENT_BEAT_FACILITY_STAGE_NPC_2, 4, PFacStageEventHideoutText, PFacStageEventDefeatText, PFacStageEventAfterText
	db -1 ; end

ProceduralFacilityInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralCave1CurScript], a
	jp TextScriptEnd

ProceduralFacilityBossText:
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
	; Go straight to battle - name display is in ProceduralFacilityBossBattleText
	; (what TalkToTrainer shows), so there's only one text box, one A press.
	text_asm
	ld hl, PFacBossTrainerHeader
	jr ProceduralFacilityInitBattleScript

; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralFacilityBossText before TalkToTrainer ran.
ProceduralFacilityBossBattleText:
	text_far _PCBossEncounterText   ; "<NAME>!@" + text_end, no prompt
	text_asm
	ld a, [wRoguePokemon1]
	call PlayCry
	call WaitForSoundToFinish
	jp TextScriptEnd
	; NOTE: do NOT touch wCurMapScript or wProceduralCave1CurScript here.
	; TalkToTrainer increments wCurMapScript after this text returns, and
	; StartTrainerBattle increments it again. Setting it here corrupts
	; the state machine and causes a post-battle freeze.

ProceduralFacilityFakeBall1Text:
	text_asm
	ld hl, PFacFakeBall1Header
	jr ProceduralFacilityInitBattleScript

ProceduralFacilityFakeBall2Text:
	text_asm
	ld hl, PFacFakeBall2Header
	jr ProceduralFacilityInitBattleScript

ProceduralFacilityFakeBall3Text:
	text_asm
	ld hl, PFacFakeBall3Header
	jr ProceduralFacilityInitBattleScript

ProceduralFacilityFakeBall4Text:
	text_asm
	ld hl, PFacFakeBall4Header
	jr ProceduralFacilityInitBattleScript

ProceduralFacilityFakeBallBattleText:
	text_far _PowerPlantVoltorbBattleText
	text_end

; --- Phase 7 rollout: stage-event NPCs (object slots 10-11) ---------------
; Byte-for-byte the same shape as the cave's own dispatch, reusing the shared
; strings in text/StageEvents.asm.

PFacStageEventArrivalText:
	text_asm
	ld hl, PFacStageEventArrivalTexts
	call PFacStageEventPickText
	call PrintText
	farcall StageEventPrintLootLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

PFacStageEventHideoutText:
	text_asm
	ld hl, PFacStageEventHideoutTexts
	call PFacStageEventPickText
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
; bc IS THE LIVE TILE CURSOR and PFacStageEventPickText destroys it (it uses bc
; as the table offset). That is precisely the misprint the Cave's PCSignText
; header warns about - TX_START then places line 1 at a garbage coordinate, off
; screen. Saving bc across the call is what makes the `ld hl` / `ret` shape
; legal here; do not drop the push/pop.
;
PFacStageEventDefeatText:
	text_asm
	push bc
	ld hl, PFacStageEventDefeatTexts
	call PFacStageEventPickText
	pop bc
	ret

; What a beaten stage-event NPC says when talked to again (1C, 2026-09-22).
; The body is StageEventPrintAfterLine in bank $3A, shared by all four stages
; - see the Cave's copy of this stub for why it is not inline.
PFacStageEventAfterText:
	text_asm
	farcall StageEventPrintAfterLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; Dispatch and strings are in bank $3A - see the Cave's copy of this stub.
PFacStageEventRecoverText:
	text_asm
	farcall StageEventPrintRecoverLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

PFacStageEventNpc1Text:
	text_asm
	ld hl, PFacStageNpc1Header
	jp ProceduralFacilityInitBattleScript

PFacStageEventNpc2Text:
	text_asm
	ld hl, PFacStageNpc2Header
	jp ProceduralFacilityInitBattleScript

; INPUT: hl = a six-entry table of text pointers, ordered by STAGE_EVENT_*
; type starting at type 1. OUTPUT: hl = the entry for the currently armed
; event. Own copy, not shared - map scripts are not guaranteed same-bank.
PFacStageEventPickText:
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

PFacStageEventArrivalTexts:
	dw PFacStageArrivalJessieJames
	dw PFacStageArrivalPsychic
	dw PFacStageArrivalBurglar
	dw PFacStageArrivalJoy
	dw PFacStageArrivalJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFacStageEventArrivalTexts needs a row per stage-event type"

PFacStageEventHideoutTexts:
	dw PFacStageHideoutJessieJames
	dw PFacStageHideoutPsychic
	dw PFacStageHideoutBurglar
	dw PFacStageHideoutJoy
	dw PFacStageHideoutJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFacStageEventHideoutTexts needs a row per stage-event type"

PFacStageEventDefeatTexts:
	dw PFacStageDefeatJessieJames
	dw PFacStageDefeatPsychic
	dw PFacStageDefeatBurglar
	dw PFacStageDefeatJoy
	dw PFacStageDefeatJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PFacStageEventDefeatTexts needs a row per stage-event type"

PFacStageArrivalJessieJames:
	text_far _StageEventArrivalJessieJamesText
	text_end
PFacStageArrivalPsychic:
	text_far _StageEventArrivalPsychicText
	text_end
PFacStageArrivalBurglar:
	text_far _StageEventArrivalBurglarText
	text_end
PFacStageArrivalJoy:
	text_far _StageEventArrivalJoyText
	text_end
PFacStageArrivalJenny:
	text_far _StageEventArrivalJennyText
	text_end

PFacStageHideoutJessieJames:
	text_far _StageEventHideoutJessieJamesText
	text_end
PFacStageHideoutPsychic:
	text_far _StageEventHideoutPsychicText
	text_end
PFacStageHideoutBurglar:
	text_far _StageEventHideoutBurglarText
	text_end
PFacStageHideoutJoy:
	text_far _StageEventHideoutJoyText
	text_end
PFacStageHideoutJenny:
	text_far _StageEventHideoutJennyText
	text_end

PFacStageDefeatJessieJames:
	text_far _StageEventDefeatJessieJamesText
	text_end
PFacStageDefeatPsychic:
	text_far _StageEventDefeatPsychicText
	text_end
PFacStageDefeatBurglar:
	text_far _StageEventDefeatBurglarText
	text_end
PFacStageDefeatJoy:
	text_far _StageEventDefeatJoyText
	text_end
PFacStageDefeatJenny:
	text_far _StageEventDefeatJennyText
	text_end
