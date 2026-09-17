_PCSignItemsText::
	text "Four items lie"
	line "hidden here.@"
	text_end

_PCSignBossText::
	text "A guardian"
	line "blocks your way.@"
	text_end

_PFSignItemsText::
	text "The trees whisper"
	line "of danger ahead...@"
	text_end

_PFSignBossText::
	text "A guardian"
	line "blocks your way.@"
	text_end

_PFacSignItemsText::
	text "Four items lie"
	line "hidden here.@"
	text_end

_PFacSignBossText::
	text "A guardian"
	line "blocks your way.@"
	text_end



_PCBossEncounterText::
	text_ram wNameBuffer
	text "!@"
	text_end

; Follower interaction mirrors the procedural boss encounter's dynamic-name
; stream, with an explicit prompt before the assembly-only cry step.
_FollowerPokemonInteractionText::
	text_ram wNameBuffer
	text "!@"
	text_promptbutton
	text_end

; Post-battle join offer. Structure mirrors the working BluesHouse pattern:
; a normal string that ends with "@" (returns to command mode), then
; text_ram to drop in the boss's name, then more string, then text_end.
; NOTE: never put "@" right before a line/cont - "@" returns to command
; mode and the <LINE>/<CONT> control byte would be misread as a command.
_PCWildCalmedText::
	text "The wild #MON"
	line "were calmed.@"
	text_promptbutton
	text_end

_PCBossJoinText::
	text "The wild"
	line "@"
	text_ram wNameBuffer
	text " wants"
	cont "to join your"
	cont "party!@"
	text_end

; --- Phase 7 stage events ------------------------------------------------
; Placeholder encounter line for the stage-event NPCs in object slots 6-7.
; 7c replaces this with the real appear/speak/vanish script and 7d with the
; theft; until then the NPC is interactable so the placement itself can be
; tested in the emulator.
_PCStageNpcText::
	text "Hey! Nice"
	line "#MON you've"
	cont "got there...@"
	text_end

; What TalkToTrainer shows before the recovery battle (7e).
_PCStageNpcBattleText::
	text "You want it"
	line "back? Take it"
	cont "from me!@"
	text_promptbutton
	text_end
