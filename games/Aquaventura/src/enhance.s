;======================================================================
; Enhanced framerate (CUSTOM1)
;======================================================================
; The game steps its world once per drawn frame (main loop $3c1a: $3e96, the state's
; routines A at ($3c52) and B at ($3c58)), 7 to 10 times a second on an A500. With
; Enhanced framerate the world steps once every PERIOD fields (a "step"), and the frames
; that fit between two steps are drawn by the game's own loop from a state that is then put
; back (a "frame between"): its movement is scaled to the part k/PERIOD of the step that the
; frame shows. Game addresses are absolute chip addresses (docs/internals.md).

; The ExpMem (optional) is the code copy: chip COPY_LO-COPY_HI (src/relocs.i). The saved
; state, the stack and the span fill's loops are in parts of it that hold no code
; (COPY_SAVE, COPY_STACK, _rel_fill), so it stays small enough for a 1 MB A500.
COPYSIZE	= COPY_HI-COPY_LO
FILL_LO		= $12ed8		;the span fill's loop and its mask table
FILL_HI		= $12fc4
FILL_OPS1	= $12f14		;the two places of the five plane instructions
FILL_OPS2	= $12f2e
FILL_SET	= $12ea0		;where the game sets them for the colour ($115e)
FILL_TAB	= $38bc			;10 bytes of instructions per colour, made by $5216
	IFD	VERIFY
EXP_LOG		= COPYSIZE		;VERIFY: addresses a frame between left changed
LOGMAX		= 1000
EXP_SNAP	= EXP_LOG+$1000		;VERIFY: chip memory before a frame between
EXPMEMSIZE	= EXP_SNAP+$80000
	ELSE
EXPMEMSIZE	= COPYSIZE		;whole 4 KB pages
	ENDC
TRAPCHIP	= $4e4f			;trap #15: what the copy holds where no code was copied

STATE_GAME	= $60			;the state ($1090) with frames between
PERIOD		= 6			;fields a step: the A500 draws 7 to 10 frames a second there
PERIOD_OTHER	= 5			;fields a pass in the states $70, $b0 (the tunnel) and $c0

; The game version: the CRC of chip COPY_LO-COPY_HI, before any patch there.
_gamecrc	movem.l	d0-d1/a0-a2,-(a7)
		move.l	#COPYSIZE,d0
		lea	COPY_LO,a0
		movea.l	(_resload,pc),a2
		jsr	(resload_CRC16,a2)
		lea	(_crc,pc),a0
		move.w	d0,(a0)
		movem.l	(a7)+,d0-d1/a0-a2
		rts

; Enhanced framerate is on when CUSTOM1 is set, the ExpMem was allocated, the CPU is a 68020
; or better and the game is the one the patches were made for (_gamecrc, .sites). Otherwise
; nothing is patched and the game runs as with v1.3.
_enhance	movem.l	d0-d1/a0-a2,-(a7)
		move.l	(_custom1,pc),d0
		beq.w	.off
		move.l	(_expmem,pc),d0
		beq.w	.off
		move.l	(_attn,pc),d0
		btst	#AFB_68020,d0
		beq.w	.off
		move.w	(_crc,pc),d0
		cmpi.w	#COPY_CRC,d0
		bne.w	.off
		lea	(.sites,pc),a0		;the instructions the patches replace
.chk		move.l	(a0)+,d0
		beq.b	.ok
		movea.l	d0,a1
		move.l	(a0)+,d0
		cmp.l	(a1),d0
		beq.b	.chk
		bra.w	.off
.ok		lea	(_enhanced,pc),a0
		st	(a0)
		lea	(_valid,pc),a0
		clr.w	(a0)
	IFD	AUTOFIRE
		lea	(_crc,pc),a0		;the test builds' counters, at the first start
		tst.w	(2,a0)
		bne.b	.cld
		st	(2,a0)
		lea	$c0.w,a0
		moveq	#15,d1
