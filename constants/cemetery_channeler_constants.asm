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
DEF BIT_CEM_RESURRECTOR_DONE EQU 7 ; served this Cemetery (cemetery_resurrector.asm)

; wSafariZoneGateCurScript while his battle is pending (the forest rest house
; uses 1, the subroom residents 2).
DEF SCRIPT_CHANNELER_AFTER_BATTLE EQU 3

; The resurrection NPC: object 5 on every floor map (custom_functions/
; cemetery_resurrector.asm). Shown by picture on his floor, parked off-grid with
; picture 0 elsewhere, like the Forest's optional slot: no toggle.
DEF CEMETERY_RESURRECTOR EQU 5
