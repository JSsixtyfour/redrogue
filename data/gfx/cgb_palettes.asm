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

; palettes for overworlds, title screen, monsters
;gbcnote - add pokemon yellow GBC palettes
CGBPalettes:
	; PAL_ROUTE
	RGB 31, 31, 31
	RGB 16, 31,  4
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_PALLET
	RGB 31, 31, 31
	RGB 23, 17, 31
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_VIRIDIAN
	RGB 31, 31, 31
	RGB 19, 31,  0
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_PEWTER
	RGB 31, 31, 31
	RGB 18, 18, 15
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_CERULEAN
	RGB 31, 31, 31
	RGB  5,  8, 31
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_LAVENDER
	RGB 31, 31, 31
	RGB 25,  4, 31
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_VERMILION
	RGB 31, 31, 31
	RGB 31, 19,  0
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_CELADON
	RGB 31, 31, 31
	RGB  5, 31,  5
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_FUCHSIA
	RGB 31, 31, 31
	RGB 31, 15, 15
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_CINNABAR
	RGB 31, 31, 31
	RGB 31,  8,  8
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_INDIGO
	RGB 31, 31, 31
	RGB 11,  8, 31
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_SAFFRON
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_TOWNMAP
	RGB 31, 31, 31
	RGB  0, 21, 31
	RGB 10, 28,  0
	RGB  1,  1,  1

	; PAL_LOGO1
IF DEF(_BLUE)
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB 21,  0,  4	;unused on title screen
	RGB  3,  3, 23	;version subtitle text color
ENDC
IF DEF(_RED)
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB 17, 23, 10	;unused on title screen
	RGB 23,  3,  3	;version subtitle text color
ENDC
IF DEF(_GREEN)
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB 17, 23, 10	;unused on title screen
	RGB  3, 23,  3	;version subtitle text color
ENDC

	; PAL_LOGO2
IF (DEF(_RED) && DEF(_JPLOGO))
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB  3,  3, 23	;"pocket monsters" logo text color
	RGB 23,  3,  3	;japanese logo text color
ELIF (DEF(_GREEN) && DEF(_JPLOGO))
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB  3,  3, 23	;"pocket monsters" logo text color
	RGB  3, 23,  3	;japanese logo text color
ELIF (DEF(_BLUE) && DEF(_JPLOGO))
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;unused yellow logo text
	RGB 31,  15, 0	;"pocket monsters" logo text color
	RGB  3,  3, 23	;japanese logo text color
ELSE
	RGB 31, 31, 31	;white bg
	RGB 31, 31,  0	;yellow logo text
	RGB  7,  7, 25	;blue logo text shadow
	RGB  0,  0, 17	;blue logo text outline
ENDC
	; PAL_0F
	RGB 31, 31, 31
	RGB 13,  1, 31
	RGB  0,  9, 31
	RGB  1,  1,  1

	; PAL_MEWMON	;reworked to match red/blue tones 
	RGB 31, 31, 31
	RGB 30, 17,  11
	RGB 11,  5,  14
	RGB  3,  3,  3

	; PAL_BLUEMON
	RGB 31, 31, 31
	RGB 16, 18, 31
	RGB  0,  1, 25
	RGB  3,  3,  3

	; PAL_REDMON
	RGB 31, 31, 31
	RGB 31, 17,  0
	RGB 31,  0,  0
	RGB  3,  3,  3

	; PAL_CYANMON
	RGB 31, 31, 31
	RGB 16, 26, 31
	RGB  0, 17, 31
	RGB  3,  3,  3

	; PAL_PURPLEMON
	RGB 31, 31, 31
	RGB 25, 15, 31
	RGB 19,  0, 22
	RGB  3,  3,  3

	; PAL_BROWNMON
	RGB 31, 31, 31
	RGB 29, 18, 10
	RGB 17,  9,  5
	RGB  3,  3,  3

	; PAL_GREENMON
	RGB 31, 31, 31
	RGB 17, 31, 11
	RGB  1, 22,  6
	RGB  3,  3,  3

	; PAL_PINKMON
	RGB 31, 31, 31
	RGB 31, 15, 18
	RGB 31,  0,  6
	RGB  3,  3,  3

	; PAL_YELLOWMON
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB 28, 14,  0
	RGB  3,  3,  3

	; PAL_GREYMON
	RGB 31, 31, 31
IF DEF(_YSPRITES)	;Use Yellow's version of gray if using yellow sprites
	RGB 20, 23, 10
	RGB 11, 11,  5
ELSE				;Else use the converted R/B stye of gray
	RGB 21, 14, 16	
	RGB 10,  9, 12
ENDC
	RGB  3,  3,  3

;gbcnote - retouched all the slot palettes to match the red/blue coloring
	; PAL_SLOTS1