.cl		clr.l	(a0)+
		dbf	d1,.cl
.cld
	ENDC
		move.l	(_custom2,pc),d1	;CUSTOM2: fields a step
		moveq	#3,d0
		cmp.l	d0,d1
		bhi.b	.def
		lea	(.periods,pc),a0
		move.b	(a0,d1.w),d0
		bra.b	.per
.def		moveq	#PERIOD,d0
	IFD	VERIFY
		move.l	d1,d0			;VERIFY: CUSTOM2 from 4 up is the period itself
	ENDC
.per		lea	(_period,pc),a0
		move.w	d0,(a0)

		lea	(_stinit,pc),a0		;$3c14: move.w $1090,$1092
		lea	$3c14.w,a1
		bsr.w	.jsr
		lea	(_frame,pc),a0		;$3c4a: jsr $3e96
		lea	$3c4a.w,a1
		move.w	#$4ef9,(a1)+
		move.l	a0,(a1)
		lea	(_vbl,pc),a0		;$3ef0: bsr.w $3fc4; bsr.b $3f0c
		lea	$3ef0.w,a1
		bsr.w	.jsr
		lea	(_vblsnd,pc),a0		;$3edc: jsr $239ea
		lea	$3edc.w,a1
		bsr.w	.jsr
		lea	(_swap,pc),a0		;$5056: addq.w #1,$3f06; move.w #$10,$dff09c
		lea	$5056.w,a1
		bsr.w	.jsr
		move.l	#$4e714e71,(a1)+
		move.w	#$4e71,(a1)
		lea	(_rot,pc),a0		;$84a6: jsr $d1d6
		lea	$84a6,a1
		bsr.w	.jsr
		lea	(_move,pc),a0		;$84b4: jsr $d4ea
		lea	$84b4,a1
		bsr.w	.jsr
		lea	(_horizon,pc),a0	;$1ea16: sub.w d0,$1eb72
		lea	$1ea16,a1
		bsr.w	.jsr
		lea	(_fillinit,pc),a0	;$3bba: jsr $5216
		lea	$3bba.w,a1
		bsr.w	.jsr
		bsr.w	_mkcopy
		bra.w	.ret
.off
	IFD	SKIPKEYS
		lea	(_vbl,pc),a0		;test builds: the keys also without the option
		lea	$3ef0.w,a1
		bsr.w	.jsr
	ENDC
.ret		movem.l	(a7)+,d0-d1/a0-a2
		rts
.jsr		move.w	#$4eb9,(a1)+
		move.l	a0,(a1)+
		rts

.periods	dc.b	PERIOD,5,7,8
.sites		dc.l	$3c14,$31f81090,$3c4a,$4eb90000,$3ef0,$610000d2,$3edc,$4eb90002
		dc.l	$5056,$52783f06,$84a6,$4eb90000,$84b4,$4eb90000,$3bba,$4eb90000
		dc.l	$1ea14,$ea409179,0

; $3c14, after a state's init routine: the saved state is no longer the game's.
_stinit		move.w	$1090.w,$1092.w
		move.l	a0,-(a7)
		lea	(_valid,pc),a0
		clr.w	(a0)
		movea.l	(a7)+,a0
		rts

; The main loop's pass: a step, or a frame between two steps.
_frame		cmpi.w	#STATE_GAME,$1090.w
		bne.w	.native
		move.w	(_valid,pc),d0
		beq.b	.step
		move.l	(_fields,pc),d1
		sub.l	(_tlast,pc),d1		;fields since the last step was shown
		moveq	#0,d0
		move.w	(_durb,pc),d0
		add.l	d0,d1			;when this pass would be shown
		move.l	d1,d2
		move.w	(_durs,pc),d0
		add.l	d0,d2			;and the step after it
		move.w	(_period,pc),d0
		cmp.l	d0,d2
		bgt.b	.step			;too late for the step: the step now (_swap waits)
		tst.l	d1
		bgt.b	.between
		moveq	#1,d1
		bra.b	.between

