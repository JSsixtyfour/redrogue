; Victory Road door sign pieces, used through text_far by
; LobbyMiniBossVictoryRoadSign (scripts/IndigoPlateauLobby.asm). Their own
; section because both the lobby script's bank ($06) and the lobby text bank
; ($28) are full.
_LobbyVictoryRoadHeadingText::
	text "VICTORY ROAD"
	line "@"
	text_end

_LobbyVictoryRoadRivalText::
	text_start
	cont "RIVAL BATTLE@"
	text_end
