; Procedural stage-event dialogue (PROCEDURAL_WILD_AREA_PLAN.md Phase 7).
;
; ONE STRING PER TRAINER PER BEAT, on purpose. These are deliberately not
; shared between event types even where the placeholder wording currently
; matches, so that each trainer's voice can be written independently without
; touching any dispatch code. To give a trainer custom text, edit only its
; string below - the tables in scripts/ProceduralCave1.asm already point at
; them, indexed by STAGE_EVENT_* type.
;
; These live in their own section rather than in text/ProceduralCave1.asm
; because the same six events can occur on any of the four procedural wild
; areas, and only one wild area is ever live at a time. The Forest, Facility
; and Cemetery reuse these strings as they grow their own NPC slots.
;
; ⚠ No "@" before a `prompt`/`text_promptbutton`: "@" terminates the
; PlaceString run and PlaceNextChar returns the instant it sees one, so a
; prompt byte after it is never dispatched and the text does not wait.
;
; EVERY STRING HERE EXCEPT THE DEFEAT BLOCK ends "@" + `text_end` and leans on
; DisplayTextID's own after-text wait (AfterDisplayingTextID ->
; WaitForTextScrollButtonPress), the same shape _PCBossJoinText uses.
;
; THE DEFEAT BLOCK IS THE ONE EXCEPTION, and it has to be. It is the only
; stage-event text NOT fired through DisplayTextID - engine/battle/core.asm
; calls PrintEndBattleText directly - so there is no AfterDisplayingTextID to
; fall back on. Without its own `prompt` that box printed and returned, and
; the "got money for winning" box drew straight over it. Those strings end in
; `prompt`, exactly like every route trainer's _...EndBattleText.

; --- ARRIVAL: spoken once, standing in front of the player on map load ----

_StageEventArrivalJessieJamesText::
	text "Stop right there!"
	line "That #MON is"
	cont "Team Rocket's!"
    
	para "Don't come"
	line "looking for us"
	cont "because you won't"
	cont "like the result!@"
	text_promptbutton
	text_end

_StageEventArrivalPsychicText::
	text "Look into my"
	line "eyes..."

	para "Give... me..."
	line "the... # BALL@"
	text_promptbutton
	text_end

_StageEventArrivalBurglarText::
	text "Thanks! I'll be"
	line "taking that!"
    cont "Good luck finding"
	cont "me.@"
	text_promptbutton
	text_end

; --- THE THEFT ITSELF: printed straight after the greeting ----------------
; Named rather than generic, which is why StageEventDoTheft now runs BEFORE
; the arrival text: the record has to exist before the line can read it.
; Shared across the villains by what was taken rather than by who took it,
; the same split the recovery lines already use.

; One per thief per kind: "They" only fits the pair, and each of the three
; has a different reason for taking it.

_StageEventTookMonJessieJamesText::
	text "They stole"
	line "@"
	text_ram wNameBuffer
	text "!@"
	text_end

_StageEventTookMonPsychicText::
	text "@"
	text_ram wNameBuffer
	text " was"
	line "stolen from your"
	cont "party.@"
	text_end

_StageEventTookMonBurglarText::
	text "He stole"
	line "@"
	text_ram wNameBuffer
	text ""
	line "and fled!@"
	text_end

_StageEventTookItemJessieJamesText::
	text "They swiped"
	line "your @"
	text_ram wNameBuffer
	text "!@"
	text_end

_StageEventTookItemPsychicText::
	text "Your @"
	text_ram wNameBuffer
	text ""
	line "was taken!@"
	text_end

_StageEventTookItemBurglarText::
	text "He pocketed"
	line "your @"
	text_ram wNameBuffer
	text "!@"
	text_end

; --- HIDEOUT: spoken when the player finds them again ---------------------

; Good NPCs skip the arrival conversation. Keep the existing map-script
; references valid without restoring the removed greeting dialogue.
_StageEventArrivalJoyText::
_StageEventArrivalJennyText::
	text_end

_StageEventHideoutJessieJamesText::
	text "Alright twerp,"
	line "you asked for it!@"
	text_promptbutton
	text_end

_StageEventHideoutPsychicText::
	text "Ah, so you did"
	line "come. Just as I"
	cont "predicted.@"
	text_promptbutton
	text_end

_StageEventHideoutBurglarText::
	text "Tch. You caught"
	line "me.@"
	text_promptbutton
	text_end

_StageEventHideoutJoyText::
	text "Surprised to see"
	line "me out here?@"
	text_promptbutton
	text_end

_StageEventHideoutJennyText::
	text "Wait, who is"
	line "that? Stop!"
	cont "You're under"
	cont "arrest!@"
	text_promptbutton
	text_end

