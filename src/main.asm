    DEVICE ZXSPECTRUM48

    ORG $8000

; ---------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------
SCREEN_ADDR     EQU $4000
ATTR_ADDR       EQU $5800

GROUND_ROW      EQU 18
; The ramp is a staircase one cell taller per column, so its tallest
; column is RAMP_RISE+1 cells: 3 cells against the 4-cell-tall bike.
RAMP_START_COL  EQU 10
RAMP_END_COL    EQU 12
RAMP_RISE       EQU RAMP_END_COL-RAMP_START_COL
LIFTOFF_ROW     EQU GROUND_ROW-RAMP_RISE
PEOPLE_START_COL EQU RAMP_END_COL+1
MAX_NPEOPLE     EQU 32-PEOPLE_START_COL

; Bike sprite size in cells. BikeCol/BikeRow are its bottom-left cell
; (the rear wheel); the front wheel is what rides up the ramp.
BIKE_W          EQU 4
BIKE_H          EQU 4
BIKE_START_COL  EQU 1
LIFTOFF_COL     EQU RAMP_END_COL-BIKE_W+1
MAX_BIKE_COL    EQU 32-BIKE_W

MAX_SPEED       EQU 28
PEDAL_INC       EQU 3
FRICTION_MASK   EQU 3
MOVE_THRESHOLD  EQU 16
FRAME_DELAY     EQU 60

ATTR_HUD        EQU $47   ; bright white on black
ATTR_GROUND     EQU $44   ; bright green on black
ATTR_RAMP       EQU $46   ; bright yellow on black
ATTR_PERSON     EQU $42   ; bright red on black
ATTR_BIKE       EQU $45   ; bright cyan on black

; ---------------------------------------------------------------------
; Entry point
; ---------------------------------------------------------------------
Start:
    di
    ld sp,$ff00
    xor a
    out ($fe),a

TitleScreen:
    call ClearScreen
    ld hl,Str_Title
    ld b,2
    ld c,9
    call PrintString
    ld hl,Str_Instr1
    ld b,10
    ld c,4
    call PrintString
    ld hl,Str_Instr2
    ld b,12
    ld c,3
    call PrintString
    ld hl,Str_Instr3
    ld b,15
    ld c,9
    call PrintString
    call WaitAnyKeyFresh

NewGame:
    xor a
    ld (Score),a
    ld a,3
    ld (Lives),a
    ld a,1
    ld (NPeople),a

RoundInit:
    call ClearScreen
    call DrawHUD
    call DrawScene
    ld a,BIKE_START_COL
    ld (BikeCol),a
    ld a,GROUND_ROW
    ld (BikeRow),a
    xor a
    ld (Speed),a
    ld (LastKey),a
    ld (PrevPO),a
    ld (FrictionCounter),a
    ld (BikeFrame),a
    ld a,MOVE_THRESHOLD
    ld (MoveTimer),a

; ---------------------------------------------------------------------
; Pedal phase: bike rides from the start towards the ramp; speed is
; built by alternating the O and P keys, and decays with friction.
; ---------------------------------------------------------------------
PedalLoop:
    call DrawBike
    call Delay
    call EraseBike
    call ReadPedalInput
    call ApplyFriction
    call AdvanceBike
    ld a,(BikeCol)
    cp LIFTOFF_COL
    jr c,PedalLoop
    jp JumpPhase

; ---------------------------------------------------------------------
; Jump phase: fixed 8-frame arc. Horizontal distance travelled equals
; the speed at takeoff; the jump succeeds if the rear wheel lands past
; the last person.
; ---------------------------------------------------------------------
JumpPhase:
    ld a,LIFTOFF_COL
    ld (BikeCol),a
    ld a,LIFTOFF_ROW
    ld (BikeRow),a
    ld a,(Speed)
    ld (JumpDistance),a
    ld b,a
    srl a
    srl a
    srl a
    ld (JumpStep),a
    ld a,b
    and 7
    ld (JumpRem),a
    ld a,1
    ld (JumpFrame),a

.frameloop:
    ld a,(JumpFrame)
    cp 8
    ld hl,JumpStep
    jr nz,.notlast
    ld a,(hl)
    ld hl,JumpRem
    add a,(hl)
    jr .havemove
