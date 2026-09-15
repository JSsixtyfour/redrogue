; Per-FORM level-up learnsets.
;
; A form is (base species, 2-bit form index) living in MON_CATCH_RATE bits 5-6,
; not a species of its own, so it has no slot in EvosMovesPointerTable - that
; table is indexed flatly by species index. This table is the override: a
; (species, form) key and a pointer to that form's own record.
;
; ONLY the LEVEL-UP LEARNSET is overridden here. A form record is
;
;     db 0                 ; empty evolution block
;     db <level>, <move>   ; the learnset
;     ...
;     db 0                 ; end of learnset
;
; and nothing else. Two deliberate omissions:
;
;   - EVOLUTIONS stay species-keyed. A form already evolves correctly without
;     any help here, because the form bits ride along inside the block-copied
;     party struct (Alolan Vulpix -> NINETALES keeps form 1 -> Alolan
;     Ninetales). TryEvolvingMon and the four stone/level evolution readers in
;     func_enc_gen.asm, bridge_effects.asm and party_menu.asm therefore never
;     reach this table, and the `db 0` above is present only because every
;     consumer skips the evolution block before reading the learnset.
;
;   - The TUTOR block stays species-keyed. PrepareMoveTutorList is NOT routed
;     through GetEvosMovesEntry, so a form keeps its base species' tutor moves.
;     Do not add a tutor block to a form record and expect it to be read; the
;     lookup would have to change first.
;
; The table is walked linearly by GetEvosMovesEntry and terminated by a 0
; species byte. Linear is fine for the same reason FormOverrides is: the walk
; only runs when a mon actually has non-zero form bits, which is never true for
; any of the ordinary species.

FormEvosMovesPointers::
; Entry layout, 4 bytes:
;     db <base species>, <form index>
;     dw <record>
;
; Phase 1 ships this table EMPTY on purpose, so the resolver is wired and
; provably inert - every lookup falls through to EvosMovesPointerTable and
; behaviour is bit-identical to before. Phase 2 fills it in.
	db 0 ; terminator
