; v1.3, 22-dec-2016, stingray
; - source made 100% pc relative and optimised (local labels wherever
;   possible, size optimising etc.)
; - 68000 quitkey support, default quitkey changed to Del (Mantis issue #2531)
; - WHDLoad v17+ features used (config)

;DEBUG

	INCDIR	SOURCES:Include/
	INCLUDE	whdload.i

_base		SLAVE_HEADER			;ws_Security + ws_ID
		dc.w	17			;ws_Version
		dc.w	WHDLF_NoError|WHDLF_EmulTrap
		dc.l	$80000			;ws_BaseMemSize
		dc.l	0			;ws_ExecInstall
		dc.w	Patch-_base		;ws_GameLoader
		IFD	DEBUG
		dc.w	.dir-_base		; ws_CurrentDir
		ELSE
		dc.w	0			;ws_CurrentDir
		ENDC
		dc.w	0			;ws_DontCache
		dc.b	0			;ws_keydebug
		dc.b	$46			;ws_keyexit = Del
		dc.l	0			;ws_ExpMem
		dc.w	.name-_base		;ws_name
		dc.w	.copy-_base		;ws_copy
		dc.w	.info-_base		;ws_info

; v16
	dc.w	0		; ws_kickname
	dc.l	0		; ws_kicksize
	dc.w	0		; ws_kickcrc

; v17
	dc.w	.config-_base	; ws_config


.config	dc.b	"BW"
	dc.b	0


.dir	IFD	DEBUG
	dc.b	"SOURCES:WHD_Slaves/Aquaventura",0
	ENDC

.name		dc.b	"Aquaventura",0
.copy		dc.b	"1992 Psygnosis",0
.info		dc.b	"installed & fixed by Bored Seal & StingRay",10
		dc.b	"V1.3 (22-Dec-2012)",0
		even

Patch		lea	(_resload,pc),a1
		move.l	a0,(a1)			;save for later using
		move.l	a0,a2
                lea     (_tags,pc),a0
                jsr     (resload_Control,a2)

		lea	$5000.w,a0
		moveq	#0,d0
		move.l	#$1600,d1
		moveq	#1,d2
		bsr	LoadProc

		move.w	#$4ef9,$5214
		pea	Disk1_Loader(pc)
		move.l	(sp)+,$5216

		lea	$100.w,a1
		move.w	#$0100,$50d4.w
		move.w	#$4ef9,(a1)+
		pea	PatchIntro(pc)
		move.l	(sp)+,(a1)+

		move.w	#$4ef9,(a1)+
		pea	PatchPicture(pc)
		move.l	(sp)+,(a1)+
		move.w	#$0106,$50b0.w

		jmp	$5026.w

PatchIntro	move.b	#$60,$59bc.w		;track0 pos
		move.w	#$6014,$597e.w		;bfd access
		move.w	#$6022,$5afe.w
		move.w	#$6002,d0
		move.w	d0,$59aa.w		;disk ready check
		move.w	d0,$5a20.w		;disk head move
		move.w	d0,$5a44.w
		move.w	d0,$5a50.w

		move.w	#$4ef9,d0
		move.w	d0,$5338.w		;mfmdecode
		move.w	d0,$534e.w
		pea	Intro_Loader(pc)
		move.l	(sp),$533a.w
		move.l	(sp)+,$5350.w
		move.w	#$6004,$5ac6.w		;read trk
		move.w	#$6030,$5a5c.w

		move.b	#$60,$40f4.w		;don't wait for disk swap

		move.w	d0,$42e8.w
		pea	Disk2_Loader(pc)
		move.l	(sp)+,$42ea.w

		move.w	#$0100,$414a.w
		pea	BootGame(pc)
		move.l	(sp)+,$102.w

; stingray, v1.3
	pea	.CheckQuit(pc)
	move.w	#$4eb9,$5bd2.w
	move.l	(a7)+,$5bd2+2.w

		bsr	PicWait
		jmp	$4000.w


.CheckQuit
	moveq	#0,d0
	move.b	$c00(a0),d0

	move.b	d0,d1
	ror.b	d1
	not.b	d1
	cmp.b	_base+ws_keyexit(pc),d1
	beq.b	QUIT
	rts
	
QUIT	pea	(TDREASON_OK).w
	move.l	_resload(pc),a0
	jmp	resload_Abort(a0)

BootGame	move.w	#$4ef9,$11de.w
		pea	Disk2_Loader(pc)
		move.l	(sp)+,$11e0.w

		move.w	#$600a,$1de2.w		;cacr

		move.w	#$4ef9,$1114.w
		pea	DecrPatch(pc)
		move.l	(sp)+,$1116.w

		move.w	#$6052,$1df6.w		;remove protection
		jmp	$1000.w

DecrPatch	cmp.l	#$207805c0,$11be.w
		bne.b	.NotGame

		move.w	#$6012,$102c.w		;disk access
		pea	PatchGame(pc)
		move.l	(sp)+,$10aa.w
.NotGame	jmp	(a2)

PatchGame	move.l	#$70004e75,d0
		move.l	d0,$260a0		;disable protection check
		move.w	d0,$1ed1e		;disable code checksums
		move.w	d0,$1ef68
		move.b	#$60,$2079c

		move.w	#$6016,$4014.w		;disk access

		pea	PatchMenu(pc)
		move.l	(sp)+,$4088.w

		jmp	$4000.w




PatchMenu	move.l	#$3b6e0002,$23834	;snoopfix


; stingray, v1.3
	pea	.QuitPatch(pc)
	move.w	#$4eb9,$4ef0.w
	move.l	(a7)+,$4ef0+2.w
	move.w	#$4e71,$4ef0+6.w

		jmp	$3b58.w



.QuitPatch
	move.l	#$3d6a,$68.w		; original code


	pea	.CheckQuit(pc)
	move.w	#$4eb9,$3d7c.w
	move.l	(a7)+,$3d7c+2.w
	rts


.CheckQuit
	move.b	$bfec01,d0

	move.l	d0,-(a7)
	ror.b	d0
	not.b	d0
	cmp.b	_base+ws_keyexit(pc),d0
	beq.w	QUIT
	move.l	(a7)+,d0
	rts



Intro_Loader	movem.l	d0-d7/a0-a6,-(sp)
		moveq	#0,d0
		moveq	#0,d1
		move.w	($688,a5),d0
		move.w	($68a,a5),d1
		mulu.w	#$1800,d0
		mulu.w	#$1800,d1
		movea.l	($68c,A5),a0
		add.l	d1,($68c,a5)
		moveq	#1,d2
		bsr	LoadProc
		movem.l	(sp)+,d0-d7/a0-a6
		clr.w	$690(a5)
		rts

Disk1_Loader	movem.l	a0-a2/d0-d2,-(sp)
		mulu.w	#$1800,d0
		mulu.w	#$1800,d1
		moveq	#1,d2
		bsr	LoadProc
		movem.l	(sp)+,a0-a2/d0-d2
		moveq	#0,d4
		rts

Disk2_Loader	movem.l	d0-d7/a0-a6,-(sp)
		cmp.w	#1,d1
		beq.b	.EndLoad
		lea	psyfile(pc),a1
		cmp.w	#5,d1
		bne.b	.ReadRoot
		move.l	#$3000,d0
		move.l	#$1000,d1
		move.l	a0,(a1)
		bra.b	.LoadDisk

.ReadRoot	movea.l	(a1),a2
		lea	($c00,a2),a3
		moveq	#0,d0
		moveq	#0,d1
		moveq	#0,d2
.Loop2		movem.l	a0/a2,-(sp)
.Loop		move.b	(a0)+,d0
		move.b	(a2)+,d1
		cmp.b	d0,d1
		bne.b	.Load_1
		tst.b	d0
		bne.b	.Loop
		bra.b	.Load_2

.Load_1		movem.l	(sp)+,a0/a2
		addq.b	#1,d2
		lea	($10,a2),a2
		bra.b	.Loop2

.Load_2		movem.l	(sp)+,a0/a2
		move.l	(12,a2),d1
		lea	(a3),a4
.Find		cmp.b	(a4)+,d2
		bne.b	.Find
		subq.l	#1,a4
		suba.l	a3,a4
		move.l	a4,d0
		mulu.w	#$400,d0
		movea.l	($24,sp),a0
.LoadDisk	moveq	#2,d2
		bsr	LoadProc
.EndLoad	movem.l	(sp)+,d0-d7/a0-a6
		moveq	#0,d0
		rts

LoadProc	move.l	(_resload,pc),a2
		jmp	(resload_DiskLoad,a2)

PatchPicture	move.w	#$6006,d0
		move.w	d0,$ad02
		move.w	d0,$ad58

		move.l	#$4e714eb9,$ad28
		pea	PicWait(pc)
		move.l	(sp)+,$ad2c
		jmp	$1000.w

PicWait		movem.l	d0-d7/a0-a6,-(sp)
		lea	button(pc),a0
		tst.l	(a0)
		beq.b	.ButtonPressed
		lea	$bfe001,a0
.test		btst	#6,(a0)
		beq.b	.ButtonPressed
		btst	#7,(a0)
		bne.b	.test
.ButtonPressed	movem.l	(sp)+,d0-d7/a0-a6
		rts

_resload	dc.l	0
psyfile		dc.l	0
_tags		dc.l	WHDLTAG_BUTTONWAIT_GET
button		dc.l    0,0
