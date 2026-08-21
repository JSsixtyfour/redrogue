; CGB-tuned background/object palette values, one 4-colour entry per PAL_*
; constant (see constants/palette_constants.asm), in that constant's order.
;
; Ported from shinpokered's GBCBasePalettes (data/gbc_palettes.asm). This
; table exists separately from SuperPalettes (data/sgb/sgb_palettes.asm)
; because those values were tuned for Super Game Boy display hardware and
; read badly when fed straight to Game Boy Color palette hardware; this
; table is tuned for CGB instead.
;
; Entry order is load-bearing: InitCGBPalettes indexes this table as
; PAL_ID * 8 (2 bytes per colour * 4 colours), so nothing may be
; reordered, inserted, or removed without updating every caller.
;
; Porting notes:
; - shinpokered spells this palette PAL_GREYMON; this project spells it
;   PAL_GRAYMON. Same palette, values carried over unchanged.
; - shinpokered's PAL_GREYMON/PAL_GRAYMON has an IF DEF(_YSPRITES) branch
;   (Yellow's sprite-matched gray) and an ELSE branch (the converted R/B
;   style of gray). This project never defines _YSPRITES (see Makefile),
;   so the ELSE branch is used here, unconditionally.
; - shinpokered's PAL_SLOTS1 has an IF DEF(_GREEN) branch and an ELSE
;   branch; this project never defines _GREEN, so the ELSE branch is used
;   here, unconditionally (this matches how PAL_SLOTS1 is already a single
;   unconditional entry in data/sgb/sgb_palettes.asm).
; - shinpokered's PAL_LOGO1 has separate IF DEF(_BLUE) / IF DEF(_RED) / IF
;   DEF(_GREEN) branches. This project only ever builds _RED or _BLUE (see
;   Makefile), so the _GREEN branch is dropped and the _RED/_BLUE branches
;   are kept, mirroring the IF DEF(_RED) / IF DEF(_BLUE) shape already used
;   for PAL_LOGO1 in data/sgb/sgb_palettes.asm.
; - shinpokered's PAL_LOGO2 branches on IF DEF(_RED)+_JPLOGO / _GREEN+
;   _JPLOGO / _BLUE+_JPLOGO / ELSE (non-JP logo). This project never
;   defines _JPLOGO, so the ELSE (non-JP) branch always applies regardless
;   of _RED/_BLUE, matching how PAL_LOGO2 is already a single unconditional
;   entry (not split on _RED/_BLUE) in data/sgb/sgb_palettes.asm.
; - shinpokered's PAL_SLOTS2/PAL_SLOTS3/PAL_SLOTS4 each branch on IF DEF
;   (_RED) / IF DEF(_BLUE) / IF DEF(_GREEN). The _GREEN branch is dropped
;   for the same reason as PAL_LOGO1; the _RED/_BLUE branches are kept,
;   mirroring the existing IF DEF(_RED) / IF DEF(_BLUE) shape already used
;   for PAL_SLOTS2-4 in data/sgb/sgb_palettes.asm.
; - Every one of this project's 37 PAL_* constants (PAL_ROUTE through
;   PAL_GAMEFREAK) had a directly-named counterpart in shinpokered's table,
;   so no SuperPalettes fallback values were needed anywhere in this file.

CGBPalettes::
	table_width 2 * 4
	RGB 31,31,31, 16,31,04, 11,23,31, 03,03,03 ; PAL_ROUTE
	RGB 31,31,31, 23,17,31, 11,23,31, 03,03,03 ; PAL_PALLET
	RGB 31,31,31, 19,31,00, 11,23,31, 03,03,03 ; PAL_VIRIDIAN
	RGB 31,31,31, 18,18,15, 11,23,31, 03,03,03 ; PAL_PEWTER
	RGB 31,31,31, 05,08,31, 11,23,31, 03,03,03 ; PAL_CERULEAN
	RGB 31,31,31, 25,04,31, 11,23,31, 03,03,03 ; PAL_LAVENDER
	RGB 31,31,31, 31,19,00, 11,23,31, 03,03,03 ; PAL_VERMILION
	RGB 31,31,31, 05,31,05, 11,23,31, 03,03,03 ; PAL_CELADON
	RGB 31,31,31, 31,15,15, 11,23,31, 03,03,03 ; PAL_FUCHSIA
	RGB 31,31,31, 31,08,08, 11,23,31, 03,03,03 ; PAL_CINNABAR
	RGB 31,31,31, 11,08,31, 11,23,31, 03,03,03 ; PAL_INDIGO
	RGB 31,31,31, 31,31,00, 11,23,31, 03,03,03 ; PAL_SAFFRON
	RGB 31,31,31, 00,21,31, 10,28,00, 01,01,01 ; PAL_TOWNMAP
