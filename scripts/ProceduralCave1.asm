ProceduralCave1_Script:
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
	; Phase 7b: reveal the stage-event NPC slots, but only for the slots this
	; event actually uses. The staged sprite doubles as the "slot in use" flag
	; - it is the same byte ProcBossPatchStageSprite installs as PICTUREID, so
	; showing a slot whose sprite is 0 could never put anything on screen
	; anyway. Reading it here keeps the two decisions from being able to
	; disagree.
	farcall StageEventShowCaveNpcs
	; Show the boss only if it hasn't been beaten yet.
	CheckEvent EVENT_BEAT_PC_BOSS
	jr nz, .afterSetup
	ld a, TOGGLE_WILD_AREA_BOSS
	ld [wToggleableObjectIndex], a
	predef ShowObject
.afterSetup
	; --- Phase 7c: stage-event arrival ------------------------------------
	; The villains are standing in front of the player when the map fades in;
	; this fires their line on the first script tick after the load, then the
	; dark flash relocates them to the hideout.
	;
	; Deliberately NOT waiting for the player to take a step. Nothing here
	; needs the player to have moved, and firing on load removes an entire
	; class of trigger bug (a player who walks straight into the exit, or who
	; never steps in the direction the trigger expected).
	;
	; THE ONE-SHOT IS wStageEvent's OWN PHASE FIELD, not a new event flag.
	; WAITING -> HIDING is a transition the feature needs regardless, so there
	; is no second piece of state that could fall out of sync with it, and no
	; EVENT_* bit spent.
	;
	; BIT_CUR_MAP_LOADED_1 is TESTED here and never `res`-ed, exactly like the
	; calm check below. That is what keeps this clear of the shared-script-flag
	; starvation trap (project_shared_script_flag_bit): that bug is caused by a
	; check-AND-CLEAR consuming the bit before a later reader sees it. Two pure
	; tests of the same bit cannot starve each other. If anything in this
	; script ever starts clearing bit 1, both of these readers break together
	; and this one must move to bit 2.
	ld hl, wCurrentMapScriptFlags
	bit BIT_CUR_MAP_LOADED_1, [hl]
	jr z, .afterStageEvent
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	jr z, .afterStageEvent          ; no event armed on this wild area
	ld a, [wStageEvent]
	and STAGE_EVENT_PHASE_MASK
	jr nz, .afterStageEvent         ; already spoken - they are at the hideout
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
	; Phase 7d: rob the player BETWEEN the threat and the vanish, so the beat
	; reads threat -> loss -> escape. Leaves sStolenKind = STOLEN_NOTHING if
	; its guards refuse (one mon left, or every mon fused), which is a valid
	; outcome rather than an error - the villain still flees and can still be
	; fought, there is just nothing to win back.
	farcall StageEventDoTheft
	ld a, TEXT_PROCEDURALCAVE1_STAGE_EVENT
	ldh [hTextID], a
	call DisplayTextID
	farcall PCStageEventVanish      ; fade out, relocate, fade in; -> HIDING
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
	ld a, TEXT_PROCEDURALCAVE1_CALMED
	ldh [hTextID], a
	call DisplayTextID
.afterCalm
	; --- Phase 7e: recovery, once the villain is beaten ---------------------
	; Same shape as the boss join offer below: wait for the beat flag AND for
	; the end-battle text to have cleared, or the reward text lands on top of
	; the battle's own closing box.
	;
	; The one-shot is the phase: this only runs at HIDING, and
	; StageEventGiveBack always leaves a different one - SETTLED when the
	; goods went back, OWED when there was no room for them. Either way this
	; cannot fire twice, even if both halves of a pair are beaten. OWED then
	; hands the retry to the NPC's own after-battle text.
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	jr z, .afterRecovery            ; no event armed
	ld a, [wStageEvent]
	and STAGE_EVENT_PHASE_MASK
	cp STAGE_EVENT_PHASE_HIDING << STAGE_EVENT_PHASE_SHIFT
	jr nz, .afterRecovery           ; not robbed-and-hiding, so nothing owed
	; EITHER half of a pair counts. Jessie and James are two objects with two
	; flags, and the player can fight them in either order; making only slot 6
	; pay out would hide the reward behind whichever one they happened to
	; approach second.
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
	; A PAIR IS ONE ENCOUNTER, not two. Jessie and James are two objects
	; because they are two sprites, but beating either ends the event.
	;
	; They used to be HIDDEN here, both of them, which is what made that true.
	; 1C leaves them standing so a hand-over that found no room can be
	; retried by talking to them - so the partner has to be marked beaten
	; instead, or the player could start a second battle with nothing left to
	; win. With both flags set, TalkToTrainer gives the survivor the
	; after-battle line, which is also the retry.
	SetEvent EVENT_BEAT_STAGE_EVENT_NPC_1
	SetEvent EVENT_BEAT_STAGE_EVENT_NPC_2
	ld a, TEXT_PROCEDURALCAVE1_STAGE_RECOVER
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
	ld a, TEXT_PROCEDURALCAVE1_BOSS_OFFER
	ldh [hTextID], a
	call DisplayTextID
	call DisableWaitingAfterTextDisplay
