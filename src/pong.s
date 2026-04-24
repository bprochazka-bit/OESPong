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
STATE_DIFFICULTY  = 12
STATE_MENU_OUT    = 8
STATE_TO_GAME     = 9
STATE_GAME_IN     = 10
STATE_GAME        = 11
STATE_GAME_OVER   = 13
STATE_PAUSE       = 14
STATE_TO_TITLE_FADE = 15       ; fade current field down before returning home

; Controller bits (standard NES button order)
BTN_A     = $80
BTN_B     = $40
BTN_SEL   = $20
BTN_START = $10
BTN_UP    = $08
BTN_DOWN  = $04
BTN_LEFT  = $02
BTN_RIGHT = $01

; Menu layout - both options start at the same column so they line up,
; arrow sprite sits two tiles to the left of the text with a one-tile gap.
MENU_TEXT_COL   = 13
CURSOR_X        = 11*8
CURSOR_Y_1P     = 16*8 - 1
CURSOR_Y_2P     = 18*8 - 1

; Play-field layout
PADDLE_TILES    = 4             ; 8*4 = 32 pixels tall
PADDLE_H        = PADDLE_TILES*8
P1_X            = 8             ; left paddle column (pixel X)
P2_X            = 240           ; right paddle column
P1_RIGHT        = P1_X + 8      ; ball reflects when ball_x <= P1_RIGHT
P2_LEFT         = P2_X          ; ball reflects when ball_x >= P2_LEFT
PADDLE_MIN_Y    = 16            ; top of playfield (below scoreboard)
PADDLE_MAX_Y    = 240 - PADDLE_H
PADDLE_START_Y  = 104           ; roughly vertical centre
PADDLE_SPEED    = 2             ; pixels per frame

; Ball
BALL_TOP        = 16
BALL_BOTTOM     = 232
BALL_VX_BASE    = 2             ; starting magnitude of ball_vx
BALL_VX_MAX     = 4             ; cap as rally speeds up
BALL_VY_MAX     = 3             ; clamp for |ball_vy|
WIN_SCORE       = 3

; Sprite OAM slot assignments
OAM_CURSOR      = 0
OAM_P1          = 1             ; 4 slots: 1..4
OAM_P2          = 5             ; 4 slots: 5..8
OAM_BALL        = 9

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
p1_y:           .res 1      ; top-left Y of P1 paddle (pixels)
p2_y:           .res 1      ; top-left Y of P2 paddle (pixels)
p1_score:       .res 1
p2_score:       .res 1
pad2:           .res 1
pad2_new:       .res 1
pad2_last:      .res 1
ball_x:         .res 1      ; pixel position
ball_y:         .res 1
ball_vx:        .res 1      ; signed pixels/frame
ball_vy:        .res 1      ; signed pixels/frame
ball_on_paddle: .res 1      ; 1 = ball stuck to P1 paddle
vram_hi:        .res 1      ; single-tile VRAM update slot
vram_lo:        .res 1
vram_val:       .res 1
vram_pending:   .res 1
pending_p2_reset:.res 1      ; queue a "P2 = 0" write on the next frame
winner:         .res 1      ; 1 or 2 - whoever triggered STATE_GAME_OVER
difficulty_sel: .res 1      ; 0 = EASY, 1 = NORMAL, 2 = HARD
ai_period:      .res 1      ; frames between AI moves (1 = every frame)
ai_step:        .res 1      ; pixels per AI move
ai_tick:        .res 1      ; counter vs ai_period
pause_sel:      .res 1      ; 0 = RESUME, 1 = EXIT
ball_speed:     .res 1      ; |ball_vx|, grows during a rally
sfx_timer:      .res 1      ; frames remaining on the current Pulse 2 SFX
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
    jsr music_start           ; start jingle immediately on boot

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
    jsr read_pads
    jsr tick_state
    jsr tick_music
    jsr tick_sfx
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
; Read both controllers. The $4016 strobe resets both shift
; registers; we then read JOY1 8 times then JOY2 8 times.
; -------------------------------------------------------------
.proc read_pads
    lda pad1
    sta pad1_last
    lda pad2
    sta pad2_last

    ; Strobe
    lda #$01
    sta JOY1
    lda #$00
    sta JOY1

    ldx #8
    lda #0