; a step: the game's pass, shown PERIOD fields after the last step (_swap waits)
.step		lea	(_mode,pc),a0
		clr.w	(a0)
		lea	(_pernow,pc),a0
		move.w	(_period,pc),(a0)
		lea	(_instep,pc),a0
		st	(a0)
		jsr	$3e96.w
		movea.l	$3c52.w,a0
		adda.l	(_delta,pc),a0
		jsr	(a0)
		movea.l	$3c58.w,a0
		adda.l	(_delta,pc),a0
		jsr	(a0)
		lea	(_saved,pc),a0
		sf	(a0)
	IFD	AUTOFIRE
		addq.l	#1,$c0.w		;test builds: steps, frames between, fields
	ENDC
		lea	(_valid,pc),a0
		st	(a0)
		jmp	$3c5c.w			;the loop's top: a state change, the pause key

; a frame between: the pass with its movement scaled to d1/PERIOD, then the state back
.between	lea	(_mode,pc),a0
		move.w	d1,(a0)
		lea	(_saved,pc),a0		;the first one after a step saves the state
		tst.b	(a0)
		bne.b	.have
		st	(a0)
		bsr.w	_save
.have
		move.w	#$0008,$dff09a		;no keyboard interrupt: the key table is restored
		bsr.w	_sndsave
	IFD	VERIFY
		bsr.w	_vsnap
	ENDC
		movea.l	$3c52.w,a0
		adda.l	(_delta,pc),a0
		jsr	(a0)
		movea.l	$3c58.w,a0
		adda.l	(_delta,pc),a0
		jsr	(a0)
		bsr.w	_restore
	IFD	VERIFY
		bsr.w	_vcheck
	ENDC
	IFD	AUTOFIRE
		addq.l	#1,$c4.w
	ENDC
		lea	(_mode,pc),a0
		clr.w	(a0)
		move.w	#$8008,$dff09a
		bra.w	_frame			;nothing changed: not through the loop's top

; another state: the game's pass. In the states that play (the A500 draws 10 frames a second
; there) it is shown PERIOD_OTHER fields after the last one.
.native		lea	(_valid,pc),a0
		clr.w	(a0)
		move.w	$1090.w,d0
		cmpi.w	#$70,d0
		beq.b	.paced
		cmpi.w	#$b0,d0
		beq.b	.paced
		cmpi.w	#$c0,d0
		bne.b	.free
.paced		lea	(_pernow,pc),a0
		move.w	#PERIOD_OTHER,(a0)
		lea	(_instep,pc),a0
		st	(a0)
.free		jsr	$3e96.w
		jmp	$3c50.w

; $5056, the buffer swap's first two instructions; the swap then waits for the copper
; interrupt request (set below the view) and swaps. The wait is done here, so that the
; fields a pass took are counted at the same beam position every time, and a step waits for
; its field. On return the request is set, and the game's wait ends at once.
_swap		addq.w	#1,$3f06.w
		move.w	#$10,$dff09c
.cop		btst	#4,$dff01f
		beq.b	.cop
		movem.l	d0-d1/a0,-(a7)
		move.l	(_fields,pc),d0
		move.l	d0,d1
		sub.l	(_tswap,pc),d1		;fields since the last swap: what this pass took
		bgt.b	.pos
		moveq	#1,d1
.pos		cmpi.l	#255,d1
		bls.b	.fit
		moveq	#0,d1
		not.b	d1
.fit		move.b	(_instep,pc),d0
		bne.b	.step
		lea	(_durb,pc),a0
		move.w	d1,(a0)
		bra.b	.done
.step		lea	(_durs,pc),a0
		move.w	d1,(a0)
		lea	(_instep,pc),a0
		sf	(a0)
		move.l	(_tlast,pc),d1
		moveq	#0,d0
		move.w	(_pernow,pc),d0
		add.l	d0,d1			;the field this step is due