.notlast:
    ld a,(hl)
.havemove:
    ld hl,BikeCol
    add a,(hl)
    cp MAX_BIKE_COL+1
    jr c,.okcol
    ld a,MAX_BIKE_COL
.okcol:
    ld (BikeCol),a

    ld a,(JumpFrame)
    dec a
    ld hl,JumpHeights
    ld d,0
    ld e,a
    add hl,de
    ld a,(hl)
    ld e,a
    ld a,GROUND_ROW
    sub e
    ld (BikeRow),a

    call DrawBike
    call Delay
    ld a,(JumpFrame)
    cp 8
    jr z,.skiperase
    call EraseBike
.skiperase:
    ld a,(JumpFrame)
    inc a
    ld (JumpFrame),a
    cp 9
    jp nz,.frameloop

    ; rear wheel lands at LIFTOFF_COL+distance; the last person is at
    ; PEOPLE_START_COL+NPeople-1, so clearing them needs
    ; distance >= NPeople + (PEOPLE_START_COL-LIFTOFF_COL)
    ld a,(NPeople)
    add a,PEOPLE_START_COL-LIFTOFF_COL
    ld d,a
    ld a,(JumpDistance)
    cp d
    jp nc,JumpSuccess
    jp JumpFail

JumpSuccess:
    ld a,(Score)
    inc a
    ld (Score),a
    ld a,(NPeople)
    cp MAX_NPEOPLE
    jr nc,.capped
    inc a
.capped:
    ld (NPeople),a
    ld hl,Str_Cleared
    ld b,20
    ld c,10
    call PrintString
    call DelayLong
    jp RoundInit

JumpFail:
    ld a,(Lives)
    dec a
    ld (Lives),a
    ld hl,Str_Ouch
    ld b,20
    ld c,13
    call PrintString
    call DelayLong
    ld a,(Lives)
    or a
    jp z,GameOver
    jp RoundInit

GameOver:
    call ClearScreen
    ld hl,Str_GameOver
    ld b,8
    ld c,11
    call PrintString
    ld hl,Str_FinalScore
    ld b,11
    ld c,7
    call PrintString
    ld a,(Score)
    ld b,11
    ld c,20
    call PrintNumber3
    ld hl,Str_Instr3
    ld b,15
    ld c,9
    call PrintString
    call WaitAnyKeyFresh
    jp NewGame

; ---------------------------------------------------------------------
; Pedal input handling
; ---------------------------------------------------------------------

; O and P must be pressed alternately to keep building speed; repeating
; the same key with no alternation in between is ignored.
ReadPedalInput:
    ld a,$df
    in a,($fe)
    and $03
    xor $03
    ld b,a
    ld a,(PrevPO)
    cpl
    and b
    ld c,a
    ld a,b
    ld (PrevPO),a

    ld a,c
    bit 1,a
    jr z,.checkP
    ld a,(LastKey)
    cp 1
    jr z,.checkP
    call PedalStroke
    ld a,1
    ld (LastKey),a
    ret
.checkP:
    bit 0,c
    ret z
    ld a,(LastKey)
    cp 2
    ret z
    call PedalStroke
    ld a,2
    ld (LastKey),a
    ret

; One accepted pedal stroke: more speed, and the rider's legs swap
; position.
PedalStroke:
    ld a,(Speed)
    add a,PEDAL_INC
    cp MAX_SPEED+1
    jr c,.store
    ld a,MAX_SPEED
.store:
    ld (Speed),a
    ld a,(BikeFrame)
    xor 1
    ld (BikeFrame),a
    ret

ApplyFriction:
    ld hl,FrictionCounter
    ld a,(hl)
    inc a
    ld (hl),a
    and FRICTION_MASK
    ret nz
    ld a,(Speed)
    or a
    ret z
    dec a
    ld (Speed),a
    ret

; Moves BikeCol forward at a rate proportional to Speed, and updates
; BikeRow while crossing the ramp.
AdvanceBike:
    ld a,(Speed)
    or a
    ret z
    ld b,a
    ld a,(MoveTimer)
    sub b
    ld (MoveTimer),a
    ret nc
    ld a,(MoveTimer)
    add a,MOVE_THRESHOLD
    ld (MoveTimer),a
    ld a,(BikeCol)
    inc a
    ld (BikeCol),a
    jp UpdateRowForRamp