@l1:
    pha
    lda JOY1
    and #%00000001
    lsr a           ; carry = button state
    pla
    rol a
    dex
    bne @l1
    sta pad1

    ldx #8
    lda #0
@l2:
    pha
    lda JOY2
    and #%00000001
    lsr a
    pla
    rol a
    dex
    bne @l2
    sta pad2

    ; Newly pressed this frame = pad & ~pad_last
    lda pad1
    eor pad1_last
    and pad1
    sta pad1_new
    lda pad2
    eor pad2_last
    and pad2
    sta pad2_new
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
:   cmp #STATE_TO_GAME
    bne :+
    jmp to_game
:   cmp #STATE_GAME_IN
    bne :+
    jmp game_in
:   cmp #STATE_GAME
    bne :+
    jmp game
:   cmp #STATE_DIFFICULTY
    bne :+
    jmp difficulty
:   cmp #STATE_GAME_OVER
    bne :+
    jmp game_over
:   cmp #STATE_PAUSE
    bne :+
    jmp pause
:   cmp #STATE_TO_TITLE_FADE
    bne :+
    jmp to_title_fade
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
    ; Disable rendering, swap to title nametable, re-enable.
    ; (music already playing since reset - don't restart it here)
    lda #$00
    sta PPU_MASK
    jsr load_title_screen
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
    cmp #1
    bne @skip_diff
    ; 1P mode: stop at difficulty menu first
    jsr open_difficulty_menu
    lda #STATE_DIFFICULTY
    sta state
    lda #0
    sta state_timer
    rts
@skip_diff:
    jsr apply_difficulty            ; 2P: irrelevant, load NORMAL as default
    lda #STATE_MENU_OUT
    sta state
    lda #0
    sta state_timer
:   rts

; -------------------------------------------------------------
; Difficulty selection menu (only shown for 1P mode)
; -------------------------------------------------------------
difficulty:
    lda pad1_new
    and #BTN_UP
    beq @check_down
    lda difficulty_sel
    beq @check_down
    dec difficulty_sel
    jsr update_diff_cursor
    jmp @check_start
@check_down:
    lda pad1_new
    and #BTN_DOWN
    beq @check_start
    lda difficulty_sel
    cmp #2
    bcs @check_start
    inc difficulty_sel
    jsr update_diff_cursor
@check_start:
    lda pad1_new
    and #BTN_START
    beq :+
    jsr apply_difficulty
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
    ; Fully black - silence APU, hide cursor, hand off to play field.
    lda #0
    sta music_on
    sta $4000
    sta $4008
    lda #$30
    sta $4000
    lda #$FF                  ; move cursor off-screen
    sta oam_buffer + 0
    lda #STATE_TO_GAME
    sta state
:   rts

to_game:
    ; Build the play field while the screen is already black.
    lda #$00
    sta PPU_MASK
    jsr load_game_screen
    lda ppu_mask_shadow
    sta PPU_MASK
    lda #STATE_GAME_IN
    sta state
    lda #0
    sta state_timer
    rts

game_in:
    ; Fade the play field in, then release control to the user.
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
    lda #STATE_GAME
    sta state
    lda #0
    sta state_timer
:   rts

game:
    ; Start opens the pause menu.
    lda pad1_new
    and #BTN_START
    beq @no_pause
    jsr open_pause_menu
    lda #STATE_PAUSE
    sta state
    lda #0
    sta state_timer
    rts
@no_pause:
    ; Drain a deferred "P2 score = 0" from last frame's game-over.
    lda pending_p2_reset
    beq :+
    jsr push_p2_score
    lda #0
    sta pending_p2_reset
:
    jsr move_paddle_p1
    lda player_count
    cmp #2
    bne :+
    jsr move_paddle_p2
    jmp @ball
:   jsr ai_paddle_p2
@ball:
    lda ball_on_paddle
    beq :+
    jsr ball_follow_p1
    lda pad1_new
    and #BTN_A
    beq @done
    jsr ball_release
    jmp @done
:   jsr ball_tick
@done:
    rts

; -------------------------------------------------------------
; Game-over banner: hold for ~3s showing "PX WINS!" then reset.
; -------------------------------------------------------------
game_over:
    lda state_timer
    cmp #180
    bcc :+
    ; 3s elapsed - reset scores, clear banner, back to play.
    jsr close_game_over_banner
    lda #0
    sta p1_score
    sta p2_score
    jsr push_p1_score
    lda #1
    sta pending_p2_reset
    jsr ball_reset_on_paddle
    lda #STATE_GAME
    sta state
    lda #0
    sta state_timer
:   rts

; -------------------------------------------------------------
; Pause: Resume / Exit menu on top of the frozen play field.
; -------------------------------------------------------------
pause:
    lda pad1_new
    and #(BTN_UP | BTN_DOWN)
    beq @check_confirm
    lda pause_sel
    eor #$01
    sta pause_sel
    jsr update_pause_cursor
@check_confirm:
    lda pad1_new
    and #(BTN_START | BTN_A)
    beq :+
    lda pause_sel
    bne @exit
    ; RESUME
    jsr close_pause_menu
    lda #STATE_GAME
    sta state
    lda #0
    sta state_timer
    rts
@exit:
    ; EXIT -> fade down the field then go back to title.
    jsr close_pause_menu
    lda #STATE_TO_TITLE_FADE
    sta state
    lda #0
    sta state_timer
:   rts

; -------------------------------------------------------------
; Fade the play field out, then swap back to the title screen.
; -------------------------------------------------------------
to_title_fade:
    lda frame_counter
    and #$0F
    bne :+
    lda fade_level
    beq :+
    dec fade_level
:   lda fade_level
    bne :+
    ; Fully black - hide all play-field sprites, swap to title.
    ldx #0
    lda #$FF
@hide_oam:
    sta oam_buffer, x
    inx
    bne @hide_oam
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
:   rts
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

    ; --- Single-tile VRAM update (drained once per frame) ---
    lda vram_pending
    beq @no_vram
    lda vram_hi
    sta PPU_ADDR
    lda vram_lo
    sta PPU_ADDR
    lda vram_val
    sta PPU_DATA
    lda #0
    sta vram_pending
@no_vram:

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

    ; --- Scroll reset: point v back to nametable start ---
    ; Write PPU_ADDR = $0000 which forces both t and v registers
    ; to a clean state before final scroll writes.
    bit PPU_STATUS           ; w latch -> 0
    lda #$00
    sta PPU_ADDR             ; t hi = 0, w -> 1
    sta PPU_ADDR             ; v = t = $0000, w -> 0
    ; Now program nametable via CTRL and scroll X/Y
    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0

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

    ; Row 16, col 13: "1 PLAYER"  ($2000 + 16*32 + 13 = $220D)
    lda #$22
    sta PPU_ADDR
    lda #$0D
    sta PPU_ADDR
    lda #<menu_1p_text
    sta ptr
    lda #>menu_1p_text
    sta ptr+1
    jsr write_string

    ; Row 18, col 13: "2 PLAYERS" ($2000 + 18*32 + 13 = $224D)
    lda #$22
    sta PPU_ADDR
    lda #$4D
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
    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
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

; =============================================================
; Difficulty select, pause, and game-over banner helpers
; =============================================================

; Erase the 1P/2P menu text and write EASY/NORMAL/HARD options.
.proc open_difficulty_menu
    lda #$00
    sta PPU_MASK

    ; Clear row 16 cols 13-21 (old "1 PLAYER" plus a little)
    lda #$22
    sta PPU_ADDR
    lda #$0D
    sta PPU_ADDR
    ldx #10
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    ; Clear row 18 cols 13-22
    lda #$22
    sta PPU_ADDR
    lda #$4D
    sta PPU_ADDR
    ldx #10
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    ; "EASY"   at row 14, col 14  ($2000 + 14*32 + 14 = $21CE)
    lda #$21
    sta PPU_ADDR
    lda #$CE
    sta PPU_ADDR
    lda #<diff_easy_text
    sta ptr
    lda #>diff_easy_text
    sta ptr+1
    jsr write_string

    ; "NORMAL" at row 16, col 13  ($220D)
    lda #$22
    sta PPU_ADDR
    lda #$0D
    sta PPU_ADDR
    lda #<diff_normal_text
    sta ptr
    lda #>diff_normal_text
    sta ptr+1
    jsr write_string

    ; "HARD"   at row 18, col 14  ($224E)
    lda #$22
    sta PPU_ADDR
    lda #$4E
    sta PPU_ADDR
    lda #<diff_hard_text
    sta ptr
    lda #>diff_hard_text
    sta ptr+1
    jsr write_string

    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
    lda ppu_mask_shadow
    sta PPU_MASK

    lda #1                      ; default NORMAL
    sta difficulty_sel
    jsr update_diff_cursor
    rts
.endproc

; Place cursor sprite to point at the currently selected difficulty.
.proc update_diff_cursor
    lda difficulty_sel
    beq @easy
    cmp #1
    beq @normal
    ; HARD
    lda #18*8 - 1
    jmp @set
@easy:
    lda #14*8 - 1
    jmp @set
@normal:
    lda #16*8 - 1
@set:
    sta oam_buffer + 0
    lda #$03
    sta oam_buffer + 1
    lda #$00
    sta oam_buffer + 2
    lda #CURSOR_X
    sta oam_buffer + 3
    rts
.endproc

; Load AI parameters from difficulty_sel. Called when Start is
; pressed on either the difficulty menu or the main menu (2P mode
; picks defaults here too).
.proc apply_difficulty
    lda #0
    sta ai_tick
    lda difficulty_sel
    beq @easy
    cmp #2
    beq @hard
    ; NORMAL: AI moves once every 3 frames, 1 px per move
    lda #3
    sta ai_period
    lda #1
    sta ai_step
    rts
@easy:
    ; EASY: once every 4 frames, 1 px
    lda #4
    sta ai_period
    lda #1
    sta ai_step
    rts
@hard:
    ; HARD: every other frame, 2 px
    lda #2
    sta ai_period
    lda #2
    sta ai_step
    rts
.endproc

; -------------------------------------------------------------
; Pause menu
; -------------------------------------------------------------
.proc open_pause_menu
    lda #$00
    sta PPU_MASK

    ; "PAUSED" at row 12, col 13 ($218D)
    lda #$21
    sta PPU_ADDR
    lda #$8D
    sta PPU_ADDR
    lda #<pause_title_text
    sta ptr
    lda #>pause_title_text
    sta ptr+1
    jsr write_string

    ; "RESUME" at row 16, col 13 ($220D)
    lda #$22
    sta PPU_ADDR
    lda #$0D
    sta PPU_ADDR
    lda #<pause_resume_text
    sta ptr
    lda #>pause_resume_text
    sta ptr+1
    jsr write_string

    ; "EXIT" at row 18, col 13 ($224D)
    lda #$22
    sta PPU_ADDR
    lda #$4D
    sta PPU_ADDR
    lda #<pause_exit_text
    sta ptr
    lda #>pause_exit_text
    sta ptr+1
    jsr write_string

    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
    lda ppu_mask_shadow
    sta PPU_MASK

    ; Hide the ball sprite while paused.
    lda #$FF
    sta oam_buffer + OAM_BALL * 4 + 0

    lda #0
    sta pause_sel
    jsr update_pause_cursor
    rts
.endproc

; Clear the pause menu tiles and hide its cursor.
.proc close_pause_menu
    lda #$00
    sta PPU_MASK

    ; Row 12, col 13-18 (6 tiles)
    lda #$21
    sta PPU_ADDR
    lda #$8D
    sta PPU_ADDR
    ldx #6
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    ; Row 16, col 13-18
    lda #$22
    sta PPU_ADDR
    lda #$0D
    sta PPU_ADDR
    ldx #6
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    ; Row 18, col 13-18
    lda #$22
    sta PPU_ADDR
    lda #$4D
    sta PPU_ADDR
    ldx #6
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
    lda ppu_mask_shadow
    sta PPU_MASK

    ; Hide cursor and bring the ball back.
    lda #$FF
    sta oam_buffer + 0
    jsr refresh_ball
    rts
.endproc

.proc update_pause_cursor
    lda pause_sel
    beq @top
    lda #CURSOR_Y_2P
    jmp @set
@top:
    lda #CURSOR_Y_1P
@set:
    sta oam_buffer + 0
    lda #$03
    sta oam_buffer + 1
    lda #$00
    sta oam_buffer + 2
    lda #CURSOR_X
    sta oam_buffer + 3
    rts
.endproc

; -------------------------------------------------------------
; Game-over banner ("P1 WINS!" / "P2 WINS!") at row 14, col 12
; -------------------------------------------------------------
.proc open_game_over_banner
    lda #$00
    sta PPU_MASK

    lda #$21
    sta PPU_ADDR
    lda #$CC                    ; 14*32 + 12 = $1CC
    sta PPU_ADDR

    lda winner
    cmp #1
    bne @p2
    lda #<go_p1_text
    sta ptr
    lda #>go_p1_text
    sta ptr+1
    jmp @write
@p2:
    lda #<go_p2_text
    sta ptr
    lda #>go_p2_text
    sta ptr+1
@write:
    jsr write_string

    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
    lda ppu_mask_shadow
    sta PPU_MASK
    rts
.endproc

.proc close_game_over_banner
    lda #$00
    sta PPU_MASK

    lda #$21
    sta PPU_ADDR
    lda #$CC
    sta PPU_ADDR
    ldx #8
    lda #0
:   sta PPU_DATA
    dex
    bne :-

    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0
    lda ppu_mask_shadow
    sta PPU_MASK
    rts
.endproc

; =============================================================
; Play field (milestone 3)
; =============================================================
.proc load_game_screen
    ; Load game palette target.
    ldx #0
@pal:
    lda game_palette, x
    sta palette_target, x
    inx
    cpx #32
    bne @pal

    ; Clear nametable 0.
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

    ; Scoreboard tiles at row 2, cols 10 and 21 (symmetric around centre).
    ; VRAM = $2000 + 2*32 + 10 = $204A
    lda #$20
    sta PPU_ADDR
    lda #$4A
    sta PPU_ADDR
    lda #$1B                  ; glyph '0'
    sta PPU_DATA

    ; VRAM = $2000 + 2*32 + 21 = $2055
    lda #$20
    sta PPU_ADDR
    lda #$55
    sta PPU_ADDR
    lda #$1B
    sta PPU_DATA

    ; Reset scroll and CTRL after direct VRAM writes.
    bit PPU_STATUS
    lda #$00
    sta PPU_ADDR
    sta PPU_ADDR
    lda ppu_ctrl_shadow
    sta PPU_CTRL
    lda #$00
    sta PPU_SCROLL           ; X = 0
    sta PPU_SCROLL           ; Y = 0

    ; Reset game state variables.
    lda #PADDLE_START_Y
    sta p1_y
    sta p2_y
    lda #0
    sta p1_score
    sta p2_score

    jsr refresh_paddles
    jsr ball_reset_on_paddle
    rts
.endproc

; -------------------------------------------------------------
; Write the 4+4 paddle sprites to OAM from p1_y / p2_y.
; -------------------------------------------------------------
.proc refresh_paddles
    ; --- P1 (red, sprite palette 0) ---
    lda p1_y
    sta tmp0
    ldx #0
@p1:
    txa
    asl a
    asl a
    clc
    adc #(OAM_P1 * 4)
    tay
    lda tmp0
    sta oam_buffer, y         ; Y
    iny
    lda #$01                  ; tile = solid 8x8
    sta oam_buffer, y
    iny
    lda #%00000000            ; attr: sprite palette 0 (red)
    sta oam_buffer, y
    iny
    lda #P1_X
    sta oam_buffer, y
    lda tmp0
    clc
    adc #8
    sta tmp0
    inx
    cpx #PADDLE_TILES
    bne @p1

    ; --- P2 (blue, sprite palette 1) ---
    lda p2_y
    sta tmp0
    ldx #0
@p2:
    txa
    asl a
    asl a
    clc
    adc #(OAM_P2 * 4)
    tay
    lda tmp0
    sta oam_buffer, y
    iny
    lda #$01
    sta oam_buffer, y
    iny
    lda #%00000001            ; attr: sprite palette 1 (blue)
    sta oam_buffer, y
    iny
    lda #P2_X
    sta oam_buffer, y
    lda tmp0
    clc
    adc #8
    sta tmp0
    inx
    cpx #PADDLE_TILES
    bne @p2
    rts
.endproc

; -------------------------------------------------------------
; Move P1 paddle from controller 1 input with clamping.
; -------------------------------------------------------------
.proc move_paddle_p1
    lda pad1
    and #BTN_UP
    beq @down
    lda p1_y
    sec
    sbc #PADDLE_SPEED
    bcc @clamp_top
    cmp #PADDLE_MIN_Y
    bcs @save
@clamp_top:
    lda #PADDLE_MIN_Y
    jmp @save
@down:
    lda pad1
    and #BTN_DOWN
    beq @refresh
    lda p1_y
    clc
    adc #PADDLE_SPEED
    bcs @clamp_bot
    cmp #PADDLE_MAX_Y+1
    bcc @save
@clamp_bot:
    lda #PADDLE_MAX_Y
@save:
    sta p1_y
@refresh:
    jsr refresh_paddles
    rts
.endproc

; -------------------------------------------------------------
; Move P2 paddle from controller 2 input with clamping.
; -------------------------------------------------------------
.proc move_paddle_p2
    lda pad2
    and #BTN_UP
    beq @down
    lda p2_y
    sec
    sbc #PADDLE_SPEED
    bcc @clamp_top
    cmp #PADDLE_MIN_Y
    bcs @save
@clamp_top:
    lda #PADDLE_MIN_Y
    jmp @save
@down:
    lda pad2
    and #BTN_DOWN
    beq @refresh
    lda p2_y
    clc
    adc #PADDLE_SPEED
    bcs @clamp_bot
    cmp #PADDLE_MAX_Y+1
    bcc @save
@clamp_bot:
    lda #PADDLE_MAX_Y
@save:
    sta p2_y
@refresh:
    jsr refresh_paddles
    rts
.endproc

; =============================================================
; Ball
; =============================================================
; Reset ball onto P1 paddle; caller should have set p1_y already.
.proc ball_reset_on_paddle
    lda #1
    sta ball_on_paddle
    lda #0
    sta ball_vx
    sta ball_vy
    lda #BALL_VX_BASE         ; rally speed resets on serve
    sta ball_speed
    ; sit ball one pixel right of P1 paddle
    lda #P1_X + 10
    sta ball_x
    lda p1_y
    clc
    adc #(PADDLE_H/2 - 4)     ; vertical centre of paddle
    sta ball_y
    jsr refresh_ball
    rts
.endproc

; Stick ball to the P1 paddle every frame while ball_on_paddle is set.
.proc ball_follow_p1
    lda p1_y
    clc
    adc #(PADDLE_H/2 - 4)
    sta ball_y
    jsr refresh_ball
    rts
.endproc

; Write ball sprite (OAM slot 9) from ball_x/ball_y.
.proc refresh_ball
    lda ball_y
    sta oam_buffer + OAM_BALL * 4 + 0
    lda #$02                     ; tile = centred dot
    sta oam_buffer + OAM_BALL * 4 + 1
    lda #%00000010               ; sprite palette 2 (white)
    sta oam_buffer + OAM_BALL * 4 + 2
    lda ball_x
    sta oam_buffer + OAM_BALL * 4 + 3
    rts
.endproc

; Launch the ball from P1 paddle. Direction = right; vertical
; component comes from whichever D-pad bit pad1 currently holds.
.proc ball_release
    lda #0
    sta ball_on_paddle
    lda ball_speed
    sta ball_vx
    lda pad1
    and #BTN_UP
    beq @not_up
    lda #<-1              ; ball_vy = -1 (upward)
    sta ball_vy
    rts
@not_up:
    lda pad1
    and #BTN_DOWN
    beq @flat
    lda #1
    sta ball_vy
    rts
@flat:
    lda #0
    sta ball_vy
    rts
.endproc

; -------------------------------------------------------------
; Queue a single-tile VRAM write. A = tile; hi/lo passed in tmp0/tmp1.
; -------------------------------------------------------------
.proc queue_vram
    sta vram_val
    lda tmp0
    sta vram_hi
    lda tmp1
    sta vram_lo
    lda #1
    sta vram_pending
    rts
.endproc

; Update P1 score tile at row 2, col 10 ($204A).
.proc push_p1_score
    lda #$20
    sta tmp0
    lda #$4A
    sta tmp1
    lda p1_score
    clc
    adc #$1B              ; tile for '0'
    jmp queue_vram
.endproc

; Update P2 score tile at row 2, col 21 ($2055).
.proc push_p2_score
    lda #$20
    sta tmp0
    lda #$55
    sta tmp1
    lda p2_score
    clc
    adc #$1B
    jmp queue_vram
.endproc

; Clamp paddle Y in A to [PADDLE_MIN_Y, PADDLE_MAX_Y]; returns in A.
.proc clamp_paddle_y
    cmp #PADDLE_MIN_Y
    bcs :+
    lda #PADDLE_MIN_Y
    rts
:   cmp #PADDLE_MAX_Y+1
    bcc :+
    lda #PADDLE_MAX_Y
:   rts
.endproc

; Clamp ball_vy to [-BALL_VY_MAX, +BALL_VY_MAX] (treats A as signed).
.proc clamp_ball_vy
    lda ball_vy
    bmi @neg
    cmp #BALL_VY_MAX+1
    bcc @done
    lda #BALL_VY_MAX
    sta ball_vy
    rts
@neg:
    cmp #<-BALL_VY_MAX
    bcs @done
    lda #<-BALL_VY_MAX
    sta ball_vy
@done:
    rts
.endproc

; -------------------------------------------------------------
; Ball per-frame update while it is in flight.
; -------------------------------------------------------------
.proc ball_tick
    ; ball_x += ball_vx  (ball_vx is signed two's-complement)
    clc
    lda ball_x
    adc ball_vx
    sta ball_x

    ; ball_y += ball_vy
    clc
    lda ball_y
    adc ball_vy
    sta ball_y

    ; Top wall
    lda ball_y
    cmp #BALL_TOP
    bcs @not_top
    lda #BALL_TOP
    sta ball_y
    lda #0
    sec
    sbc ball_vy
    sta ball_vy
@not_top:

    ; Bottom wall
    lda ball_y
    cmp #BALL_BOTTOM+1
    bcc @not_bot
    lda #BALL_BOTTOM
    sta ball_y
    lda #0
    sec
    sbc ball_vy
    sta ball_vy
@not_bot:

    ; Horizontal: paddle reflect vs score
    lda ball_vx
    bpl @right

    ; --- Moving left: test P1 paddle ---
    lda ball_x
    cmp #P1_RIGHT+1
    bcs @check_score_left
    ; within P1 X column - check Y overlap
    lda ball_y
    cmp p1_y
    bcc @miss_p1
    sec
    sbc p1_y
    cmp #PADDLE_H
    bcs @miss_p1
    ; Hit P1: reflect to positive vx with rally speedup.
    lda ball_speed
    cmp #BALL_VX_MAX
    bcs :+
    inc ball_speed
:   lda ball_speed
    sta ball_vx
    lda pad1
    and #BTN_UP
    beq :+
    dec ball_vy
:   lda pad1
    and #BTN_DOWN
    beq :+
    inc ball_vy
:   jsr clamp_ball_vy
    jsr sfx_play_paddle
    ; nudge ball just right of paddle so we do not re-hit next frame
    lda #P1_RIGHT+1
    sta ball_x
    jmp @done
@miss_p1:
    ; Still in the paddle lane but not intersecting; don't score yet.
@check_score_left:
    lda ball_x
    cmp #4
    bcs @done
    ; Ball off left - P2 scores.
    inc p2_score
    jsr push_p2_score
    jsr sfx_play_score
    jsr check_game_over
    jsr ball_reset_on_paddle
    jmp @done

@right:
    ; --- Moving right: test P2 paddle ---
    lda ball_x
    cmp #P2_LEFT
    bcc @check_score_right
    lda ball_y
    cmp p2_y
    bcc @miss_p2
    sec
    sbc p2_y
    cmp #PADDLE_H
    bcs @miss_p2
    ; Hit P2: reflect to negative vx with rally speedup. In 1P mode
    ; pad2 has no buttons set, so the CPU hit imparts no spin -
    ; good enough for a first cut.
    lda ball_speed
    cmp #BALL_VX_MAX
    bcs :+
    inc ball_speed
:   lda #0
    sec
    sbc ball_speed
    sta ball_vx
    lda pad2
    and #BTN_UP
    beq :+
    dec ball_vy
:   lda pad2
    and #BTN_DOWN
    beq :+
    inc ball_vy
:   jsr clamp_ball_vy
    jsr sfx_play_paddle
    lda #P2_LEFT-1
    sta ball_x
    jmp @done
@miss_p2:
@check_score_right:
    lda ball_x
    cmp #252
    bcc @done
    inc p1_score
    jsr push_p1_score
    jsr sfx_play_score
    jsr check_game_over
    jsr ball_reset_on_paddle

@done:
    jsr refresh_ball
    rts
.endproc

; -------------------------------------------------------------
; If either score reaches WIN_SCORE, transition to STATE_GAME_OVER
; (banner + 3s delay). Actual reset happens when that state ends.
; -------------------------------------------------------------
.proc check_game_over
    lda p1_score
    cmp #WIN_SCORE
    bcs @win_p1
    lda p2_score
    cmp #WIN_SCORE
    bcs @win_p2
    rts
@win_p1:
    lda #1
    sta winner
    jmp @enter
@win_p2:
    lda #2
    sta winner
@enter:
    jsr sfx_play_gameover
    jsr open_game_over_banner
    lda #STATE_GAME_OVER
    sta state
    lda #0
    sta state_timer
    rts
.endproc

; -------------------------------------------------------------
; CPU AI for P2 in 1P mode: move P2 paddle toward ball center.
; Difficulty scales how often the AI moves (ai_skip_mask) and how
; far it moves per tick (ai_step).
; -------------------------------------------------------------
.proc ai_paddle_p2
    ; Only chase when the ball is moving toward P2 or sitting still.
    lda ball_vx
    bmi @hold             ; moving away - idle

    ; Throttle moves: only act once every ai_period frames.
    inc ai_tick
    lda ai_tick
    cmp ai_period
    bcc @hold
    lda #0
    sta ai_tick

    ; target = ball_y - PADDLE_H/2 + 4  (align paddle centre to ball)
    lda ball_y
    sec
    sbc #(PADDLE_H/2 - 4)
    sta tmp0
    lda p2_y
    cmp tmp0
    beq @hold
    bcs @go_up
    ; p2_y < tmp0 -> move down
    clc
    adc ai_step
    cmp tmp0
    bcc @save
    lda tmp0
    jmp @save
@go_up:
    sec
    sbc ai_step
    cmp tmp0
    bcs @save
    lda tmp0
@save:
    jsr clamp_paddle_y
    sta p2_y
@hold:
    jsr refresh_paddles
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

; =============================================================
; Sound effects (Pulse 2 - Pulse 1 is reserved for the jingle)
; =============================================================

; Short high chirp for paddle hits.
.proc sfx_play_paddle
    lda #%10111111      ; duty=10, const vol, max volume
    sta $4004
    lda #$08
    sta $4005           ; sweep off
    lda #$40            ; period lo (high pitch)
    sta $4006
    lda #$00
    sta $4007
    lda #3
    sta sfx_timer
    rts
.endproc

; Lower-pitched ~200ms blip for a score.
.proc sfx_play_score
    lda #%10111111
    sta $4004
    lda #$08
    sta $4005
    lda #$FF
    sta $4006
    lda #$01
    sta $4007
    lda #12
    sta sfx_timer
    rts
.endproc

; Sustained low tone for game over.
.proc sfx_play_gameover
    lda #%10111111
    sta $4004
    lda #$08
    sta $4005
    lda #$FF
    sta $4006
    lda #$03
    sta $4007
    lda #45
    sta sfx_timer
    rts
.endproc

; Drain the sfx_timer every frame; silence Pulse 2 when it hits 0.
.proc tick_sfx
    lda sfx_timer
    beq @done
    dec sfx_timer
    bne @done
    lda #$30            ; duty 00, constant vol, vol = 0
    sta $4004
@done:
    rts
.endproc

.proc music_start
    lda #1
    sta music_on
    lda #0
    sta music_idx
    lda #1             ; ensure first dec hits zero on frame 1
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

; Play-field palette: minimal BG (just white digits on black) plus
; red/blue paddle colours and a white sprite for the (future) ball.
game_palette:
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $30, $30, $30
    .byte $0F, $16, $30, $30    ; sprite pal 0: red (P1 paddle)
    .byte $0F, $12, $30, $30    ; sprite pal 1: blue (P2 paddle)
    .byte $0F, $30, $30, $30    ; sprite pal 2: white (ball)
    .byte $0F, $30, $30, $30

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
diff_easy_text:
    .byte "EASY", 0
diff_normal_text:
    .byte "NORMAL", 0
diff_hard_text:
    .byte "HARD", 0
pause_title_text:
    .byte "PAUSED", 0
pause_resume_text:
    .byte "RESUME", 0
pause_exit_text:
    .byte "EXIT", 0
go_p1_text:
    .byte "P1 WINS!", 0
go_p2_text:
    .byte "P2 WINS!", 0

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