.wait		move.l	(_fields,pc),d0
		cmp.l	d1,d0
		bpl.b	.due
		move.w	#$10,$dff09c		;the next field's request
.w2		btst	#4,$dff01f
		beq.b	.w2
		bra.b	.wait
.due		lea	(_tlast,pc),a0
		move.l	d0,(a0)
.done		lea	(_tswap,pc),a0
		move.l	(_fields,pc),(a0)
	IFD	AUTOFIRE
		move.w	(_mode,pc),$e4.w	;test builds: the pass that is swapped in
	ENDC
		movem.l	(a7)+,d0-d1/a0
		rts

; $84a6: jsr $d1d6 with an object's four turn rates in d4-d7. $84b4: jsr $d4ea with its
; speed in d0. In a frame between they are the part of the step that the frame shows.
_rot		move.w	(_mode,pc),-(a7)
		beq.b	.go
		muls.w	(a7),d4
		divs.w	(_period,pc),d4
		muls.w	(a7),d5
		divs.w	(_period,pc),d5
		muls.w	(a7),d6
		divs.w	(_period,pc),d6
		muls.w	(a7),d7
		divs.w	(_period,pc),d7
.go		addq.l	#2,a7
		move.l	(_delta,pc),-(a7)
		addi.l	#$d1d6,(a7)
		rts

_move		move.w	(_mode,pc),-(a7)
		beq.b	.go
		muls.w	(a7),d0
		divs.w	(_period,pc),d0
.go		addq.l	#2,a7
		move.l	(_delta,pc),-(a7)
		addi.l	#$d4ea,(a7)
		rts

; $1ea16: sub.w d0,$1eb72, the horizon's scroll by the turn rate.
_horizon	move.w	(_mode,pc),-(a7)
		beq.b	.go
		muls.w	(a7),d0
		divs.w	(_period,pc),d0
.go		addq.l	#2,a7
		sub.w	d0,$1eb72
		rts

; $3ef0 in the level 3 handler: the joystick ($3fc4) and the crosshair ($3f0c), and the
; field counter.
_vbl		jsr	$3fc4.w
		jsr	$3f0c.w
		lea	(_fields,pc),a0
		addq.l	#1,(a0)
	IFD	AUTOFIRE
		move.l	(a0),$c8.w
	ENDC
	IFD	SKIPKEYS
; test builds: with the cheat on, the key L (next level) or T (tunnel) every 2048 fields,
; and the states seen (bit = state/16) at $e0
		move.l	(a0),d0
		andi.w	#$7ff,d0
		bne.b	.nokey
		btst	#3,2(a0)
		bne.b	.keyt
		bclr	#1,$3a4d.w		;L
		bra.b	.nokey
.keyt		bclr	#1,$3a25.w		;T
.nokey		move.w	$1090.w,d0
		lsr.w	#4,d0
		andi.w	#15,d0
		move.w	$e0.w,d1
		bset	d0,d1
		move.w	d1,$e0.w
	ENDC
		btst	#7,$bfe001
		beq.b	.pressed
		lea	(_released,pc),a0
		st	(a0)
.pressed	rts

; $3edc in the level 3 handler: jsr $239ea, the sound effects. During a frame between
; it works on the requests ($23c5c-$23c93) of the last step, not the frame's.
_vblsnd		move.b	(_insnd,pc),d0
		beq.b	.go
		bsr.b	_sndswap
		jsr	$239ea
		bra.b	_sndswap
.go		jmp	$239ea

SNDREQ		= $23c5c
SNDREQSIZE	= $38
_sndswap	lea	SNDREQ,a0
		lea	(_sndbuf,pc),a1
		moveq	#SNDREQSIZE/4-1,d0
.l		move.l	(a0),d1
		move.l	(a1),(a0)+
		move.l	d1,(a1)+
		dbf	d0,.l
		rts

