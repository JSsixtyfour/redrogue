; pokeyellow's fix: the original name-prefix check (matching English "GRAVELER"
; or "SPECTRE", Haunter's early English name) breaks for any trade-received
; species whose name happens to start with the same letters - a live hazard
; here since TRADE_FOR_RANDOM can hand out any species, not just the ones in
; TradeMons. Check the actual received species instead.
InGameTrade_CheckForTradeEvo:
	ld a, [wInGameTradeReceiveMonSpecies]
	cp KADABRA
	jr z, .tradeEvo
	cp GRAVELER
	jr z, .tradeEvo
	cp MACHOKE
	jr z, .tradeEvo
	cp HAUNTER
	jr z, .tradeEvo
	ret
.tradeEvo
	ld a, [wPartyCount]
	dec a
	ldh [hWhichPokemon], a ; the mon just received is always the last party slot
	ld a, TRUE
	ld [wForceEvolution], a
	ld a, LINK_STATE_TRADING
	ld [wLinkState], a
	callfar TryEvolvingMon
	xor a ; LINK_STATE_NONE
	ld [wLinkState], a
	jp PlayDefaultMusic
