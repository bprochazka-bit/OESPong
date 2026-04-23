; =============================================================
; PONG for the Owen Entertainment System
; Milestone 1: intro screen + title screen + title jingle
; Assembler: ca65
; =============================================================

; ---------------- PPU / APU / IO registers -------------------
PPU_CTRL        = $2000
PPU_MASK        = $2001
PPU_STATUS      = $2002
OAM_ADDR        = $2003
OAM_DATA        = $2004
PPU_SCROLL      = $2005
PPU_ADDR        = $2006
PPU_DATA        = $2007
OAM_DMA         = $4014
APU_STATUS      = $4015
APU_FRAME       = $4017
JOY1            = $4016
JOY2            = $4017

; ---------------- Game state IDs -----------------------------
STATE_INIT        = 0
STATE_INTRO_IN    = 1
STATE_INTRO_HOLD  = 2
STATE_INTRO_OUT   = 3
STATE_TO_TITLE    = 4
STATE_TITLE_IN    = 5
STATE_TITLE       = 6
STATE_MENU        = 7
STATE_MENU_OUT    = 8
STATE_GAME_STUB   = 9

; Controller bits (standard NES button order)
BTN_A     = $80
BTN_B     = $40
BTN_SEL   = $20
BTN_START = $10
BTN_UP    = $08
BTN_DOWN  = $04
BTN_LEFT  = $02
BTN_RIGHT = $01

; Cursor sprite Y positions (1 PLAYER row 16, 2 PLAYERS row 18).
; NES OAM Y is drawn one scanline below the stored value.
CURSOR_X        = 72
CURSOR_Y_1P     = 16*8 - 1
CURSOR_Y_2P     = 18*8 - 1

; ---------------- Zero page variables ------------------------
.segment "ZEROPAGE"
frame_counter:  .res 1
state:          .res 1
state_timer:    .res 1
pad1:           .res 1
pad1_new:       .res 1
pad1_last:      .res 1
fade_level:     .res 1      ; 0 = black .. 4 = full
ppu_ctrl_shadow:.res 1
ppu_mask_shadow:.res 1
nmi_done:       .res 1      ; toggles each NMI
music_idx:      .res 1
music_timer:    .res 1
music_on:       .res 1
menu_selection: .res 1      ; 0 = 1 PLAYER, 1 = 2 PLAYERS
player_count:   .res 1      ; 1 or 2 - committed at Start press
tmp0:           .res 1
tmp1:           .res 1
ptr:            .res 2

; ---------------- OAM page -----------------------------------
.segment "OAM"
oam_buffer:     .res 256

; ---------------- General BSS --------------------------------
.segment "BSS"
palette_target: .res 32
palette_live:   .res 32

; ---------------- iNES header --------------------------------
.segment "HEADER"
    .byte "NES", $1A
    .byte 2             ; 2 * 16 KB PRG-ROM
    .byte 1             ; 1 * 8 KB CHR-ROM
    .byte $00           ; mapper 0, horizontal mirroring
    .byte $00
    .byte 0, 0, 0, 0, 0, 0, 0, 0

; =============================================================
; CODE
; =============================================================
.segment "CODE"

; -------------------------------------------------------------
; Reset handler
; -------------------------------------------------------------
.proc reset
    sei
    cld
    ldx #$40
    stx APU_FRAME       ; disable APU frame IRQ
    ldx #$FF
    txs
    inx                 ; x = 0
    stx PPU_CTRL        ; disable NMI
    stx PPU_MASK        ; disable rendering
    stx $4010           ; disable DMC IRQ

    ; First vblank wait
    bit PPU_STATUS
:   bit PPU_STATUS
    bpl :-

    ; Clear RAM $0000-$07FF (skip OAM $0200 - we clear it right after)
    lda #$00
    tax
@clr:
    sta $0000, x
    sta $0100, x
    sta $0300, x
    sta $0400, x
    sta $0500, x
    sta $0600, x
    sta $0700, x
    inx
    bne @clr

    ; Clear OAM (all sprites off-screen)
    lda #$FF
    ldx #$00