; The front wheel (BikeCol+BIKE_W-1) is what follows the ramp surface.
UpdateRowForRamp:
    ld a,(BikeCol)
    add a,BIKE_W-1
    cp RAMP_START_COL
    jr c,.flat
    cp RAMP_END_COL+1
    jr nc,.liftoff
    sub RAMP_START_COL
    ld b,a
    ld a,GROUND_ROW
    sub b
    ld (BikeRow),a
    ret
.flat:
    ld a,GROUND_ROW
    ld (BikeRow),a
    ret
.liftoff:
    ld a,LIFTOFF_ROW
    ld (BikeRow),a
    ret

; ---------------------------------------------------------------------
; Screen drawing primitives
;
; Character-cell resolution throughout (32x24 grid). All the routines
; below that take a row/col pair use B=row(0-23), C=col(0-31) and are
; guaranteed not to clobber B or C, so callers can chain calls freely.
; ---------------------------------------------------------------------

; IN: D=pixel row(0-191), E=char col(0-31). OUT: HL=screen address.
ScreenAddr:
    ld a,d
    and $c0
    rrca
    rrca
    rrca
    ld b,a
    ld a,d
    and $07
    or b
    or $40
    ld h,a
    ld a,d
    and $38
    rlca
    rlca
    or e
    ld l,a
    ret

; IN: IX=8-byte glyph, B=row, C=col.
DrawGlyph:
    ld a,b
    add a,a
    add a,a
    add a,a
    ld d,a
    ld e,c
    ld a,8
    ld (LineCount),a
.loop:
    push bc
    call ScreenAddr
    ld a,(ix+0)
    ld (hl),a
    inc ix
    pop bc
    inc d
    ld hl,LineCount
    dec (hl)
    jr nz,.loop
    ret

; IN: B=row, C=col.
ClearGlyph:
    ld a,b
    add a,a
    add a,a
    add a,a
    ld d,a
    ld e,c
    ld a,8
    ld (LineCount),a
.loop:
    push bc
    call ScreenAddr
    xor a
    ld (hl),a
    pop bc
    inc d
    ld hl,LineCount
    dec (hl)
    jr nz,.loop
    ret

; IN: B=row, C=col, A=attribute byte.
SetAttr:
    push af
    ld a,b
    ld h,0
    ld l,a
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,0
    ld e,c
    add hl,de
    ld de,ATTR_ADDR
    add hl,de
    pop af
    ld (hl),a
    ret

; Draws whatever the static scene should show at (B,C): ramp, ground,
; a person, or blank sky. Used both for the initial draw and to erase
; the bike sprite by restoring the background underneath it.
RestoreCell:
    ld a,c
    cp RAMP_START_COL
    jr c,.notRamp
    cp RAMP_END_COL+1
    jr nc,.notRamp
    ld a,c
    sub RAMP_START_COL
    ld e,a
    ld a,GROUND_ROW
    sub e
    ld e,a
    ld a,b
    cp e
    jr c,.blank
    ld ix,Ramp
    call DrawGlyph
    ld a,ATTR_RAMP
    call SetAttr
    ret
.notRamp:
    ld a,b
    cp GROUND_ROW
    jr nz,.blank
    ld a,c
    cp PEOPLE_START_COL
    jr c,.groundTile
    ld a,(NPeople)
    ld d,a
    ld a,c
    sub PEOPLE_START_COL
    cp d
    jr nc,.groundTile
    ld ix,Person
    call DrawGlyph
    ld a,ATTR_PERSON
    call SetAttr
    ret
.groundTile:
    ld ix,Ground
    call DrawGlyph
    ld a,ATTR_GROUND
    call SetAttr
    ret
.blank:
    call ClearGlyph
    ret

DrawScene:
    ld b,LIFTOFF_ROW
.rowloop:
    ld c,0
.colloop:
    call RestoreCell
    inc c
    ld a,c
    cp 32
    jr nz,.colloop
    ld a,b
    inc a
    ld b,a
    cp GROUND_ROW+1
    jr nz,.rowloop
    ret