; --- DEFEAT: spoken by the trainer the moment the player wins -------------
; Printed by PrintEndBattleText, which has ALREADY written "<CLASS>: " into
; the box from _TrainerNameText. Line 1 is therefore not empty when these
; start, and the first token has to fit whatever the name prefix leaves of the
; box's 17-column contract:
;
;   "JESSIE/JAMES: " 14 used, 3 left    "NURSE JOY: " 11 used, 6 left
;   "PSYCHIC: "       9 used, 8 left    "OFC.JENNY: " 11 used, 6 left
;   "BURGLAR: "       9 used, 8 left
;
; That budget is the whole reason these are separate strings instead of the
; hideout lines reused: a hideout line opens on a full-width line 1 and would
; run off into the border. It is also the vanilla shape - look at
; _SSAnneBowSailor2EndBattleText, which opens with just "You're".
;
; Each ends `prompt`, not "@" + `text_end`. See the file header for why.

_StageEventDefeatJessieJamesText::
	text ""
	line "A brat beat us?"
	prompt

_StageEventDefeatPsychicText::
	text "Unseen!"
	line "My visions have"
	cont "failed me."
	prompt

_StageEventDefeatBurglarText::
	text "Tch!"
	line "Take your junk"
	cont "back, then."
	prompt

_StageEventDefeatJoyText::
	text "Wow!"
	line "Looks like I need"
	cont "to head back to"
	cont "the #MON"
	cont "center."
	prompt

_StageEventDefeatJennyText::
	text "Sorry!"
	line "I mistook you for"
	cont "the suspect."
	prompt

; --- AFTER BATTLE: spoken when the player talks to them again ------------
; These did not exist before 1C (2026-09-22), because there was nothing to
; say: both NPCs were hidden the instant either was beaten, so the headers'
; after-battle slot pointed harmlessly back at the hideout line. They stay on
; the map now, so this beat is reachable - and for a PAIR it is the ONLY thing
; the surviving partner can do, since beating either one ends the encounter.
;
; Printed through DisplayTextID like the hideout lines, not by
; PrintEndBattleText, so there is no "<CLASS>: " prefix eating line 1 and no
; need for a trailing `prompt` - AfterDisplayingTextID waits.

_StageEventAfterJessieJamesText::
	text "JESSE: We'll get"
	line "you next time,"
	cont "twerp!@"
	text_end

_StageEventAfterPsychicText::
	text "I should have"
	line "seen this coming.@"
	text_end

_StageEventAfterBurglarText::
	text "Quit asking for"
	line "trouble and go,"
	cont "kid.@"
	text_end

_StageEventAfterJoyText::
	text "I'll see you"
	line "again soon!@"
	text_end

_StageEventAfterJennyText::
	text "Be vigilant!"
	line "Thieves have been"
	cont "reported here.@"
	text_end

; --- RECOVERY: what the player is told after beating the villain ---------
; Picked by STAGE_GIVEBACK_* result, not by event type, because what matters
; here is what came back rather than who took it.

_StageEventRecoverMonText::
	text "You got"
	line "@"
	text_ram wNameBuffer
	text " back!@"
	text_end

_StageEventRecoverItemText::
	text "You got your"
	line "@"
	text_ram wNameBuffer
	text " back!@"
	text_end

; The villain's guards refused the theft, so there was never anything to win
; back. Reached when the player had one mon and an empty bag.
_StageEventRecoverNothingText::
	text "They didn't steal"
	line "anything.@"
	text_end

; Party full at recovery time - the player caught something in here after
; being robbed - but the current box had space, so the mon is safe.
; Party full at recovery time, but the box had space. The authored line always
; names BILL's PC; the former EVENT_MET_BILL/"someone's PC" split was retired.
;
; The one deliberate difference is the name source. The capture path reads
; `text_ram wBoxMonNicks` because SendNewMonToBox FRONT-INSERTS, so the new mon
; is box slot 0. The give-back APPENDS at wBoxCount, so slot 0 is somebody
; else; wNameBuffer, filled by StageEventNameLoot, is the right source here.
;
; Ends `prompt`, not "@": StageEventPrintRecoverLine
; may print the box-full reminder straight afterwards, and PrintText redraws
; the box, so without a wait the second line would erase this one unread.
_StageEventRecoverToBoxBillText::
	text_ram wNameBuffer
	text " was"
	line "transferred to"
	cont "BILL's PC!"
	prompt

; Party AND box both full, or the bag pocket full for a stolen item. The only
; outcome that does not end the event: the villain stays put and the record
; stays live, so the player can make space and talk to them again.
_StageEventRecoverNoRoomText::
	text "You don't have"
	line "room for it so"
	cont "get lost!@"
	text_end