; before a frame between: the sound requests and the fire latch
_sndsave	move.w	#$4000,$dff09a
		lea	SNDREQ,a0
		lea	(_sndbuf,pc),a1
		moveq	#SNDREQSIZE/4-1,d0
.l		move.l	(a0)+,(a1)+
		dbf	d0,.l
		lea	(_fire,pc),a0
		move.b	$114d.w,(a0)
		lea	(_released,pc),a0
		sf	(a0)
		lea	(_insnd,pc),a0
		st	(a0)
		move.w	#$c000,$dff09a
		rts

; after a step: _statetab's ranges to the ExpMem
_save		lea	COPY_SAVE,a1
		adda.l	(_delta,pc),a1
		lea	(_statetab,pc),a2
.r		move.l	(a2)+,d0
		beq.b	.done
		movea.l	d0,a0
		move.w	(a2)+,d0
		bsr.b	_copy
		bra.b	.r
.done		rts

; after a frame between: the state of the last step again
_restore	lea	COPY_SAVE,a0
		adda.l	(_delta,pc),a0
		lea	(_statetab,pc),a2
.r		move.l	(a2)+,d0
		beq.b	.done
		movea.l	d0,a1
		move.w	(a2)+,d0
		bsr.b	_copy
		bra.b	.r
.done		move.w	#$4000,$dff09a
		lea	(_sndbuf,pc),a0		;the requests as the handler left them
		lea	SNDREQ,a1
		moveq	#SNDREQSIZE/4-1,d0
.l		move.l	(a0)+,(a1)+
		dbf	d0,.l
		move.b	(_released,pc),d0	;the fire latch $114d: the game sets it when it
		not.b	d0			;takes a press, the handler clears it on release
		and.b	(_fire,pc),d0
		move.b	d0,$114d.w
		jsr	$3ff0.w			;$114c from the button and $114d, as the handler does
		lea	(_insnd,pc),a0
		sf	(a0)
		move.w	#$c000,$dff09a
		rts

; d0.w bytes (even) from (a0)+ to (a1)+
_copy		lsr.w	#2,d0
		bcc.b	.longs
		move.w	(a0)+,(a1)+
.longs		subq.w	#1,d0
		bmi.b	.done
.l		move.l	(a0)+,(a1)+
		dbf	d0,.l
.done		rts

	IFD	VERIFY