IF DEF(_GREEN)
	RGB 31, 31, 31	;reel background
	RGB 21, 12, 15	;reel accents
	RGB 16,  0,  0	;"7" fill color
	RGB  3,  3,  3	;reel outline
ELSE
	RGB 31, 31, 31	;reel background
	RGB 21, 12, 15	;reel accents
	RGB 21, 14,  0	;"7" fill color
	RGB  3,  3,  3	;reel outline
ENDC
	; PAL_SLOTS2
IF DEF(_RED)
	RGB 31, 31, 31	;"3" icon fill
	RGB 31, 31,  0	;"3" icon shape color
	RGB 20,  8, 15	;"3" icon background color
	RGB  3,  3,  3	;"3" icon outline
ENDC
IF DEF(_BLUE)
	RGB 31, 31, 31	;"3" icon fill
	RGB 31, 31,  0	;"3" icon shape color
	RGB  9,  5, 30	;"3" icon background color
	RGB  3,  3,  3	;"3" icon outline
ENDC
IF DEF(_GREEN)
	RGB 31, 31, 31	;"3" icon fill
	RGB 31, 31,  0	;"3" icon shape color
	RGB 12, 21,  7	;"3" icon background color
	RGB  3,  3,  3	;"3" icon outline
ENDC

	; PAL_SLOTS3
IF DEF(_RED)
	RGB 31, 31, 31	;"2" icon fill
	RGB  3, 31,  9	;"2" icon shape color
	RGB 20,  8, 15	;"2" icon background color
	RGB  3,  3,  3	;"2" icon outline
ENDC
IF DEF(_BLUE)
	RGB 31, 31, 31	;"2" icon fill
	RGB  3, 31,  9	;"2" icon shape color
	RGB  9,  5, 30	;"2" icon background color
	RGB  3,  3,  3	;"2" icon outline
ENDC
IF DEF(_GREEN)
	RGB 31, 31, 31	;"2" icon fill
	RGB 20,  8, 15	;"2" icon shape color
	RGB 12, 21,  7	;"2" icon background color
	RGB  3,  3,  3	;"2" icon outline
ENDC

	; PAL_SLOTS4
IF DEF(_RED)
	RGB 31, 31, 31	;"1" icon fill
	RGB  9,  5, 30	;"1" icon shape color
	RGB 20,  8, 15	;"1" icon background color
	RGB  3,  3,  3	;"1" icon outline
ENDC
IF DEF(_BLUE)
	RGB 31, 31, 31	;"1" icon fill
	RGB 20,  8, 15	;"1" icon shape color
	RGB  9,  5, 30	;"1" icon background color
	RGB  3,  3,  3	;"1" icon outline
ENDC
IF DEF(_GREEN)
	RGB 31, 31, 31	;"1" icon fill
	RGB  9,  5, 30	;"1" icon shape color
	RGB 12, 21,  7	;"1" icon background color
	RGB  3,  3,  3	;"1" icon outline
ENDC

	; PAL_BLACK
	RGB 31, 31, 31
	RGB  3,  3,  3
	RGB  3,  3,  3
	RGB  3,  3,  3

	; PAL_GREENBAR
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB  0, 31,  0
	RGB  3,  3,  3

	; PAL_YELLOWBAR
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB 31, 18,  0
	RGB  3,  3,  3

	; PAL_REDBAR
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB 31,  0,  0
	RGB  3,  3,  3

	; PAL_BADGE	
	;re-toned to a nice teal for the cascade and earth badges
	RGB 31, 31, 31
	RGB  3, 11,  6
	RGB  3, 17, 11
	RGB  3,  3,  3

	; PAL_CAVE
	RGB 31, 31, 31
	RGB 23,  8,  0
	RGB 17, 14, 11
	RGB  3,  3,  3

	; PAL_GAMEFREAK
	RGB 31, 31, 31
	RGB 31, 19,  0
	RGB 19, 19,  0
	RGB  3,  3,  3

	; PAL_25
	RGB 31, 31, 31
	RGB 31, 31,  0
	RGB 11, 23, 31
	RGB  3,  3,  3

	; PAL_BILLS_PC
	RGB 31, 31, 31
	RGB 31, 31, 31
	RGB 30, 22, 17
	RGB  3,  3,  3

	; PAL_27
	RGB 31, 31, 31
	RGB  9,  9,  9
	RGB 31, 21,  0
	RGB  3,  3,  3

	; PAL_BW	;joenote - adding a black & white palette just for GBC
	RGB 31, 31, 31
	RGB 31, 31, 31
	RGB  3,  3,  3
	RGB  3,  3,  3

	; PAL_UBALL	;joenote - adding a pal just for ultra balls on GBC
	RGB 31, 31, 31
	RGB 24, 24, 24
	RGB  8,  8,  8
	RGB  3,  3,  3
