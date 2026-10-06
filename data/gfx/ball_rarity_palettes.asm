; Rarity-colored overworld Poke Balls: the ONE definition of the three tinted
; ball palettes, INCLUDEd twice so each colour path reads it from its own bank:
;   - data/gfx/cgb_palettes.asm, as rows PAL_BALL_GREAT/ULTRA/MASTER, for the
;     non-enhanced CGB path (SetPal_Overworld puts them in slots 1-3).
;   - custom_functions/ball_rarity.asm, as BallRarityPalettes, for the Enhanced
;     Colors path (BufferAllEnhancedColorsGBC.ReadMasterPals, gamma applied).
; No label in here: each includer puts its own label in front.
;
; How the ball sprite uses a row (gfx/sprites/poke_ball.png through the
; overworld rOBP0 = 3,1,0,0 from FadePal4): pixel shade 3 (outline) -> colour 3,
; shade 2 (top half) -> colour 1, shade 1 (bottom half and the top highlight) ->
; colour 0. So colour 1 IS the ball's top, colours 0 and 3 keep the ordinary
; white body and dark outline, and colour 2 only appears during fade steps
; (FadePal3 maps shade 2 -> colour 2), so it is a darker step of the top.

	; Great Ball: blue top
	RGB 31, 31, 31
	RGB  8, 14, 31
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
	RGB  3,  3,  3
	RGB  2,  2,  2
	RGB 15, 12,  0

	; Master Ball: purple top
	RGB 31, 31, 31
	RGB 20,  6, 26
	RGB 11,  2, 15
	RGB  3,  3,  3