@oam_clr:
    sta oam_buffer, x
    inx
    bne @oam_clr

    ; Second vblank wait - PPU ready
:   bit PPU_STATUS
    bpl :-

    ; Initial state
    lda #STATE_INIT
    sta state

    jsr load_intro_screen
    jsr apu_init

    ; Enable NMI + BG pattern table 0 + sprite pattern table 1
    lda #%10001000          ; NMI on, sprites=$1000, bg=$0000
    sta ppu_ctrl_shadow
    sta PPU_CTRL

    ; Enable rendering (bg + sprites, left columns shown)
    lda #%00011110
    sta ppu_mask_shadow
    sta PPU_MASK

    ; Force transition to INTRO_IN (fade in)
    lda #STATE_INTRO_IN
    sta state
    lda #0
    sta fade_level
    sta state_timer

; -------------------------------------------------------------
; Main loop - tick once per frame, synchronized via NMI
; -------------------------------------------------------------
main_loop:
    jsr wait_nmi
    jsr read_pad1
    jsr tick_state
    jsr tick_music
    jmp main_loop
.endproc

; -------------------------------------------------------------
; Wait until the NMI has run once (frame sync)
; -------------------------------------------------------------
.proc wait_nmi
    lda nmi_done
:   cmp nmi_done
    beq :-
    rts
.endproc

; -------------------------------------------------------------
; Read controller 1 into pad1 and pad1_new (pressed-this-frame)
; -------------------------------------------------------------
.proc read_pad1
    lda pad1
    sta pad1_last

    ; Strobe
    lda #$01
    sta JOY1
    lda #$00
    sta JOY1

    ldx #8
    lda #0
@loop:
    pha
    lda JOY1
    and #%00000001
    lsr a           ; carry = button state
    pla
    rol a
    dex
    bne @loop
    sta pad1

    ; Newly pressed this frame = pad1 & ~pad1_last
    lda pad1
    eor pad1_last
    and pad1
    sta pad1_new
    rts
.endproc

; -------------------------------------------------------------
; Per-frame state machine
; -------------------------------------------------------------
.proc tick_state
    inc frame_counter
    inc state_timer     ; wraps but that is OK for our uses

    lda state
    cmp #STATE_INTRO_IN
    bne :+
    jmp intro_in
:   cmp #STATE_INTRO_HOLD
    bne :+
    jmp intro_hold
:   cmp #STATE_INTRO_OUT
    bne :+
    jmp intro_out
:   cmp #STATE_TO_TITLE
    bne :+
    jmp to_title
:   cmp #STATE_TITLE_IN
    bne :+
    jmp title_in
:   cmp #STATE_TITLE
    bne :+
    jmp title
:   cmp #STATE_MENU
    bne :+
    jmp menu
:   cmp #STATE_MENU_OUT
    bne :+
    jmp menu_out
:   cmp #STATE_GAME_STUB
    bne :+
    jmp game_stub
:   rts

intro_in:
    ; fade in once every 12 frames, up to level 4
    lda frame_counter
    and #$0F
    bne :+
    lda fade_level
    cmp #4
    bcs :+
    inc fade_level
:   lda fade_level
    cmp #4
    bne :+
    ; reached full brightness - hold
    lda #STATE_INTRO_HOLD
    sta state
    lda #0
    sta state_timer
:   rts

intro_hold:
    ; hold ~2.5s at 60fps
    lda state_timer
    cmp #150
    bcc :+
    lda #STATE_INTRO_OUT
    sta state
    lda #0
    sta state_timer
:   rts

intro_out:
    lda frame_counter
    and #$0F
    bne :+
    lda fade_level
    beq :+
    dec fade_level
:   lda fade_level
    bne :+
    ; fully black -> swap screen
    lda #STATE_TO_TITLE
    sta state
:   rts

