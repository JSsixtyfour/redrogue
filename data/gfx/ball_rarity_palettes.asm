; Rarity-colored overworld Poke Balls, NON-ENHANCED CGB mode only: the three
; tinted ball palettes, INCLUDEd by data/gfx/cgb_palettes.asm as rows
; PAL_BALL_GREAT/ULTRA/MASTER (SetPal_Overworld puts them in slots 1-3). No gamma
; applies in this mode, so what you write is what you see.
; ENHANCED COLORS mode has its OWN rows in data/gfx/ball_rarity_palettes_enhanced.asm
; (gamma-lifted, and with a separate standard-ball row); edit that file for it.
; No label in here: the includer puts its own label in front.
;
; How the ball sprite uses a row (gfx/sprites/poke_ball.png through the
; overworld rOBP0 = 3,1,0,0 from FadePal4): pixel shade 3 (outline) -> colour 3,
; shade 2 (top half) -> colour 1, shade 1 (bottom half and the top highlight) ->
; colour 0. So colour 1 IS the ball's top, colours 0 and 3 keep the ordinary
; white body and dark outline, and colour 2 only appears during fade steps
; (FadePal3 maps shade 2 -> colour 2), so it is a darker step of the top.
;
; The STANDARD (untiered) ball is red and shares the Master row. OBJ palettes
; 4-7 are the same base palettes read through rOBP1 (3,2,0,0 in the overworld),
; which sends the ball's top (shade 2) to colour 2 instead of 1. So OAM palette
; 7 = this Master row seen through OBP1: top = colour 2 = red, body and outline
; unchanged. This mode therefore needs no extra palette slot: PAL_BALL_MASTER in
; packet slot 3 feeds both OBJ 3 and OBJ 7 (InitCGBPalettes builds both).
; Side effect: the Master ball flashes red for a few frames in fade steps, where
; the overworld fade shows colour 2. Keep colour 2 a hue close to colour 1 if
; that bothers you.

	; Great Ball: blue top
	RGB 31, 31, 31
	RGB  2,  8, 31
	RGB  2,  5, 20
	RGB  3,  3,  3

	; Ultra Ball: near-black top. The outline is a dark gold rather than black
	; so the top still reads as a shape against its own outline (the user's
	; contrast acceptance item); tune this row if it reads poorly in BGB.
	; The top is exactly 3,3,3 because Enhanced Colors' gamma (GBCGamma,
	; custom_functions/func_gamma.asm) skips only colours with EVERY channel <= 3
	; and lifts anything else hard: 5,5,6 measured 12,12,12 and 3,3,4 measured
	; 10,10,10 in OBJ palette RAM, silver rather than black.
	RGB 31, 31, 31
	RGB  5,  5,  5
	RGB  2,  2,  2
	RGB  3,  3,  3

	; Master Ball: purple top (colour 1). Colour 2 is the STANDARD ball's red top.
	RGB 31, 31, 31
	RGB 15,  6, 23
	RGB 10,  4, 12
	RGB  3,  3,  3