; VERIFY: a frame between must leave the game's memory as it was. _vsnap copies chip memory
; $1000-$80000 before the frame, _vcheck compares after the restore and logs the addresses
; that differ (EXP_LOG, the count at $cc, the ExpMem's address at $d0), except what the
; interrupts own, the screens, the stack and the draw's scratch (_vexcl).
_vsnap		lea	$1000.w,a0
		movea.l	(_expmem,pc),a1
		adda.l	#EXP_SNAP+$1000,a1
		move.l	#($80000-$1000)/4-1,d0
.l		move.l	(a0)+,(a1)+
		subq.l	#1,d0
		bpl.b	.l
		rts

_vcheck		movem.l	d0-d3/a0-a3,-(a7)
		move.l	(_expmem,pc),$d0.w
		lea	$1000.w,a0
		movea.l	(_expmem,pc),a1
		adda.l	#EXP_SNAP+$1000,a1
		move.l	#($80000-$1000)/2-1,d0
.l		cmpm.w	(a0)+,(a1)+
		bne.b	.diff
.next		subq.l	#1,d0
		bpl.b	.l
		movem.l	(a7)+,d0-d3/a0-a3
		rts
.diff		move.l	a0,d1
		subq.l	#2,d1			;the address
		lea	(_vexcl,pc),a2
.x		move.l	(a2)+,d2
		beq.b	.buf
		move.l	(a2)+,d3
		cmp.l	d2,d1
		bcs.b	.x
		cmp.l	d3,d1
		bcs.b	.next
		bra.b	.x
.buf		move.l	$1154.w,d2		;the two screens (40000 bytes each)
		bsr.b	.inbuf
		beq.b	.next
		move.l	$1158.w,d2
		bsr.b	.inbuf
		beq.b	.next
		movea.l	(_expmem,pc),a2
		adda.l	#EXP_LOG,a2
		move.l	$cc.w,d2
		movea.l	a2,a3
		bra.b	.fe
.find		cmp.l	(a3)+,d1
		beq.b	.next
.fe		dbf	d2,.find
		move.l	$cc.w,d2
		cmpi.l	#LOGMAX,d2
		bcc.b	.next
		addq.l	#1,$cc.w
		lsl.l	#2,d2
		move.l	d1,(a2,d2.l)
		bra.b	.next
.inbuf		move.l	d1,d3
		sub.l	d2,d3
		cmpi.l	#40000,d3
		bcs.b	.in
		moveq	#1,d3
		rts
.in		moveq	#0,d3
		rts

_vexcl		dc.l	$1148,$114e,$1154,$115e,$3afc,$3afe,$3b04,$3b08,$3f04,$3f0c
		dc.l	$4024,$4c00,$5300,$5548,$9b86,$a508,$a510,$b9ca,$c8a0,$cb20,$12f14,$132e8,$13990,$13994
		dc.l	$23090,$24000,$7ff00,$80000,0
	ENDC

; The code copy. The game's code runs from chip memory, which is as slow on an accelerated
; Amiga as on an A500. _mkcopy puts the code that tools/codemap.py reaches from chip
; COPY_LO-COPY_HI into the ExpMem (src/relocs.i, tools/relocs.py). All data stays in chip
; memory, and what was not copied is TRAP #15: _trapchip continues there in chip memory.
; _delta = copy - chip, or 0 without the copy (no fast ExpMem, another game version).
_mkcopy		movem.l	d0-d7/a0-a6,-(a7)
		move.l	(_expmem,pc),d7
		subi.l	#COPY_LO,d7		;delta
		lea	COPY_LO,a0
		adda.l	d7,a0
		move.l	#COPYSIZE/2-1,d0
.fill		move.w	#TRAPCHIP,(a0)+
		subq.l	#1,d0
		bpl.b	.fill
		lea	(_rel_ranges,pc),a2
.rng		move.l	(a2)+,d0
		beq.b	.code
		movea.l	d0,a0
		lea	(a0,d7.l),a1
		move.w	(a2)+,d0
		lsr.w	#1,d0
		subq.w	#1,d0
.cp		move.w	(a0)+,(a1)+
		dbf	d0,.cp
		bra.b	.rng
.code		lea	(_rel_code,pc),a2
.rc		move.l	(a2)+,d0
		beq.b	.absw
		movea.l	d0,a1
		add.l	d7,(a1,d7.l)
		bra.b	.rc
.absw		lea	(_rel_absw,pc),a2	;d16(pc) -> abs.w
.ra		move.l	(a2)+,d0
		beq.b	.stub
		movea.l	d0,a0			;the instruction in chip
		lea	(a0,d7.l),a1
		move.w	(a2)+,d1		;offset of the displacement
		andi.w	#$ffc0,(a1)
		ori.w	#$0038,(a1)
		move.w	(a0,d1.w),d2
		add.w	d1,d2
		add.w	a0,d2			;the target, below $8000
		move.w	d2,(a1,d1.w)
		bra.b	.ra
.stub		lea	(_rel_stub,pc),a2	;d16(pc) -> a stub with abs.l
.rs		move.l	(a2)+,d0
		beq.b	.out
		movea.l	d0,a0			;the instruction in chip
		move.w	(a2)+,d3		;its length
		move.w	(a2)+,d1		;offset of the displacement
		movea.l	(a2)+,a3		;the stub
		move.l	a3,d4
		adda.l	d7,a3
		movea.l	a0,a4
		move.w	d1,d0
		lsr.w	#1,d0
		subq.w	#1,d0
		movea.l	a3,a5
.s1		move.w	(a4)+,(a3)+		;the words before the displacement
		dbf	d0,.s1
		andi.w	#$ffc0,(a5)
		ori.w	#$0039,(a5)
		move.w	(a4)+,d2
		ext.l	d2
		add.l	a0,d2
		ext.l	d1
		add.l	d1,d2
		move.l	d2,(a3)+		;the chip address
		move.w	d3,d0
		sub.w	d1,d0
		subq.w	#2,d0
		lsr.w	#1,d0
		bra.b	.s2e
.s2		move.w	(a4)+,(a3)+		;the words after it
.s2e		dbf	d0,.s2
		move.w	#$4ef9,(a3)+		;jmp back
		ext.l	d3
		add.l	a0,d3
		add.l	d7,d3
		move.l	d3,(a3)+
		lea	(a0,d7.l),a1		;the instruction in the copy: bra.w stub
		move.w	#$6000,(a1)+
		sub.l	a0,d4
		subq.l	#2,d4
		move.w	d4,(a1)
		bra.b	.rs
.out		lea	(_rel_out,pc),a2	;bsr.w/bra.w/jsr d16(pc)/jmp d16(pc) -> abs.w
.ro		move.l	(a2)+,d0
		beq.b	.chip
		movea.l	d0,a0
		lea	(a0,d7.l),a1
		move.w	(a0),d1
		move.w	#$4eb8,d2
		cmpi.w	#$6100,d1
		beq.b	.o1
		cmpi.w	#$4eba,d1
		beq.b	.o1
		move.w	#$4ef8,d2
.o1		move.w	d2,(a1)+
		move.w	2(a0),d2
		add.w	a0,d2
		addq.w	#2,d2
		move.w	d2,(a1)
		bra.b	.ro
.chip		lea	(_rel_chip,pc),a2	;entries of chip-only routines: jmp chip
.rh		move.l	(a2)+,d0
		beq.b	.tramp
		movea.l	d0,a0
		lea	(a0,d7.l),a1
		move.w	#$4ef9,(a1)+
		move.l	a0,(a1)
		bra.b	.rh
.tramp		lea	(_rel_tramp,pc),a2	;chip entries reached through pointers: jmp copy
.rt		move.l	(a2)+,d0
		beq.b	.vec
		movea.l	d0,a0
		add.l	d7,d0
		move.w	#$4ef9,(a0)+
		move.l	d0,(a0)
		bra.b	.rt
.vec		lea	(_trapchip,pc),a0	;the game can start again: once
		cmpa.l	$bc.w,a0
		beq.b	.vecd
		lea	(_trapold,pc),a1
		move.l	$bc.w,(a1)
		move.l	a0,$bc.w
.vecd
		lea	(_delta,pc),a0
		move.l	d7,(a0)
		move.l	d7,d0			;the stack in the ExpMem: the game sets it at
		addi.l	#COPY_STACK+STACKSIZE,d0	;$22670 (lea $80000,sp); the slave at its entry
		lea	(_stack,pc),a0
		move.l	d0,(a0)
		lea	$22670,a1
		cmpi.w	#$4ff9,(a1)+
		bne.b	.nosp
		move.l	d0,(a1)
		move.l	d0,(a1,d7.l)		;and in the copy
.nosp
	IFD	AUTOFIRE
		move.l	d7,$dc.w		;test builds: the copy's offset
	ENDC
		movea.l	(_resload,pc),a2
		jsr	(resload_FlushCache,a2)
.done		movem.l	(a7)+,d0-d7/a0-a6
		rts

; $3bba: jsr $5216, which makes the span fill's instruction table (FILL_TAB). The game's
; fill ($12e7c) writes the five plane instructions of the colour into its loop when the
; colour changes. Code that changes itself needs a cache flush where the ExpMem is cached,
; so the copy gets one loop per colour (_rel_fill), and FILL_SET in the copy becomes a jump
; to the colour's loop.
_fillinit	jsr	$5216.w
		movem.l	d0-d3/a0-a5,-(a7)
		lea	(_filltab,pc),a4
		lea	FILL_TAB.w,a3
		lea	(_rel_fill,pc),a5
.gap		move.l	(a5)+,d0
		beq.b	.set
		movea.l	d0,a1
		adda.l	(_delta,pc),a1
		move.w	(a5)+,d2
		subq.w	#1,d2
.col		move.l	a1,(a4)+
		movea.l	a1,a2
		lea	FILL_LO,a0
		move.w	#(FILL_HI-FILL_LO)/2-1,d0
.cp		move.w	(a0)+,(a1)+
		dbf	d0,.cp
		moveq	#4,d0
.op		move.w	(a3),(FILL_OPS1-FILL_LO,a2)
		move.w	(a3)+,(FILL_OPS2-FILL_LO,a2)
		addq.l	#2,a2
		dbf	d0,.op
		dbf	d2,.col
		bra.b	.gap
.set
		lea	FILL_SET,a0		;in the copy:
		adda.l	(_delta,pc),a0
		move.l	#$3038115e,(a0)+	;move.w $115e.w,d0
		move.l	#$d040d040,(a0)+	;add.w d0,d0 (twice)
		move.w	#$45f9,(a0)+		;lea _filltab,a2
		lea	(_filltab,pc),a1
		move.l	a1,(a0)+
		move.l	#$24720000,(a0)+	;movea.l (0,a2,d0.w),a2
		move.w	#$4ed2,(a0)+		;jmp (a2)
		movea.l	(_resload,pc),a2
		jsr	(resload_FlushCache,a2)
		movem.l	(a7)+,d0-d3/a0-a5
		rts

; TRAP #15 in the copy: the same instruction in chip memory
_trapchip	move.l	d0,-(a7)
		move.l	6(a7),d0
		subq.l	#2,d0
		sub.l	(_delta,pc),d0
		cmpi.l	#COPY_LO,d0
		bcs.b	.other
		cmpi.l	#COPY_HI,d0
		bcc.b	.other
		move.l	d0,6(a7)
	IFD	AUTOFIRE
		addq.l	#1,$d4.w		;test builds: traps, the last one's address
		move.l	d0,$d8.w
	ENDC
		move.l	(a7)+,d0
		rte
.other		move.l	(a7)+,d0
		move.l	(_trapold,pc),-(a7)
		rts

_delta		dc.l	0
_trapold	dc.l	0
_filltab	ds.l	32	;the span fill's loop for each colour
_stack		dc.l	0	;the stack's top in the ExpMem, or 0
_crc		dc.w	0
		dc.w	0	;test builds: the counters are cleared
_enhanced	dc.w	0
_period		dc.w	PERIOD	;fields a step in STATE_GAME
_pernow		dc.w	PERIOD	;fields this step is shown after the last
_mode		dc.w	0	;0 in a step, k in a frame between that shows k/PERIOD of the step
_valid		dc.w	0	;the saved state is the game's
_durb		dc.w	1	;fields the last frame between took, swap to swap
_durs		dc.w	1	;fields the last step took, before its wait
_instep		dc.b	0
_saved		dc.b	0	;_save ran after the last step
_insnd		dc.b	0	;_sndbuf holds the last step's sound requests
_fire		dc.b	0
_released	dc.b	0
		even
_fields		dc.l	0	;fields, counted by the level 3 handler
_tlast		dc.l	0	;the field the last step swapped in
_tswap		dc.l	0	;the field of the last swap
_sndbuf		ds.b	SNDREQSIZE

	INCLUDE	state.i
	INCLUDE	relocs.i

	IFNE	COPYSIZE&$fff
	FAIL	"the copy is not whole pages"
	ENDC
	IFGT	STATESIZE-SAVESIZE
	FAIL	"the saved state does not fit COPY_SAVE"
	ENDC