to_title:
    ; Disable rendering, swap to title nametable, re-enable
    lda #$00
    sta PPU_MASK
    jsr load_title_screen
    jsr music_start
    lda ppu_mask_shadow
    sta PPU_MASK
    lda #STATE_TITLE_IN
    sta state
    lda #0
    sta state_timer
    rts

title_in:
    lda frame_counter
    and #$0F
    bne :+
    lda fade_level
    cmp #4
    bcs :+
    inc fade_level
:   lda fade_level
    cmp #4
    bne :+
    lda #STATE_TITLE
    sta state
    lda #0
    sta state_timer
:   rts

title:
    ; Start press opens the player-select menu.
    lda pad1_new
    and #BTN_START
    beq :+
    jsr open_menu
    lda #STATE_MENU
    sta state
    lda #0
    sta state_timer
:   rts

menu:
    ; D-pad up/down toggles selection. Only act on newly-pressed edges.
    lda pad1_new
    and #(BTN_UP | BTN_DOWN)
    beq @check_start
    ; toggle 0 <-> 1
    lda menu_selection
    eor #$01
    sta menu_selection
    jsr update_cursor_sprite
@check_start:
    lda pad1_new
    and #BTN_START
    beq :+
    ; Commit: 1 PLAYER -> 1, 2 PLAYERS -> 2
    lda menu_selection
    clc
    adc #1
    sta player_count
    lda #STATE_MENU_OUT
    sta state
    lda #0
    sta state_timer
:   rts

menu_out:
    ; Fade music out in lockstep with the picture.
    lda frame_counter
    and #$0F
    bne :+
    lda fade_level
    beq :+
    dec fade_level
:   lda fade_level
    bne :+
    ; Fully black - silence APU, hide cursor, hand off to game stub.
    lda #0
    sta music_on
    sta $4000
    sta $4008
    lda #$30
    sta $4000
    lda #$FF                  ; move cursor off-screen
    sta oam_buffer + 0
    lda #STATE_GAME_STUB
    sta state
:   rts

game_stub:
    ; Milestone 3 replaces this with the play field.
    rts
.endproc

; -------------------------------------------------------------
; NMI - runs during vblank once per frame
; -------------------------------------------------------------
.proc nmi
    pha
    txa
    pha
    tya
    pha

    ; --- OAM DMA ---
    lda #$00
    sta OAM_ADDR
    lda #>oam_buffer
    sta OAM_DMA

    ; --- Recompute live palette from target + fade_level, upload ---
    jsr apply_fade
    lda #$3F
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    ldx #0
@pal_loop:
    lda palette_live, x
    sta PPU_DATA
    inx
    cpx #32
    bne @pal_loop

    ; --- Reset scroll to 0 after PPU writes ---
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL

    ; --- Re-latch PPU_CTRL (scroll reset may have clobbered) ---
    lda ppu_ctrl_shadow
    sta PPU_CTRL

    inc nmi_done

    pla
    tay
    pla
    tax
    pla
    rti
.endproc

; -------------------------------------------------------------
; IRQ - unused
; -------------------------------------------------------------
.proc irq
    rti
.endproc

; =============================================================
; Palette fade
; =============================================================
; For each of the 32 target palette entries:
;   if fade_level == 4 -> use as-is
;   else if target_hi_nibble >= (4 - fade_level) -> subtract (4-fade_level)<<4
;   else -> $0F (black)
; Entry 0 (universal bg) is always forced to $0F regardless.
.proc apply_fade
    lda #4
    sec
    sbc fade_level     ; A = 4 - fade_level  (0..4)
    asl a
    asl a
    asl a
    asl a              ; A = (4 - fade_level) * 16
    sta tmp0           ; amount to subtract

    ldx #0
@loop:
    lda palette_target, x
    cpx #0
    bne :+
    lda #$0F           ; universal bg always black
    jmp @store
:
    pha
    and #$30           ; high nibble of color row (0..3, in $00/$10/$20/$30)
    cmp tmp0
    bcs @bright        ; row >= subtract count -> darken
    pla
    lda #$0F
    jmp @store
