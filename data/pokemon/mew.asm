; Mew's pics and base data are not grouped with the other Pokémon
; because it was a last-minute addition "as a kind of prank".
; Shigeki Morimoto explained in an Iwata Asks interview:
; "We put Mew in right at the very end. The cartridge was really full and
; there wasn't room for much more on there. Then the debug features which
; weren't going to be included in the final version of the game were removed,
; creating a miniscule 300 bytes of free space. So we thought that we could
; slot Mew in there. What we did would be unthinkable nowadays!"
; https://iwataasks.nintendo.com/interviews/ds/pokemon/0/0/

; Mew's PICS still live here, but its base-stats row does NOT any more: it moved
; into BaseStats at its own dex position (Species Groups Phase 2), because the
; hole it left at dex 151 shifted every species added after it by one row. With
; BASE_PIC_BANK the row can name these pics from any bank, so nothing about this
; section had to move with it.
MewPicFront:: INCBIN "gfx/pokemon/front/mew.pic"
MewPicBack::  INCBIN "gfx/pokemon/back/mewb.pic"