.runScripts
	call EnableAutoTextBoxDrawing
	ld hl, ProceduralCave1TrainerHeaders
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
	ld hl, PCStageNpc1Header
.haveTrainerHeaders
	ld de, ProceduralCave1_ScriptPointers
	ld a, [wProceduralCave1CurScript]
	call ExecuteCurMapScriptInTable
	ld [wProceduralCave1CurScript], a
	ret

ProceduralCave1_ScriptPointers:
	def_script_pointers
	dw_const CheckFightingMapTrainers,              SCRIPT_PROCEDURALCAVE1_DEFAULT
	dw_const DisplayEnemyTrainerTextAndStartBattle, SCRIPT_PROCEDURALCAVE1_START_BATTLE
	dw_const EndTrainerBattle,                      SCRIPT_PROCEDURALCAVE1_END_BATTLE

; The join offer itself. Shown via DisplayTextID so the text box / font are set
; up properly (raw PrintText from a map-script state left the tiles unloaded,
; which is what produced glitched graphics and no visible text).
ProceduralCave1BossOfferText:
	text_asm
	ld a, [wRoguePokemon1]
	ld [wNamedObjectIndex], a
	call GetMonName               ; fill wNameBuffer for the offer text
	ld hl, PCBossJoinText
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

PCBossJoinText:
	text_far _PCBossJoinText
	text_end

PCWildCalmedText:
	text_far _PCWildCalmedText
	text_end

PCSignText:
	text_asm
	; Read sign variant from SRAM (rolled at preload, stable for the whole cave).
	; Use call PrintText — ld hl/ret causes TX_START to pop the text stream
	; pointer as the tile cursor, so line 1 writes off-screen (invisible).
	; PrintText sets up its own tile cursor through the normal init path.
	ld a, RAMG_SRAM_ENABLE
	ld [rRAMG], a
	ld a, BMODE_ADVANCED
	ld [rBMODE], a
	xor a
	ld [rRAMB], a
	ld a, [sProcCaveSignVariant]
	ld b, a
	ld a, BMODE_SIMPLE
	ld [rBMODE], a
	ld [rRAMG], a
	ld a, b
	and a
	jr nz, .showBoss
	ld hl, PCSignItemsText
	jr .show
.showBoss
	ld hl, PCSignBossText
.show
	call PrintText
	ld hl, .signEnd    ; point NextTextCommand at TX_END for clean exit
	jp TextScriptEnd
.signEnd
	text_end

PCSignItemsText:
	text_far _PCSignItemsText
	text_end

; --- Phase 7 stage-event NPCs (object slots 6-7) -------------------------
; TEXT IS PER EVENT TYPE, dispatched through the two tables below. To give a
; trainer its own voice, edit only its string in text/StageEvents.asm; nothing
; here needs to change. The tables are indexed by wStageEvent's type field, so
; a row exists for all six types even though STAGE_EVENT_MAX_ROLLABLE
; currently stops Joy and Jenny from rolling.
;
; Both NPC object slots share one text handler per beat. For a pair (Jessie &
; James) that means talking to either one says the same thing, which is the
; right default - 7e can split them by testing hSpriteIndex if a pair ever
; wants two voices.

