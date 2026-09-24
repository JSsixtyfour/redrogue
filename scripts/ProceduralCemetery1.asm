; Cemetery floor 1. This file also owns the stage-event machinery the other
; three floors share: the trainer header table, the script-pointer table, the
; battle shim and every text handler. All four cemetery scripts are INCLUDEd
; into maps.asm's "Maps 6" section, so they assemble into the same bank and
; the cross-file references from floors 2-4 are plain same-bank pointers -
; the same reason PCemCalmedText has always been defined here and used by all
; four TextPointers tables.
;
; WHY THE CEMETERY IS NOT A COPY OF THE CAVE. It is the only wild area whose
; arrival and hideout are on DIFFERENT MAPS. The player can only enter at
; floor 1, so that is the only place the villain can catch them; the hideout
; is rolled among floors 2-4 (PCemRollStageHideoutFloor) so recovering the
; stolen thing always costs a descent. That splits the script work cleanly:
; floor 1 runs the ARRIVAL and never the recovery, floors 2-4 run the
; RECOVERY and never the arrival. No floor needs both.

ProceduralCemetery1_Script:
	CheckEvent EVENT_ENTER_ROOM
	jr nz, .afterSetup
	SetEvent EVENT_ENTER_ROOM
	call PCemStageEnterSetup
.afterSetup
	; --- Phase 7 rollout: the arrival -------------------------------------
	; Same shape as the cave's and forest's .afterSetup block: it fires on
	; load rather than on the player's first step, and the phase field IS the
	; one-shot, so no extra event bit is needed.
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
	ld a, TEXT_PROCEDURALCEMETERY1_STAGE_EVENT
	ldh [hTextID], a
	call DisplayTextID
	farcall PCemStageEventVanish    ; fade, leave the floor entirely -> HIDING
	jr .afterStageEvent
.goodNpcSettle
	ld a, [wStageEvent]
	and ~STAGE_EVENT_PHASE_MASK & $ff
	or STAGE_EVENT_PHASE_SETTLED << STAGE_EVENT_PHASE_SHIFT
	ld [wStageEvent], a
.afterStageEvent
	call PCemCalmedCheck
	jp PCemStageRunScripts

; ============================================================
; Shared fresh-entry setup, used by all four floors.
;
; All four floors SHARE wProceduralCemetery4CurScript. That is safe - only one
; wild area is ever live, and a trainer battle is modal, so it cannot straddle
; a floor change - but it is reset on entry anyway: floor 4's pointer table
; has five entries and floors 1-3 have three, so a stale floor-4 index carried
; back upstairs would dispatch off the end of the shorter table.
; ============================================================
PCemStageEnterSetup::
	xor a
	ld [wProceduralCemetery4CurScript], a
	farcall PCemRefreshBall
	farcall PCemShowStageEventNpcs
	ret

; Shared script dispatch for floors 1-3. Floor 4 has its own copy because it
; passes its own five-entry pointer table.
PCemStageRunScripts::
	call EnableAutoTextBoxDrawing
	ld hl, PCemStageTrainerHeaders
	ld de, PCemStageScriptPointers
	ld a, [wProceduralCemetery4CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCemetery4CurScript], a
	ret

; ============================================================
; PCemStageEventRecoverCheck
; The recovery, shared by floors 2-4 (floor 1 is the arrival floor and is
; excluded from the hideout roll, so it can never owe anything back).
;
; INPUT: d = this floor's TEXT_..._STAGE_RECOVER id. It travels in d rather
; than a because the body farcalls three times and Bankswitch destroys
; a/b/c/h/l on both legs - d and e are the only registers that survive one.
; The CheckEvent macro only touches a/hl, so d is safe across it too.
; ============================================================
PCemStageEventRecoverCheck::
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	ret z                           ; no event armed
	ld a, [wStageEvent]
	and STAGE_EVENT_PHASE_MASK
	cp STAGE_EVENT_PHASE_HIDING << STAGE_EVENT_PHASE_SHIFT
	ret nz                          ; not robbed-and-hiding, so nothing owed
	CheckEvent EVENT_BEAT_FACILITY_STAGE_NPC_1
	jr nz, .recover
	CheckEvent EVENT_BEAT_FACILITY_STAGE_NPC_2
	ret z