@bright:
    pla
    sec
    sbc tmp0
@store:
    sta palette_live, x
    inx
    cpx #32
    bne @loop
    rts
.endproc

; =============================================================
; Intro screen (Owen Entertainment System Presents)
; =============================================================
.proc load_intro_screen
    ; Palette target = white text on black (all 4 bg palettes)
    ldx #0
@pal:
    lda intro_palette, x
    sta palette_target, x
    inx
    cpx #32
    bne @pal

    ; Clear nametable 0 ($2000-$23FF = 1024 bytes)
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    lda #0              ; blank tile
    ldx #4              ; 4 pages of 256 bytes
    ldy #0
@clr:
    sta PPU_DATA
    iny
    bne @clr
    dex
    bne @clr

    ; Draw line 1 at row 13 (centered): "OWEN ENTERTAINMENT SYSTEM"
    ; Row 13, col 3 -> VRAM = $2000 + 13*32 + 3 = $21A3
    lda #$21
    sta PPU_ADDR
    lda #$A3
    sta PPU_ADDR
    lda #<intro_line1
    sta ptr
    lda #>intro_line1
    sta ptr+1
    jsr write_string

    ; Draw line 2 at row 15: "PRESENTS"
    ; Row 15, col 12 -> $2000 + 15*32 + 12 = $21EC
    lda #$21
    sta PPU_ADDR
    lda #$EC
    sta PPU_ADDR
    lda #<intro_line2
    sta ptr
    lda #>intro_line2
    sta ptr+1
    jsr write_string
    rts
.endproc

; -------------------------------------------------------------
; Title screen (PONG + PRESS START)
; -------------------------------------------------------------
.proc load_title_screen
    ; Palette - each PONG letter gets its own palette entry
    ldx #0
@pal:
    lda title_palette, x
    sta palette_target, x
    inx
    cpx #32
    bne @pal

    ; Clear nametable 0
    lda #$20
    sta PPU_ADDR
    lda #$00
    sta PPU_ADDR
    lda #0
    ldx #4
    ldy #0
@clr:
    sta PPU_DATA
    iny
    bne @clr
    dex
    bne @clr

    ; Draw PONG big letters
    ; Row 10 starts at $2000 + 10*32 = $2140, col 12 -> $214C
    lda #$21
    sta PPU_ADDR
    lda #$4C
    sta PPU_ADDR
    ; P top-left, P top-right, O TL, O TR, N TL, N TR, G TL, G TR
    lda #$2A    ; P_TL
    sta PPU_DATA
    lda #$2B    ; P_TR
    sta PPU_DATA
    lda #$2E    ; O_TL
    sta PPU_DATA
    lda #$2F    ; O_TR
    sta PPU_DATA
    lda #$32    ; N_TL
    sta PPU_DATA
    lda #$33    ; N_TR
    sta PPU_DATA
    lda #$36    ; G_TL
    sta PPU_DATA
    lda #$37    ; G_TR
    sta PPU_DATA

    ; Row 11 - bottoms of each letter
    ; $2000 + 11*32 + 12 = $216C
    lda #$21
    sta PPU_ADDR
    lda #$6C
    sta PPU_ADDR
    lda #$2C    ; P_BL
    sta PPU_DATA
    lda #$2D    ; P_BR
    sta PPU_DATA
    lda #$30    ; O_BL
    sta PPU_DATA
    lda #$31    ; O_BR
    sta PPU_DATA
    lda #$34    ; N_BL
    sta PPU_DATA
    lda #$35    ; N_BR
    sta PPU_DATA
    lda #$38    ; G_BL
    sta PPU_DATA
    lda #$39    ; G_BR
    sta PPU_DATA

    ; Attribute table: give PONG letters different palettes
    ; P @ (row 10-11, col 12-13): attr byte (2,3) @ $23D3, BL quadrant (bits 4-5) -> palette 0
    ; O @ (row 10-11, col 14-15): attr byte (2,3) @ $23D3, BR quadrant (bits 6-7) -> palette 1
    ;   byte = (1 << 6) | (0 << 4) = $40
    ; N @ (row 10-11, col 16-17): attr byte (2,4) @ $23D4, BL quadrant -> palette 2
    ; G @ (row 10-11, col 18-19): attr byte (2,4) @ $23D4, BR quadrant -> palette 3
    ;   byte = (3 << 6) | (2 << 4) = $E0
    lda #$23
    sta PPU_ADDR
    lda #$D3
    sta PPU_ADDR
    lda #$40
    sta PPU_DATA    ; covers P (pal 0), O (pal 1)
    lda #$E0
    sta PPU_DATA    ; covers N (pal 2), G (pal 3)

    ; Draw "PRESS START" prompt at row 20
    ; Row 20, col 10 -> $2000 + 20*32 + 10 = $228A
    lda #$22
    sta PPU_ADDR
    lda #$8A
    sta PPU_ADDR
    lda #<press_start_text
    sta ptr
    lda #>press_start_text
    sta ptr+1
    jsr write_string
    rts
