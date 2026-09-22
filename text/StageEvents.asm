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
	text "Hold it right"
	line "there! Hand over"
	cont "that #MON!@"
	text_end

_StageEventArrivalPsychicText::
	text "I foresaw your"
	line "arrival... and"
	cont "your loss.@"
	text_end

_StageEventArrivalBurglarText::
	text "Nice bag! I'll"
	line "be taking"
	cont "something.@"
	text_end

_StageEventArrivalJoyText::
	text "Oh! A trainer"
	line "way out here?"
	cont "Let me help.@"
	text_end

_StageEventArrivalJennyText::
	text "This area isn't"
	line "safe. I'm on"
	cont "patrol here.@"
	text_end

; --- THE THEFT ITSELF: printed straight after the greeting ----------------
; Named rather than generic, which is why StageEventDoTheft now runs BEFORE
; the arrival text: the record has to exist before the line can read it.
; Shared across the villains by what was taken rather than by who took it,
; the same split the recovery lines already use.

; One per thief per kind: "They" only fits the pair, and each of the three
; has a different reason for taking it.

_StageEventTookMonJessieJamesText::
	text "They made off"
	line "with @"
	text_ram wNameBuffer
	text "!@"
	text_end

_StageEventTookMonPsychicText::
	text "@"
	text_ram wNameBuffer
	text " vanished"
	line "from your party!@"
	text_end

_StageEventTookMonBurglarText::
	text "He grabbed @"
	text_ram wNameBuffer
	text ""
	line "and bolted!@"
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
	line "floated away!@"
	text_end

_StageEventTookItemBurglarText::
	text "He pocketed"
	line "your @"
	text_ram wNameBuffer
	text "!@"
	text_end

; --- HIDEOUT: spoken when the player finds them again ---------------------

_StageEventHideoutJessieJamesText::
	text "You followed us"
	line "all the way out"
	cont "here?@"
	text_end

_StageEventHideoutPsychicText::
	text "Predictable. I"
	line "knew you would"
	cont "come.@"
	text_end

_StageEventHideoutBurglarText::
	text "Tch. You've got"
	line "a good nose,"
	cont "kid.@"
	text_end

_StageEventHideoutJoyText::
	text "Your #MON look"
	line "much better"
	cont "now!@"
	text_end

_StageEventHideoutJennyText::
	text "Stay safe out"
	line "here, trainer.@"
	text_end

; --- DEFEAT: spoken by the trainer the moment the player wins -------------
; Printed by PrintEndBattleText, which has ALREADY written "<CLASS>: " into
; the box from _TrainerNameText. Line 1 is therefore not empty when these
; start, and the first token has to fit whatever the name prefix leaves of the
; box's 18 columns:
;
;   "JESSIE/JAMES: " 14 used, 4 left    "NURSE JOY: " 11 used, 7 left
;   "PSYCHIC: "       9 used, 9 left    "OFC.JENNY: " 11 used, 7 left
;   "BURGLAR: "       9 used, 9 left
;
; That budget is the whole reason these are separate strings instead of the
; hideout lines reused: a hideout line opens on a full-width line 1 and would
; run off into the border. It is also the vanilla shape - look at
; _SSAnneBowSailor2EndBattleText, which opens with just "You're".
;
; Each ends `prompt`, not "@" + `text_end`. See the file header for why.

_StageEventDefeatJessieJamesText::
	text "No!"
	line "We're blasting"
	cont "off again!"
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
	text "My my!"
	line "You and your"
	cont "team are strong!"
	prompt

_StageEventDefeatJennyText::
	text "Whew!"
	line "You can handle"
	cont "yourself fine!"
	prompt

; --- RECOVERY: what the player is told after beating the villain ---------
; Picked by STAGE_GIVEBACK_* result, not by event type, because what matters
; here is what came back rather than who took it.

_StageEventRecoverMonText::
	text "You got @"
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
	text "They didn't get"
	line "away with"
	cont "anything!@"
	text_end

; Party full at recovery time - the player caught something in here after
; being robbed, so there is nowhere to put the mon back.
_StageEventRecoverNoRoomText::
	text "Your party is"
	line "full! There's no"
	cont "room for it!@"
	text_end
