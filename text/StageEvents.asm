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
; prompt byte after it is never dispatched and the text does not wait. These
; all end "@" + `text_end` and rely on DisplayTextID's own after-text wait,
; the same shape _PCBossJoinText uses.

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

_StageEventArrivalBothGoodText::
	text "We came out to"
	line "look for lost"
	cont "trainers!@"
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

_StageEventHideoutBothGoodText::
	text "Take care! We'll"
	line "be nearby if"
	cont "you need us.@"
	text_end

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
