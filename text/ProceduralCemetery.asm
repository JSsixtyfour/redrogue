_ProceduralCemeteryCalmedText::
	text "The wild #MON"
	line "were calmed.@"
	text_end

; The Cemetery's resurrection NPC (custom_functions/cemetery_resurrector.asm).

_CemResNoSoulsText::
	text "I sense no lost"
	line "souls near you."
	done

_CemResWhichText::
	text "Whom shall I"
	line "return to you?"
	done

_CemResConfirmText::
	text_ram wNameBuffer
	text_start
	line "Lv.@"
	text_decimal wCurEnemyLevel, 1, 3
	text " for ¥@"
	text_bcd wPriceTemp, 3 | LEADING_ZEROES | LEFT_ALIGN
	text "?"
	done

_CemResBoxFullText::
	text "Your PC box is"
	line "full."
	done

_CemResReturnedText::
	text_ram wNameBuffer
	text_start
	line "has returned!"
	prompt

_CemResToBoxText::
	text "Your party is"
	line "full. It went to"
	cont "the PC."
	prompt

_CemResEffectLostText::
	text "Its special power"
	line "faded away."
	prompt

_CemResAfterText::
	text "The dead have"
	line "had their say."
	done

_CemResNoFaintedText::
	text "None of your"
	line "#MON have"
	cont "fainted."
	done

_CemResReviveAskText::
	text "Which #MON"
	line "shall I revive?"
	done

_CemResNotFaintedText::
	text "That one has not"
	line "fainted."
	done

_CemResReviveConfirmText::
	text "Revive @"
	text_ram wNameBuffer
	text_start
	line "for ¥@"
	text_bcd wPriceTemp, 3 | LEADING_ZEROES | LEFT_ALIGN
	text "?"
	done

_CemResRevivedText::
	text_ram wNameBuffer
	text_start
	line "is revitalized!"
	prompt
