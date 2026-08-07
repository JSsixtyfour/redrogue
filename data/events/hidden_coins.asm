MACRO hidden_coin
	db \1, \3, \2
ENDM

HiddenCoinCoords:
	table_width 3
	; map id, x, y
	assert_max_table_length MAX_HIDDEN_COINS
	db -1 ; end
