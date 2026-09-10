; Bank-safe max-PP lookup for the trainer party builder.
;
; WHY THIS EXISTS
; ---------------
; ReadTrainer's .AddAdditionalMoveData substitutes a move into an already-built
; enemy mon and then has to give that move its own max PP. It used to read the
; PP straight out of the Moves table with a plain in-bank `ld a, [hl]`, which
; was correct only because ReadTrainer happened to live in the same bank as
; Moves. The gym-leader expansion moves the trainer party data and ReadTrainer
; out to their own bank, so that read would have become a cross-bank read of
; whatever byte happens to sit at that offset in the NEW bank: no crash, no
; warning, just wrong PP on every substituted move.
;
; Rather than teach ReadTrainer to do a far read (which needs a WRAM landing
; byte, and every scratch buffer in range is union'd with something), the lookup
; stays on THIS side of the seam, beside the table it reads, and is reached by
; farcall.
;
; REGISTER CONTRACT
; -----------------
; Bankswitch (home/bankswitch.asm) touches only a, b, c, h and l, so de is the
; only pair that survives a farcall in either direction. Both the argument and
; the result therefore travel in e.
;
; INPUT:  e = move id (1-based, as stored in MON_MOVES)
; OUTPUT: e = that move's max PP
; Clobbers a, b, c, h, l - all of which a farcall destroys anyway.
GetMoveMaxPPFar::
	ld a, e
	dec a
	ld hl, Moves + MOVE_PP
	ld bc, MOVE_LENGTH
	call AddNTimes        ; hl -> this move's PP byte, in THIS bank
	ld e, [hl]
	ret

; The plain read above is only valid while this routine and the table share a
; bank. If a future relocation splits them, fail the LINK rather than ship a
; silent garbage read - the exact failure this file was created to prevent.
ASSERT BANK(GetMoveMaxPPFar) == BANK(Moves), \
       "GetMoveMaxPPFar does a plain in-bank read of Moves; it must stay in that bank"