; Multi-cell sprite. IN: IX=cell-major sprite data (8 bytes per cell,
; left to right then top to bottom), B=top row, C=left col, D=height in
; cells, E=width in cells. Cells that are entirely blank are skipped so
; the background shows through the sprite's empty corners.
DrawSprite:
    ld a,e
    ld (SprW),a
    ld a,d
    ld (SprRowsLeft),a
.rowloop:
    push bc
    ld a,(SprW)
    ld (SprColsLeft),a
.colloop:
    ld a,(ix+0)
    or (ix+1)
    or (ix+2)
    or (ix+3)
    or (ix+4)
    or (ix+5)
    or (ix+6)
    or (ix+7)
    jr z,.skip
    call DrawGlyph          ; advances IX past the cell
    ld a,ATTR_BIKE
    call SetAttr
    jr .next
.skip:
    push bc
    ld bc,8
    add ix,bc
    pop bc
.next:
    inc c
    ld hl,SprColsLeft
    dec (hl)
    jr nz,.colloop
    pop bc
    inc b
    ld hl,SprRowsLeft
    dec (hl)
    jr nz,.rowloop
    ret

; Restores the background under a sprite. IN: B=top row, C=left col,
; D=height in cells, E=width in cells.
EraseSprite:
    ld a,e
    ld (SprW),a
    ld a,d
    ld (SprRowsLeft),a
.rowloop:
    push bc
    ld a,(SprW)
    ld (SprColsLeft),a
.colloop:
    call RestoreCell
    inc c
    ld hl,SprColsLeft
    dec (hl)
    jr nz,.colloop
    pop bc
    inc b
    ld hl,SprRowsLeft
    dec (hl)
    jr nz,.rowloop
    ret

; Sets up B,C,D,E for the bike's current position (BikeRow/BikeCol is
; the bottom-left cell).
BikeBounds:
    ld a,(BikeRow)
    sub BIKE_H-1
    ld b,a
    ld a,(BikeCol)
    ld c,a
    ld d,BIKE_H
    ld e,BIKE_W
    ret

DrawBike:
    call BikeBounds
    ld ix,BikeA
    ld a,(BikeFrame)
    or a
    jr z,.draw
    ld ix,BikeB
.draw:
    jp DrawSprite

EraseBike:
    call BikeBounds
    jp EraseSprite

; ---------------------------------------------------------------------
; Text and HUD
;
; Characters are drawn from our own embedded copy of the 48K ROM font
; (MyFont, below), 8 bytes per glyph starting at char code 32. This
; avoids the ROM entirely: a raw .sna snapshot boots with system
; variables uninitialised, and this ZEsarUX build's snapshot-load also
; leaves ROM reads returning zero for the emulated CPU.
; ---------------------------------------------------------------------

; IN: A=char code, B=row, C=col.
PrintChar:
    sub 32
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,MyFont
    add hl,de
    push hl
    pop ix
    call DrawGlyph
    ld a,ATTR_HUD
    call SetAttr
    ret

; IN: HL=zero-terminated string, B=row, C=col.
PrintString:
.loop:
    ld a,(hl)
    or a
    ret z
    push hl
    call PrintChar
    pop hl
    inc hl
    inc c
    jr .loop

; IN: A=value(0-255). Writes ASCII digits to Digits+0..2.
ToDecimal3:
    ld c,0
.hloop:
    cp 100
    jr c,.hdone
    sub 100
    inc c
    jr .hloop
.hdone:
    ld b,a
    ld a,c
    add a,'0'
    ld (Digits+0),a
    ld a,b
    ld c,0
.tloop:
    cp 10
    jr c,.tdone
    sub 10
    inc c
    jr .tloop
.tdone:
    ld b,a
    ld a,c
    add a,'0'
    ld (Digits+1),a
    ld a,b
    add a,'0'
    ld (Digits+2),a
    ret

; IN: A=value, B=row, C=col.
PrintNumber3:
    push bc
    call ToDecimal3
    pop bc
    ld a,(Digits+0)
    call PrintChar
    inc c
    ld a,(Digits+1)
    call PrintChar
    inc c
    ld a,(Digits+2)
    call PrintChar
    ret

