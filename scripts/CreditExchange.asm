CreditExchange_Script:
	jp EnableAutoTextBoxDrawing

CreditExchange_TextPointers:
	def_text_pointers
	dw_const CreditExchangeCooltrainerText, TEXT_CREDITEXCHANGE_COOLTRAINER
	dw_const CreditExchangeScientistText,    TEXT_CREDITEXCHANGE_SCIENTIST
	dw_const CreditExchangeVendorText,     TEXT_CREDITEXCHANGE_VENDOR_1
	dw_const CreditExchangeVendorText,     TEXT_CREDITEXCHANGE_VENDOR_2
	dw_const CreditExchangeVendorText,     TEXT_CREDITEXCHANGE_VENDOR_3
	; all three counters share one handler; CreditVendorMenu tells them apart by
	; hTextID, so these three must stay adjacent and in this order
	EXPORT TEXT_CREDITEXCHANGE_VENDOR_1 ; used by engine/events/credit_mart.asm

CreditExchangeCooltrainerText:
	text_far _CreditExchangeCooltrainerText
	text_end

CreditExchangeScientistText:
	text_far _CreditExchangeScientistText
	text_end

CreditExchangeVendorText:
	script_credit_vendor