IF DEF(_RED)
	RGB 31,31,31, 31,31,00, 17,23,10, 23,03,03 ; PAL_LOGO1
ENDC
IF DEF(_BLUE)
	RGB 31,31,31, 31,31,00, 21,00,04, 03,03,23 ; PAL_LOGO1
ENDC
	RGB 31,31,31, 31,31,00, 07,07,25, 00,00,17 ; PAL_LOGO2
	RGB 31,31,31, 13,01,31, 00,09,31, 01,01,01 ; PAL_0F
	RGB 31,31,31, 30,17,11, 11,05,14, 03,03,03 ; PAL_MEWMON
	RGB 31,31,31, 16,18,31, 00,01,25, 03,03,03 ; PAL_BLUEMON
	RGB 31,31,31, 31,17,00, 31,00,00, 03,03,03 ; PAL_REDMON
	RGB 31,31,31, 16,26,31, 00,17,31, 03,03,03 ; PAL_CYANMON
	RGB 31,31,31, 25,15,31, 19,00,22, 03,03,03 ; PAL_PURPLEMON
	RGB 31,31,31, 29,18,10, 17,09,05, 03,03,03 ; PAL_BROWNMON
	RGB 31,31,31, 17,31,11, 01,22,06, 03,03,03 ; PAL_GREENMON
	RGB 31,31,31, 31,15,18, 31,00,06, 03,03,03 ; PAL_PINKMON
	RGB 31,31,31, 31,31,00, 28,14,00, 03,03,03 ; PAL_YELLOWMON
	RGB 31,31,31, 21,14,16, 10,09,12, 03,03,03 ; PAL_GRAYMON
	RGB 31,31,31, 21,12,15, 21,14,00, 03,03,03 ; PAL_SLOTS1
IF DEF(_RED)
	RGB 31,31,31, 31,31,00, 20,08,15, 03,03,03 ; PAL_SLOTS2
ENDC
IF DEF(_BLUE)
	RGB 31,31,31, 31,31,00, 09,05,30, 03,03,03 ; PAL_SLOTS2
ENDC
IF DEF(_RED)
	RGB 31,31,31, 03,31,09, 20,08,15, 03,03,03 ; PAL_SLOTS3
ENDC
IF DEF(_BLUE)
	RGB 31,31,31, 03,31,09, 09,05,30, 03,03,03 ; PAL_SLOTS3
ENDC
IF DEF(_RED)
	RGB 31,31,31, 09,05,30, 20,08,15, 03,03,03 ; PAL_SLOTS4
ENDC
IF DEF(_BLUE)
	RGB 31,31,31, 20,08,15, 09,05,30, 03,03,03 ; PAL_SLOTS4
ENDC
	RGB 31,31,31, 03,03,03, 03,03,03, 03,03,03 ; PAL_BLACK
	RGB 31,31,31, 31,31,00, 00,31,00, 03,03,03 ; PAL_GREENBAR
	RGB 31,31,31, 31,31,00, 31,18,00, 03,03,03 ; PAL_YELLOWBAR
	RGB 31,31,31, 31,31,00, 31,00,00, 03,03,03 ; PAL_REDBAR
	RGB 31,31,31, 03,11,06, 03,17,11, 03,03,03 ; PAL_BADGE
	RGB 31,31,31, 23,08,00, 17,14,11, 03,03,03 ; PAL_CAVE
	RGB 31,31,31, 31,19,00, 19,19,00, 03,03,03 ; PAL_GAMEFREAK
	assert_table_length NUM_SGB_PALS
