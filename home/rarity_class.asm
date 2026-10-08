; RollSpreadClass
; Turns a 0-255 roll plus a rarity bonus into a rarity class (1 = pokeball).
;
; Every random class roll used to ADD its bonus to the roll and saturate at 255.
; That leaves every middle band its base width, so all of the bonus moved odds
; straight from the bottom class to the top one: the gym-leader item bonus took
; masterball items from 20% to 40% while great and ultra never grew.
;
; Here the bonus CASCADES up the classes instead. It drains the pokeball band
; and splits what it frees evenly over every class above (the top class also
; takes the division remainder); whatever bonus is left once pokeball is empty
; drains greatball the same way into ultra and master, then ultra into master.
; The total stays 256, a zero bonus gives exactly the old odds, and no part of
; a stacked bonus is wasted until only the top class is left.
;
; Lives in HOME because the callers are in three different banks. The table is
; read through hl while the CALLER's bank is mapped, so keep each table in the
; same bank as the code that passes it. Never bank-switches. The working widths
; live in a 4-byte frame on the stack, so it needs no RAM of its own.
;
; INPUT:  a  = roll (0-255)
;         b  = bonus (0-255)
;         hl = table: db n, then the n cumulative widths of every class below
;              the top one (pokeball, pokeball+great, ...), then db 0. The top
;              class has no entry; it is the fall-through. n is 2 or 3.
; OUTPUT: c  = class, 1-based
; Clobbers a, b, d, e, hl.
RollSpreadClass::
	push af                ; the roll, read back at sp+5 once the frame is up
	ld a, [hli]
	ld d, a                ; d = n
	ld e, b                ; e = bonus still to spend
	ld b, h
	ld c, l                ; bc = first cumulative width
	add sp, -4             ; frame: W0 W1 W2 at sp+0..2, n at sp+3
	ld hl, sp + 3
	ld [hl], d
	ld hl, sp + 0
	; cumulative widths -> one width per class (d = previous cumulative)
	ld d, 0
.copy
	ld a, [bc]
	and a
	jr z, .copied
	inc bc
	sub d
	ld [hli], a
	add d
	ld d, a
	jr .copy
.copied
	; b = classes above the one being drained, counting the implicit top one
	ld hl, sp + 3
	ld b, [hl]
	ld hl, sp + 0
.drain
	ld a, e
	and a
	jr z, .classify        ; bonus spent
	ld a, [hl]
	cp e
	jr c, .takeAll         ; band narrower than the bonus: empty it
	ld a, e
.takeAll
	ld c, a                ; c = width taken from this band
	ld a, [hl]
	sub c
	ld [hl], a
	ld a, e
	sub c
	ld e, a
	; c = q = taken / b, each higher class's share
	ld a, c
	ld c, -1
.divide
	inc c
	sub b
	jr nc, .divide
	; add q to every stored band above this one; the top class is implicit
	; and keeps the rest (q plus the remainder)
	push hl
	ld d, b
.share
	dec d
	jr z, .shared
	inc hl
	ld a, [hl]
	add c
	ld [hl], a
	jr .share
.shared
	pop hl
	inc hl
	dec b
	jr nz, .drain
.classify
	ld hl, sp + 5
	ld e, [hl]             ; e = roll
	ld hl, sp + 3
	ld b, [hl]             ; b = n
	ld hl, sp + 0
	ld d, 0                ; d = cumulative width; never passes 255 because
	ld c, 1                ;     the top class always keeps its base width
.find
	ld a, d
	add [hl]
	ld d, a
	ld a, e
	cp d
	jr c, .done            ; roll < cumulative: this class
	inc hl
	inc c
	dec b
	jr nz, .find
.done
	add sp, 6              ; the frame and the saved roll
	ret