.recover
	ld a, [wStatusFlags3]
	bit BIT_PRINT_END_BATTLE_TEXT, a
	ret nz
	call Delay3
	; GiveBack stores its own result into wStageEventScratch. It cannot hand
	; it back in `a`: farcall returns through Bankswitch, which ends with
	; `ld a, b` = this script's ROM bank.
	farcall StageEventGiveBack      ; -> wStageEventScratch, -> SETTLED or OWED
	; A PAIR IS ONE ENCOUNTER: beating either one ends it. Both NPCs used to
	; be hidden here, which is what made that true. 1C leaves them standing so
	; a hand-over that found no room can be retried by talking to them, so the
	; partner is marked beaten instead - otherwise the player could start a
	; second battle with nothing left to win. Both flags set means
	; TalkToTrainer gives the survivor the after-battle line, which is also
	; the retry. SetEvent only touches a/hl, so d survives it.
	SetEvent EVENT_BEAT_FACILITY_STAGE_NPC_1
	SetEvent EVENT_BEAT_FACILITY_STAGE_NPC_2
	ld a, d
	ldh [hTextID], a
	call DisplayTextID
	jp DisableWaitingAfterTextDisplay

; ============================================================
; Shared stage-event trainer headers for ALL FOUR cemetery floors.
;
; One table serves every floor because a trainer header carries nothing
; map-specific: the `trainer` macro emits the sprite slot (CURRENT_TRAINER_BIT),
; the event flag and the text pointers, and all four floors use object slots
; 2-3 with the same events and the same text. Slot 1 on every floor is that
; floor's pokeball, which is an ITEM and has no header.
;
; The events are shared with the Facility, which also puts its pair on a
; slot-2-aligned pair of bits. That is the same deliberate sharing the Cave
; and Forest already do with EVENT_BEAT_STAGE_EVENT_NPC_1/2: only one wild
; area is ever offered per lobby visit, and every stage's preload now resets
; both pairs.
; ============================================================
; The END-BATTLE pointer below is the CAVE's PCStageEventDefeatText, not a
; local one. maps.asm includes ProceduralCave1.asm and this file in the one
; "Maps 6" SECTION, and a SECTION cannot straddle a bank, so the call is
; always in-bank. Bank 17 had 95 free bytes when this was written and a
; second dispatcher plus table plus six text_far wrappers does not fit in
; that. The dispatcher reads wStageEvent and nothing map-specific, and this
; map's own PCemStageEventPickText is byte-identical to the Cave's, so there
; is nothing to diverge. If this file ever moves to its own SECTION, give it
; a local copy back.
PCemStageTrainerHeaders::
	def_trainers 2  ; slot 1 is the pokeball; the NPC pair is slots 2-3, and
	                ; EVENT_BEAT_FACILITY_STAGE_NPC_1 % 8 == 2 == 2 % 8
	                ; satisfies the trainer macro's alignment ASSERT.
PCemStageNpc1Header::
	trainer EVENT_BEAT_FACILITY_STAGE_NPC_1, 4, PCemStageEventHideoutText, PCStageEventDefeatText, PCStageEventAfterText
PCemStageNpc2Header::
	trainer EVENT_BEAT_FACILITY_STAGE_NPC_2, 4, PCemStageEventHideoutText, PCStageEventDefeatText, PCStageEventAfterText
	db -1 ; end

; Shared by floors 1-3. Floor 4 keeps its own five-entry table because it also
; carries the boss-battle and player-moving states; indices 0-2 match here, so
; the shared CurScript byte means the same thing on all four floors.
PCemStageScriptPointers::
	def_script_pointers
	dw_const PCemStageDefaultScript,                SCRIPT_PCEMSTAGE_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PCEMSTAGE_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PCEMSTAGE_END_BATTLE

; Floors 1-3 have no boss, so the default state is nothing but the ordinary
; sight-range trainer scan. Floor 4 has its own default script, which runs the
; boss proximity trigger FIRST and then falls through to the same scan.
PCemStageDefaultScript::
	jp CheckFightingMapTrainers

PCemStageInitBattleScript::
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralCemetery4CurScript], a
	jp TextScriptEnd

