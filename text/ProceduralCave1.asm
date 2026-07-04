_PCBossEncounterText::
	text_ram wNameBuffer
	text "!@"
	text_end

; Post-battle join offer. Structure mirrors the working BluesHouse pattern:
; a normal string that ends with "@" (returns to command mode), then
; text_ram to drop in the boss's name, then more string, then text_end.
; NOTE: never put "@" right before a line/cont - "@" returns to command
; mode and the <LINE>/<CONT> control byte would be misread as a command.
_PCBossJoinText::
	text "The wild"
	line "@"
	text_ram wNameBuffer
	text " wants"
	cont "to join your"
	cont "party!@"
	text_end
