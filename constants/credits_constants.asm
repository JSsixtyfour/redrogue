; CreditsTextPointers indexes (see data/credits/credits_text.asm)
	const_def
	const CRED_VERSION        ; $00
	const CRED_TAJIRI         ; $01
	const CRED_TA_OOTA        ; $02
	const CRED_MORIMOTO       ; $03
	const CRED_WATANABE       ; $04
	const CRED_MASUDE         ; $05
	const CRED_NISINO         ; $06
	const CRED_SUGIMORI       ; $07
	const CRED_NISHIDA        ; $08
	const CRED_MIYAMOTO       ; $09
	const CRED_KAWAGUCHI      ; $0A
	const CRED_ISHIHARA       ; $0B
	const CRED_YAMAUCHI       ; $0C
	const CRED_ZINNAI         ; $0D
	const CRED_HISHIDA        ; $0E
	const CRED_SAKAI          ; $0F
	const CRED_YAMAGUCHI      ; $10
	const CRED_YAMAMOTO       ; $11
	const CRED_TANIGUCHI      ; $12
	const CRED_NONOMURA       ; $13
	const CRED_FUZIWARA       ; $14
	const CRED_MATSUSIMA      ; $15
	const CRED_TOMISAWA       ; $16
	const CRED_KAWAMOTO       ; $17
	const CRED_KAKEI          ; $18
	const CRED_TSUCHIYA       ; $19
	const CRED_TA_NAKAMURA    ; $1A
	const CRED_YUDA           ; $1B
	const CRED_MON            ; $1C
	const CRED_DIRECTOR       ; $1D
	const CRED_PROGRAMMERS    ; $1E
	const CRED_CHAR_DESIGN    ; $1F
	const CRED_MUSIC          ; $20
	const CRED_SOUND_EFFECTS  ; $21
	const CRED_GAME_DESIGN    ; $22
	const CRED_MONSTER_DESIGN ; $23
	const CRED_GAME_SCENE     ; $24
	const CRED_PARAM          ; $25
	const CRED_MAP            ; $26
	const CRED_TEST           ; $27
	const CRED_SPECIAL        ; $28
	const CRED_PRODUCERS      ; $29
	const CRED_PRODUCER       ; $2A
	const CRED_EXECUTIVE      ; $2B
	const CRED_TAMADA         ; $2C
	const CRED_SA_OOTA        ; $2D
	const CRED_YOSHIKAWA      ; $2E
	const CRED_TO_OOTA        ; $2F
	const CRED_US_STAFF       ; $30
	const CRED_US_COORD       ; $31
	const CRED_TILDEN         ; $32
	const CRED_KAWAKAMI       ; $33
	const CRED_HI_NAKAMURA    ; $34
	const CRED_GIESE          ; $35
	const CRED_OSBORNE        ; $36
	const CRED_TRANS          ; $37
	const CRED_OGASAWARA      ; $38
	const CRED_IWATA          ; $39
	const CRED_IZUSHI         ; $3A
	const CRED_HARADA         ; $3B
	const CRED_MURAKAWA       ; $3C
	const CRED_FUKUI          ; $3D
	const CRED_CLUB           ; $3E
	const CRED_PAAD           ; $3F
; Red Rogue sections (rolled before the vanilla staff, see credits_order.asm)
	const CRED_RR_TITLE       ; $40
	const CRED_RR_BY          ; $41
	const CRED_RR_JSSIXTYFOUR ; $42
	const CRED_RR_THANKS      ; $43
	const CRED_RR_THANKS_2    ; $44
	const CRED_RR_BASE        ; $45
	const CRED_RR_PRET        ; $46
	const CRED_RR_POKERED     ; $47
	const CRED_RR_CONTRIBS    ; $48
	const CRED_RR_PORTED      ; $49
	const CRED_RR_PORTED_2    ; $4A
	const CRED_RR_SHINRED     ; $4B
	const CRED_RR_JOJOBEAR    ; $4C
	const CRED_RR_YLEGACY     ; $4D
	const CRED_RR_CRZSHADOWS  ; $4E
	const CRED_RR_PURERGB     ; $4F
	const CRED_RR_VORTYNE     ; $50
	const CRED_RR_YUME        ; $51
	const CRED_RR_POKEFANMARC ; $52
	const CRED_RR_EXYELLOW    ; $53
	const CRED_RR_RAINBOWMP   ; $54
	const CRED_RR_KEP         ; $55
	const CRED_RR_MEMENTO     ; $56
	const CRED_RR_REDPP       ; $57
	const CRED_RR_LUNA        ; $58
	const CRED_RR_POLISHED    ; $59
	const CRED_RR_RANGI       ; $5A
	const CRED_RR_ART         ; $5B
	const CRED_RR_SKIDMARC    ; $5C
	const CRED_RR_YL_ART      ; $5D
	const CRED_RR_ZUPERZACH   ; $5E
	const CRED_RR_KARLOS      ; $5F
	const CRED_RR_ALGORITHMS  ; $60
	const CRED_RR_RAK         ; $61
	const CRED_RR_SAUKAS      ; $62
	const CRED_RR_ALBRECHT    ; $63
	const CRED_RR_CODE        ; $64
	const CRED_RR_MATEO       ; $65
	const CRED_RR_XILLICIS    ; $66
	const CRED_RR_YAKINEEN    ; $67
	const CRED_RR_TUTORIALS   ; $68
	const CRED_RR_PRET_WIKI   ; $69
	const CRED_RR_AUTHORS     ; $6A
	const CRED_RR_RESEARCH    ; $6B
	const CRED_RR_SMOGON      ; $6C
	const CRED_RR_PMARIGLIA   ; $6D
	const CRED_RR_GENERICMAD  ; $6E
	const CRED_RR_EMERALD     ; $6F
	const CRED_RR_EXPANSION   ; $70
	const CRED_RR_TOOLS       ; $71
	const CRED_RR_RGBDS       ; $72
	const CRED_RR_BGB         ; $73
	const CRED_RR_PYBOY       ; $74
DEF NUM_CRED_STRINGS EQU const_value

	const_def -1, -1
	const CRED_TEXT_FADE_MON ; $FF
	const CRED_TEXT_MON      ; $FE
	const CRED_TEXT_FADE     ; $FD
	const CRED_TEXT          ; $FC
	const CRED_COPYRIGHT     ; $FB
	const CRED_THE_END       ; $FA

; string ids share CreditsOrder's byte space with the commands above
	assert NUM_CRED_STRINGS <= LOW(CRED_THE_END), "too many credits strings"

; wCreditsFlags bits (engine/movie/credits.asm)
DEF BIT_CREDITS_SKIP        EQU 0 ; START pressed: jump to THE END
DEF BIT_CREDITS_START_ARMED EQU 1 ; START seen released since the roll began
DEF BIT_CREDITS_FAST        EQU 2 ; SELECT toggled 4x speed on
DEF BIT_CREDITS_SELECT_HELD EQU 3 ; SELECT was down last frame (edge detect)
DEF CREDITS_FAST_STEP       EQU 4 ; frames counted per real frame while fast
