; Far calls to another bank

; There is no difference between `farcall` and `callfar`, except the arbitrary
; order in which they set `b` and `hl` before calling `FarCall`.
; We use the more natural name "farcall" for the more common order.
; The same goes for `farjp` and `jpfar`.

MACRO farcall
	ld b, BANK(\1)
	ld hl, \1
	call Bankswitch
ENDM

MACRO callfar
	ld hl, \1
	ld b, BANK(\1)
	call Bankswitch
ENDM

MACRO farjp
	ld b, BANK(\1)
	ld hl, \1
	jp Bankswitch
ENDM

MACRO jpfar
	ld hl, \1
	ld b, BANK(\1)
	jp Bankswitch
ENDM

; Compact far call/jump through the rst vectors in home/header.asm: 4 bytes
; per site instead of 8, identical register contract (it ends in Bankswitch).
; Costs ~70 extra cycles per call, so keep plain `farcall` on per-frame paths
; (VBlank, audio) and in hot loops. Used where ROM space is tight, e.g. HOME.
DEF RST_FARCALL EQU $08
DEF RST_FARJUMP EQU $18

MACRO rfarcall
	rst RST_FARCALL
	dba \1
ENDM

MACRO rfarjp
	rst RST_FARJUMP
	dba \1
ENDM

MACRO homecall
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(\1)
	call SetCurBank
	call \1
	pop af
	call SetCurBank
ENDM

MACRO homecall_sf ; homecall but save flags by popping into bc instead of af
	ldh a, [hLoadedROMBank]
	push af
	ld a, BANK(\1)
	call SetCurBank
	call \1
	pop bc
	ld a, b
	call SetCurBank
ENDM

MACRO callbs	;joenote - added from pokeyellow
	ld a, BANK(\1)
	call BankswitchCommon
	call \1
	ENDM