.endproc

; -------------------------------------------------------------
; Draw the player-select menu below the PONG title.
; Rendering must already be disabled by caller.
; -------------------------------------------------------------
.proc open_menu
    ; Disable rendering while we write nametable.
    lda #$00
    sta PPU_MASK

    ; Row 16, col 12: "1 PLAYER"
    lda #$22
    sta PPU_ADDR
    lda #$0C
    sta PPU_ADDR
    lda #<menu_1p_text
    sta ptr
    lda #>menu_1p_text
    sta ptr+1
    jsr write_string

    ; Row 18, col 11: "2 PLAYERS"
    lda #$22
    sta PPU_ADDR
    lda #$4B
    sta PPU_ADDR
    lda #<menu_2p_text
    sta ptr
    lda #>menu_2p_text
    sta ptr+1
    jsr write_string

    ; Clear PRESS START prompt (row 20, col 10, 11 tiles)
    lda #$22
    sta PPU_ADDR
    lda #$8A
    sta PPU_ADDR
    ldx #11
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    ; Reset scroll + restore CTRL since our writes clobber PPU latches.
    lda #$00
    sta PPU_SCROLL
    sta PPU_SCROLL
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda ppu_mask_shadow
    sta PPU_MASK

    ; Install cursor sprite (OAM slot 0).
    lda #0
    sta menu_selection
    jsr update_cursor_sprite
    rts
.endproc

; -------------------------------------------------------------
; Position the cursor sprite (OAM slot 0) based on menu_selection.
; -------------------------------------------------------------
.proc update_cursor_sprite
    ; Y
    lda menu_selection
    beq @pos_1p
    lda #CURSOR_Y_2P
    jmp @setY
@pos_1p:
    lda #CURSOR_Y_1P
@setY:
    sta oam_buffer + 0
    lda #$03                ; tile index = arrow (sprite pattern table)
    sta oam_buffer + 1
    lda #$00                ; attr: palette 0 (red), no flip, in front
    sta oam_buffer + 2
    lda #CURSOR_X
    sta oam_buffer + 3
    rts
.endproc

; -------------------------------------------------------------
; Write the zero-terminated string at (ptr) to PPU_DATA.
; Characters use glyph table offset map.
; -------------------------------------------------------------
.proc write_string
    ldy #0
@loop:
    lda (ptr), y
    beq @done
    jsr char_to_tile
    sta PPU_DATA
    iny
    bne @loop
@done:
    rts
.endproc

; -------------------------------------------------------------
; char_to_tile: map ASCII in A -> CHR tile index in A.
; A-Z -> $01..$1A,   0-9 -> $1B..$24,
; ' ' -> $00,  ':' -> $25, '-' -> $26, '.' -> $27, '!' -> $28
; -------------------------------------------------------------
.proc char_to_tile
    cmp #' '
    bne :+
    lda #$00
    rts