DrawHUD:
    ld hl,Str_Score
    ld b,0
    ld c,1
    call PrintString
    ld a,(Score)
    ld b,0
    ld c,8
    call PrintNumber3
    ld hl,Str_Lives
    ld b,0
    ld c,18
    call PrintString
    ld a,(Lives)
    add a,'0'
    ld b,0
    ld c,25
    call PrintChar
    ret

; ---------------------------------------------------------------------
; Keyboard
; ---------------------------------------------------------------------

; OUT: A=0 if no key is pressed, nonzero otherwise.
ReadAnyKey:
    ld hl,KeyRows
    ld b,8
    ld d,0
.loop:
    ld a,(hl)
    inc hl
    push hl
    push bc
    in a,($fe)
    and $1f
    cp $1f
    pop bc
    pop hl
    jr z,.next
    ld d,1
.next:
    djnz .loop
    ld a,d
    ret

WaitKeyRelease:
    call ReadAnyKey
    or a
    jr nz,WaitKeyRelease
    ret

WaitAnyKeyFresh:
    call WaitKeyRelease
.press:
    call ReadAnyKey
    or a
    jr z,.press
    ret

; ---------------------------------------------------------------------
; Utility
; ---------------------------------------------------------------------

ClearScreen:
    ld hl,SCREEN_ADDR
    ld de,SCREEN_ADDR+1
    ld bc,6144-1
    ld (hl),0
    ldir
    ld hl,ATTR_ADDR
    ld de,ATTR_ADDR+1
    ld bc,768-1
    ld (hl),ATTR_HUD
    ldir
    ret

Delay:
    ld b,FRAME_DELAY
.l1:
    ld c,0
.l2:
    dec c
    jr nz,.l2
    djnz .l1
    ret

DelayLong:
    ld d,8
.rep:
    call Delay
    dec d
    jr nz,.rep
    ret

; ---------------------------------------------------------------------
; Variables
; ---------------------------------------------------------------------
Score:           DB 0
Lives:           DB 0
NPeople:         DB 0
Speed:           DB 0
BikeRow:         DB 0
BikeCol:         DB 0
MoveTimer:       DB 0
LastKey:         DB 0
PrevPO:          DB 0
FrictionCounter: DB 0
JumpDistance:    DB 0
JumpStep:        DB 0
JumpRem:         DB 0
JumpFrame:       DB 0
BikeFrame:       DB 0
LineCount:       DB 0
SprW:            DB 0
SprColsLeft:     DB 0
SprRowsLeft:     DB 0
Digits:          DB 0,0,0

; ---------------------------------------------------------------------
; Font (copy of the standard 48K ROM character set, char 32 upwards,
; 8 bytes/glyph) so text rendering doesn't depend on the ROM at runtime.
; ---------------------------------------------------------------------
MyFont:
    INCBIN "src/font.bin"

; ---------------------------------------------------------------------
; Graphics data: BikeA, BikeB, Person, Ground, Ramp - generated from
; src/sprites.txt by scripts/gen_sprites.py (run by build.sh).
; ---------------------------------------------------------------------
    INCLUDE "build/sprites.asm"

; Height of the bike's bottom row above the ground on each jump frame.
JumpHeights:
    DB 4,6,7,7,6,4,2,0

KeyRows:
    DB $fe,$fd,$fb,$f7,$ef,$df,$bf,$7f

; ---------------------------------------------------------------------
; Text
; ---------------------------------------------------------------------
Str_Title:       DB "BMX RAMP JUMP",0
Str_Instr1:      DB "PEDAL WITH O AND P KEYS",0
Str_Instr2:      DB "CLEAR THE PEOPLE TO SCORE",0
Str_Instr3:      DB "PRESS ANY KEY",0
Str_Cleared:     DB "CLEARED!",0
Str_Ouch:        DB "OUCH!",0
Str_GameOver:    DB "GAME OVER",0
Str_FinalScore:  DB "FINAL SCORE:",0
Str_Score:       DB "SCORE:",0
Str_Lives:       DB "LIVES:",0

    SAVESNA "build/game.sna", Start