; ============================================================
; Shared text handlers. Defined once here and referenced from all four
; TextPointers tables, which is possible only because the four scripts share
; a bank (see this file's header).
; ============================================================
PCemStageEventNpc1Text::
	text_asm
	ld hl, PCemStageNpc1Header
	jp PCemStageInitBattleScript

PCemStageEventNpc2Text::
	text_asm
	ld hl, PCemStageNpc2Header
	jp PCemStageInitBattleScript

PCemStageEventArrivalText::
	text_asm
	ld hl, PCemStageEventArrivalTexts
	call PCemStageEventPickText
	call PrintText
	farcall StageEventPrintLootLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

PCemStageEventHideoutText::
	text_asm
	ld hl, PCemStageEventHideoutTexts
	call PCemStageEventPickText
	call PrintText
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; Dispatch and strings are in bank $3A - see the Cave's copy of this stub.
PCemStageEventRecoverText::
	text_asm
	farcall StageEventPrintRecoverLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; INPUT: hl = a six-entry table of text pointers, ordered by STAGE_EVENT_*
; type starting at type 1. OUTPUT: hl = the entry for the armed event.
; Same logic as the cave's and forest's own copies; bc is free to clobber.
PCemStageEventPickText::
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

PCemStageEventArrivalTexts:
	dw PCemStageArrivalJessieJames  ; STAGE_EVENT_JESSIE_JAMES
	dw PCemStageArrivalPsychic      ; STAGE_EVENT_PSYCHIC
	dw PCemStageArrivalBurglar      ; STAGE_EVENT_BURGLAR
	dw PCemStageArrivalJoy          ; STAGE_EVENT_JOY
	dw PCemStageArrivalJenny        ; STAGE_EVENT_JENNY
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PCemStageEventArrivalTexts needs a row per stage-event type"

PCemStageEventHideoutTexts:
	dw PCemStageHideoutJessieJames
	dw PCemStageHideoutPsychic
	dw PCemStageHideoutBurglar
	dw PCemStageHideoutJoy
	dw PCemStageHideoutJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PCemStageEventHideoutTexts needs a row per stage-event type"

PCemStageArrivalJessieJames:
	text_far _StageEventArrivalJessieJamesText
	text_end
PCemStageArrivalPsychic:
	text_far _StageEventArrivalPsychicText
	text_end
PCemStageArrivalBurglar:
	text_far _StageEventArrivalBurglarText
	text_end
PCemStageArrivalJoy:
	text_far _StageEventArrivalJoyText
	text_end
PCemStageArrivalJenny:
	text_far _StageEventArrivalJennyText
	text_end

PCemStageHideoutJessieJames:
	text_far _StageEventHideoutJessieJamesText
	text_end
PCemStageHideoutPsychic:
	text_far _StageEventHideoutPsychicText
	text_end
PCemStageHideoutBurglar:
	text_far _StageEventHideoutBurglarText
	text_end
PCemStageHideoutJoy:
	text_far _StageEventHideoutJoyText
	text_end
PCemStageHideoutJenny:
	text_far _StageEventHideoutJennyText
	text_end

ProceduralCemetery1_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING: see scripts/ProceduralCave1.asm's copy of this
	; note. The first wNumSprites entries must be the objects' own text, in
	; slot order, or DisplayTextID's .spriteHandling branch reroutes any
	; script-fired constant whose value is <= the object count. Measured here
	; before the reorder: CALMED printed the stage NPC's line.
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCEMETERY1_POKEBALL
	dw_const PCemStageEventNpc1Text, TEXT_PROCEDURALCEMETERY1_STAGE_NPC_1
	dw_const PCemStageEventNpc2Text, TEXT_PROCEDURALCEMETERY1_STAGE_NPC_2
	; --- end of the object block (3 objects); script-only ids follow ---
	dw_const PCemCalmedText, TEXT_PROCEDURALCEMETERY1_CALMED
	dw_const PCemStageEventArrivalText, TEXT_PROCEDURALCEMETERY1_STAGE_EVENT
	dw_const PCemStageEventRecoverText, TEXT_PROCEDURALCEMETERY1_STAGE_RECOVER

PCemCalmedText::
	text_far _ProceduralCemeteryCalmedText
	text_end
