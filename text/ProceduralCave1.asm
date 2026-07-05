_PCSignItemsText::
	text "Four items lie"
	line "hidden here.@"
	text_end

_PCSignBossText::
	text "A guardian"
	line "blocks your way.@"
	text_end



_PCBossEncounterText::
	text_ram wNameBuffer
	text "!@"
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
