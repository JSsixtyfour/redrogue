; Rarity-colored overworld Poke Balls, ENHANCED COLORS mode only. Edit this file
; to tune the balls when the Enhanced Colors option is ON. The non-enhanced rows
; live in data/gfx/ball_rarity_palettes.asm and are independent of these.
; INCLUDEd by custom_functions/ball_rarity.asm as BallRarityPalettes (bank $2C,
; read by BufferAllEnhancedColorsGBC.ReadMasterPals).
;
; EVERY colour here goes through GBCGamma (custom_functions/func_gamma.asm) before
; it reaches the screen: a colour-mixing matrix, then a gamma-2 lookup. That lifts
; saturation toward pastel, so write DARKER and MORE SATURATED values than the look
; you want, rebuild, and read the real result (probe_ball_rarity.py prints the
; Enhanced OBJ palette RAM, "[enh] OBJn ..."). A colour whose R, G and B are all <= 3
; skips the gamma entirely, which is why Ultra's top is exactly 3,3,3 (5,5,6
; measured 12,12,12, silver).
;
; Four rows of four colours (RGB, 0-31): white / top / fade step / outline.
; Rows 0-2 are OBJ palettes 1-3 (tier balls) and are read through rOBP0
; (3,1,0,0 in the overworld): pixel shade 2 (the ball's top) -> colour 1, shade 1
; -> colour 0, shade 3 -> colour 3. Colour 2 only shows in fade steps.
; Row 3 is OBJ palette 7, the STANDARD red ball, read through rOBP1 (3,2,0,0):
; the top is colour 2 here (not 1), colour 1 only shows in fade steps.
; Keep colour 0 (body) and colour 3 (outline) the same across rows unless you want
; those to change per tier.
; There must be exactly four rows: ball_rarity.asm ASSERTs the size.

	; Row 0, Great Ball (OBJ 1): blue top
	RGB 31, 31, 31
	RGB  2,  8, 31
	RGB  2,  5, 20
	RGB  3,  3,  3

	; Row 1, Ultra Ball (OBJ 2): near-black top, dark-gold outline
	RGB 31, 31, 31
	RGB  5,  5,  5
	RGB  2,  2,  2
	RGB  3,  3,  3

	; Row 2, Master Ball (OBJ 3): purple top
	RGB 31, 31, 31
	RGB 15,  6, 23
	RGB 10,  4, 12
	RGB  3,  3,  3

	; Row 3, standard Poke Ball (OBJ 7): red top (colour 2, via rOBP1)
	RGB 31, 31, 31
	RGB 22,  3,  3
	RGB 26,  4,  4
	RGB  3,  3,  3