:   cmp #'A'
    bcc @nonalpha
    cmp #'Z'+1
    bcs @nonalpha
    sec
    sbc #'A'-1          ; 'A' -> $01
    rts
@nonalpha:
    cmp #'0'
    bcc @punct
    cmp #'9'+1
    bcs @punct
    sec
    sbc #'0'-$1B        ; '0' -> $1B
    rts
@punct:
    cmp #':'
    bne :+
    lda #$25
    rts
:   cmp #'-'
    bne :+
    lda #$26
    rts
:   cmp #'.'
    bne :+
    lda #$27
    rts
:   cmp #'!'
    bne :+
    lda #$28
    rts
:   lda #$00            ; unknown -> blank
    rts
.endproc

; =============================================================
; APU / music
; =============================================================
.proc apu_init
    lda #$0F
    sta APU_STATUS      ; enable pulse1, pulse2, tri, noise
    lda #$00
    sta $4000
    sta $4001
    sta $4002
    sta $4003
    sta $4004
    sta $4005
    sta $4006
    sta $4007
    sta $4008
    sta $4009
    sta $400A
    sta $400B
    rts
.endproc

.proc music_start
    lda #1
    sta music_on
    lda #0
    sta music_idx
    sta music_timer
    rts
.endproc

; Simple 8-note looping jingle on pulse1 + bass triangle on the downbeat.
.proc tick_music
    lda music_on
    bne :+
    rts
:
    dec music_timer
    bne @done

    ; Next note
    ldx music_idx
    lda music_note_lo, x
    sta $4002
    lda music_note_hi, x
    sta $4003

    ; Duty 50%, constant vol 10, no length counter
    lda #%10111010
    sta $4000
    lda #$00
    sta $4001

    ; Every 4th note, retrigger triangle bass
    txa
    and #$03
    bne @no_bass
    lda #$C0            ; linear counter reload, halt
    sta $4008
    lda #$FD            ; triangle period lo (low bass)
    sta $400A
    lda #$01
    sta $400B
@no_bass:

    lda #20             ; note duration in frames
    sta music_timer

    inx
    cpx #8
    bcc :+
    ldx #0
:   stx music_idx
@done:
    rts
.endproc

; =============================================================
; Read-only data
; =============================================================
.segment "RODATA"

; Intro palette: white on black for all 4 BG palettes
intro_palette:
    .byte $0F, $30, $30, $30    ; bg pal 0
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30    ; sprite palettes (unused here)
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30

; Title palette: each PONG letter gets its own vivid color
;  pal 0 -> P = red, pal 1 -> O = yellow,
;  pal 2 -> N = green, pal 3 -> G = cyan.
; "PRESS START" uses pal 0 (red) since its attribute region defaults to 0.
title_palette:
    .byte $0F, $16, $30, $30    ; 0: red
    .byte $0F, $28, $30, $30    ; 1: yellow
    .byte $0F, $2A, $30, $30    ; 2: green
    .byte $0F, $2C, $30, $30    ; 3: cyan
    .byte $0F, $16, $30, $30    ; sprite palettes
    .byte $0F, $21, $30, $30
    .byte $0F, $2A, $30, $30
    .byte $0F, $2C, $30, $30

intro_line1:
    .byte "OWEN ENTERTAINMENT SYSTEM", 0
intro_line2:
    .byte "PRESENTS", 0
press_start_text:
    .byte "PRESS START", 0
menu_1p_text:
    .byte "1 PLAYER", 0
menu_2p_text:
    .byte "2 PLAYERS", 0

; APU note periods: C4, E4, G4, C5, G4, E4, C4, rest
music_note_lo:
    .byte <426, <338, <284, <212, <284, <338, <426, <0
music_note_hi:
    .byte >426, >338, >284, >212, >284, >338, >426, >0

; =============================================================
; CHR-ROM
; =============================================================
.segment "CHARS"
    .incbin "chr.bin"

; =============================================================
; Interrupt vectors
; =============================================================
.segment "VECTORS"
    .word nmi
    .word reset
    .word irq
