_PCBossEncounterText::
	text_ram wNameBuffer
	text "!@"
	;text_promptbutton   ; show ▼ arrow, wait for A/B so the name isn't a blip
	text_end

_PCBossJoinText::
	text_start
	text_ram wNameBuffer
	line "@"
_PCBossJoinText2::
	text "wants to join your"
	line "party!@"
	text_end