; Spoken once, standing in front of the player, before the vanish.
PCStageEventArrivalText:
	text_asm
	ld hl, PCStageEventArrivalTexts
	call PCStageEventPickText     ; hl = this event type's string
	call PrintText
	farcall StageEventPrintLootLine
	; Terminate the stream rather than returning hl: PrintText has already
	; done the printing, and TextScriptEnd closes the box cleanly. Same shape
	; as PCSignText above, whose header explains why `ld hl / ret` misprints.
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; Spoken when the player tracks them down at the hideout, by TalkToTrainer as
; the header's before/after/end battle text rather than by the object's own
; text entry. That is what lets one per-type dispatcher serve all three beats:
; TalkToTrainer picks which of the header's three pointers to print, and they
; all point here.
PCStageEventHideoutText:
	text_asm
	ld hl, PCStageEventHideoutTexts
	call PCStageEventPickText
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
; bc IS THE LIVE TILE CURSOR and PCStageEventPickText destroys it (it uses bc
; as the table offset). That is precisely the misprint the PCSignText header
; warns about - TX_START then places line 1 at a garbage coordinate, off
; screen. Saving bc across the call is what makes the `ld hl` / `ret` shape
; legal here; do not drop the push/pop.
;
; SHARED WITH THE CEMETERY. scripts/ProceduralCemetery1.asm points its own
; trainer headers at this label rather than carrying a second copy. Legal
; because maps.asm includes both files in the one "Maps 6" SECTION and a
; section cannot span banks, so they always share a bank. If the Cemetery is
; ever moved into a section of its own it needs its own copy back.
PCStageEventDefeatText::
	text_asm
	push bc
	ld hl, PCStageEventDefeatTexts
	call PCStageEventPickText
	pop bc
	ret

