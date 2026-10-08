; Bag / mart item descriptions, drawn by PrintItemDescription
; (custom_functions/item_descriptions.asm). Two lines of at most 14 tiles;
; '#' prints as four (POKé). TMs/HMs are not listed: they show their move's
; type, PP, power and accuracy instead.
; Write each entry from the item's real effect in this ROM, not vanilla's.

ItemDescriptions:
	item_desc POTION,       "Restores 20 HP", "to one #MON"
	item_desc SUPER_POTION, "Restores 50 HP", "to one #MON"
	item_desc HYPER_POTION, "Restores 200HP", "to one #MON"
	db -1
