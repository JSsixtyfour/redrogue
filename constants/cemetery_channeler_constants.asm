; The Cemetery's possessed Channeler (custom_functions/cemetery_channeler.asm).

; His object slot on every floor map, named like object consts on purpose: the
; save converter finds a toggle's new-game default by TOGGLE_<object name>.
DEF CEMETERY_1_CHANNELER EQU 4
DEF CEMETERY_2_CHANNELER EQU 4
DEF CEMETERY_3_CHANNELER EQU 4
DEF CEMETERY_4_CHANNELER EQU 4

; sProcCemeteryItemGot (bits 0-3 are the floors' balls).
DEF CEM_CHANNELER_FLOOR_MASK EQU %00110000 ; his floor, 0-3
DEF BIT_CEM_CHANNELER_WON    EQU 6

; wSafariZoneGateCurScript while his battle is pending (the forest rest house
; uses 1, the subroom residents 2).
DEF SCRIPT_CHANNELER_AFTER_BATTLE EQU 3