; Shown once after the villain is beaten. Dispatches on the STAGE_GIVEBACK_*
; result the script stashed, not on the event type: the player cares what came
; back, not who took it.
;
; THE DISPATCH AND THE STRINGS ARE IN BANK $3A (1C, 2026-09-22). All four
; stages used to carry a private copy of this handler, a private five-row
; pointer table and five private text_far wrappers, every one of them naming
; the same shared string - roughly 60 bytes per map for nothing but the
; duplication, in the bank that can least afford it. One farcall now.
PCStageEventRecoverText:
	text_asm
	farcall StageEventPrintRecoverLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; What a beaten stage-event NPC says when the player talks to them again (1C,
; 2026-09-22). Before 1C there was nothing to say - both NPCs were hidden the
; instant either was beaten - so every header's after-battle pointer went back
; to the hideout line. They stay on the map now, so this beat is reachable.
;
; THE BODY IS IN BANK $3A, not here, and deliberately so. "Maps 6" is bank 17,
; which is one of the tightest banks in the ROM (95 free bytes when the
; Cemetery's headers were written, and it has only shrunk); a dispatcher plus
; a five-row table plus five text_far wrappers does not fit in that, and the
; same argument is already why the Cemetery borrows this file's defeat
; dispatcher. StageEventPrintAfterLine is reached by farcall, so bank $3A is
; mapped while it runs and its own local text streams are what PrintText sees
; - exactly how StageEventPrintLootLine has always worked.
;
; SHARED WITH THE CEMETERY, whose headers point straight at this label.
PCStageEventAfterText::
	text_asm
	farcall StageEventPrintAfterLine
	ld hl, .done
	jp TextScriptEnd
.done
	text_end

; The two NPC objects' own text entries. Each hands TalkToTrainer its slot's
; header and nothing else - exactly the shape ProceduralCave1BossText uses, so
; there is one text box and one A press, not two. Which header matters: the
; flag bit inside it is what marks THAT slot beaten, and for a pair the player
; must be able to beat each independently.
PCStageEventNpc1Text:
	text_asm
	ld hl, PCStageNpc1Header
	jp ProceduralCaveInitBattleScript

PCStageEventNpc2Text:
	text_asm
	ld hl, PCStageNpc2Header
	jp ProceduralCaveInitBattleScript

; INPUT: hl = a six-entry table of text pointers, ordered by STAGE_EVENT_* type
;        starting at type 1.
; OUTPUT: hl = the entry for the currently armed event.
;
; bc is free to clobber here: both callers hand the result straight to
; PrintText and then terminate the stream with TextScriptEnd, so there is no
; live text cursor to preserve. A text_asm handler that RETURNS hl to continue
; the stream would have to push/pop bc (see ProceduralCave1BossText, which
; does exactly that).
PCStageEventPickText:
	ld a, [wStageEvent]
	and STAGE_EVENT_TYPE_MASK
	dec a                         ; type is 1-based; the table is 0-based
	add a, a                      ; two bytes per pointer
	ld c, a
	ld b, 0
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	ret

PCStageEventArrivalTexts:
	dw PCStageArrivalJessieJames  ; STAGE_EVENT_JESSIE_JAMES
	dw PCStageArrivalPsychic      ; STAGE_EVENT_PSYCHIC
	dw PCStageArrivalBurglar      ; STAGE_EVENT_BURGLAR
	dw PCStageArrivalJoy          ; STAGE_EVENT_JOY
	dw PCStageArrivalJenny        ; STAGE_EVENT_JENNY
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PCStageEventArrivalTexts needs a row per stage-event type"

PCStageEventHideoutTexts:
	dw PCStageHideoutJessieJames
	dw PCStageHideoutPsychic
	dw PCStageHideoutBurglar
	dw PCStageHideoutJoy
	dw PCStageHideoutJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PCStageEventHideoutTexts needs a row per stage-event type"

PCStageEventDefeatTexts:
	dw PCStageDefeatJessieJames
	dw PCStageDefeatPsychic
	dw PCStageDefeatBurglar
	dw PCStageDefeatJoy
	dw PCStageDefeatJenny
	ASSERT NUM_STAGE_EVENT_TYPES == 5, "PCStageEventDefeatTexts needs a row per stage-event type"

PCStageArrivalJessieJames:
	text_far _StageEventArrivalJessieJamesText
	text_end
PCStageArrivalPsychic:
	text_far _StageEventArrivalPsychicText
	text_end
PCStageArrivalBurglar:
	text_far _StageEventArrivalBurglarText
	text_end
PCStageArrivalJoy:
	text_far _StageEventArrivalJoyText
	text_end
PCStageArrivalJenny:
	text_far _StageEventArrivalJennyText
	text_end

PCStageHideoutJessieJames:
	text_far _StageEventHideoutJessieJamesText
	text_end
PCStageHideoutPsychic:
	text_far _StageEventHideoutPsychicText
	text_end
PCStageHideoutBurglar:
	text_far _StageEventHideoutBurglarText
	text_end
PCStageHideoutJoy:
	text_far _StageEventHideoutJoyText
	text_end
PCStageHideoutJenny:
	text_far _StageEventHideoutJennyText
	text_end

PCStageDefeatJessieJames:
	text_far _StageEventDefeatJessieJamesText
	text_end
PCStageDefeatPsychic:
	text_far _StageEventDefeatPsychicText
	text_end
PCStageDefeatBurglar:
	text_far _StageEventDefeatBurglarText
	text_end
PCStageDefeatJoy:
	text_far _StageEventDefeatJoyText
	text_end
PCStageDefeatJenny:
	text_far _StageEventDefeatJennyText
	text_end

; TalkToTrainer's before-battle text for both NPC slots (7e). Still one shared
; string; 7e gives it the same per-type table treatment as the two above.
PCStageNpcBattleText:
	text_far _PCStageNpcBattleText
	text_end

PCSignBossText:
	text_far _PCSignBossText
	text_end

ProceduralCave1_TextPointers:
	def_text_pointers
	; ORDER IS LOAD-BEARING, and not for the reason it looks. DisplayTextID
	; takes its .spriteHandling branch whenever hTextID <= wNumSprites, and
	; that branch REPLACES the id with wMapSpriteData[id-1] - the text id the
	; sprite in THAT SLOT declares. So any constant the map script fires whose
	; value is <= the object count silently prints a different entry.
	;
	; Phase 7 grew this map's object list past the low ids and broke exactly
	; that. MEASURED 2026-09-17, before the reorder below: BOSS_OFFER printed
	; the stage NPC's line and CALMED printed its partner's. The rule that
	; fixes it is simply that the first wNumSprites entries must be the
	; objects' own text, in slot order - then the indirection is the identity
	; and every later constant is out of its range. Keep any new entry AFTER
	; the object block.
    dw_const ProceduralCave1BossText, TEXT_PROCEDURALCAVE1_BOSS
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_1
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_2
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_3
	dw_const RandomPickUpItemText, TEXT_PROCEDURALCAVE1_WILD_AREA_POKEBALL_4
	dw_const PCStageEventNpc1Text, TEXT_PROCEDURALCAVE1_STAGE_NPC_1
	dw_const PCStageEventNpc2Text, TEXT_PROCEDURALCAVE1_STAGE_NPC_2
	; --- end of the object block (7 objects); script-only ids follow ---
	dw_const ProceduralCave1BossOfferText, TEXT_PROCEDURALCAVE1_BOSS_OFFER
	dw_const PCWildCalmedText, TEXT_PROCEDURALCAVE1_CALMED
	EXPORT TEXT_PROCEDURALCAVE1_CALMED ; used by engine/battle/wild_encounters.asm
	dw_const PCSignText, TEXT_PROCEDURALCAVE1_SIGN
	dw_const PCStageEventArrivalText, TEXT_PROCEDURALCAVE1_STAGE_EVENT
	dw_const PCStageEventRecoverText, TEXT_PROCEDURALCAVE1_STAGE_RECOVER
    ;dw_const PCBossEncounterText, TEXT_PROCEDURALCAVE1_BOSS_ENCOUNTER
    ;dw_const ProceduralCave1BossRoarText, TEXT_PROCEDURALCAVE1_BOSS_ROAR

ProceduralCave1TrainerHeaders:
PCBossTrainerHeader:
	; The boss is slot 1 and CheckForEngagingTrainers uses CURRENT_TRAINER_BIT
	; as the sprite slot, so its flag bit must be 1. EVENT_BEAT_PC_BOSS is
	; shared with the other procedural maps, so - exactly as
	; scripts/ProceduralFacility.asm does for its slots 6-9 - this established
	; slot-1 header is emitted directly rather than through `def_trainers 1`,
	; which lets the event-layout generator treat the slot-6/7 pair below as
	; its own byte-aligned trainer run instead of forcing it to share the
	; boss's.
	ASSERT EVENT_BEAT_PC_BOSS % 8 == 1
	db 1
	db 0
	dw wEventFlags + (EVENT_BEAT_PC_BOSS - 1) / 8
	dw ProceduralCave1BossBattleText, ProceduralCave1BossBattleText
	dw ProceduralCave1BossBattleText, ProceduralCave1BossBattleText
	; Slots 2-5 are pokeballs, so resume the trainer-bit sequence at object
	; slot 6, where the Phase 7 stage-event NPCs live.
	def_trainers 6
	; The second argument is the SIGHT-LINE ENGAGE DISTANCE, not padding:
	; CheckForEngagingTrainers reads header byte 1 into wTrainerEngageDistance
	; and hands it to TrainerEngage. 0 (as the boss uses) means talk-only.
	;
	; 4 here, so a stage-event NPC spots the player and walks up like any route
	; trainer. Safe for the villains despite them starting in the player's
	; face: the arrival text and the dark flash both run in .afterSetup, which
	; is earlier in the same script tick than .runScripts' CheckFightingMapTrainers,
	; so by the time sight lines are tested they are already at the hideout.
	;
	; Arg 5 is AFTER-BATTLE text, and it used to point back at the hideout
	; line because it was unreachable - both NPCs were hidden the moment
	; either was beaten. 1C leaves them standing, so it now points at the real
	; after-battle handler, which also carries the no-room retry.
PCStageNpc1Header:
	trainer EVENT_BEAT_STAGE_EVENT_NPC_1, 4, PCStageEventHideoutText, PCStageEventDefeatText, PCStageEventAfterText
PCStageNpc2Header:
	trainer EVENT_BEAT_STAGE_EVENT_NPC_2, 4, PCStageEventHideoutText, PCStageEventDefeatText, PCStageEventAfterText
	db -1 ; end

ProceduralCaveInitBattleScript:
	call TalkToTrainer
	ld a, [wCurMapScript]
	ld [wProceduralCave1CurScript], a
	jp TextScriptEnd

ProceduralCave1BossText:
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
	ld hl, PCBossTrainerHeader
	jr ProceduralCaveInitBattleScript

; TalkToTrainer shows this as its "before battle text".
; Shows "<NAME>!" → player presses A → cry plays → battle starts.
; wNameBuffer was filled by ProceduralCave1BossText before TalkToTrainer ran.
ProceduralCave1BossBattleText:
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
