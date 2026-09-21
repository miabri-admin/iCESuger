// =========================================================================
// RESTRUCTURED CLEAN MASTER SIMON SAYS ENGINE (simon_fsm.v)
// HARDENED IMPLEMENTATION: Rising-Edge Press Capture Engine
// =========================================================================

module simon_fsm (
    input             clk,
    input             reset,
    input      [4:0]  matrix_key_code,
    input             any_key_pressed,

    // Communication bus lines linked directly to the Tier-2 Audio Engine
    output reg        play_trigger,
    output reg [3:0]  playback_length,
    output reg [167:0] simon_seq_r,        
    output reg [167:0] simon_seq_c,        
    input             sequence_done,

    output reg        input_lockout,

    // Light Interface Feedback Bus Port Connections
    input      [3:0]  audio_play_step,
    output reg [4:0]  simon_active_key,
    output reg        play_in_simon_mode,

    input             final_key_released  // Terminal 2-second timeout trigger
);

    // Core DTMF Fixed Constant frequency blocks
    localparam R1 = 14'd8608; localparam R2 = 14'd7792; localparam R3 = 14'd7042; localparam R4 = 14'd6376;
    localparam C1 = 14'd4962; localparam C2 = 14'd4491; localparam C3 = 14'd4062; localparam C4 = 14'd3674;

    // High Level Game Controller States
    localparam STATE_BOOT_JINGLE        = 4'd0;
    localparam STATE_START_DELAY        = 4'd1;
    localparam STATE_GEN_SEQUENCE       = 4'd2;
    localparam STATE_SIMON_PLAYBACK     = 4'd3;
    localparam STATE_PLAYER_TURN        = 4'd4;
    localparam STATE_CHECK_ROUND        = 4'd5;
    localparam STATE_VICTORY_CHIME      = 4'd7;
    localparam STATE_FAILURE_CHIME      = 4'd8;
    localparam STATE_QUIET_LOCKOUT      = 4'd9;
    localparam STATE_MATCH_CHIME        = 4'd10;

    // ---------------------------------------------------------------------
    // Hardware Pseudo-Random Number Generator (4-bit LFSR Engine)
    // ---------------------------------------------------------------------
    reg [3:0] lfsr_reg = 4'b1011; 

    always @(posedge clk) begin
        if (reset) begin
            lfsr_reg <= 4'b1011;   
        end else begin
            lfsr_reg <= {lfsr_reg[2:0], lfsr_reg[3] ^ lfsr_reg[2]};
        end
    end

    // Sequence Generation Rules: Row 0 is locked; Column moves randomly
    wire [1:0] rand_row_index = 2'd0; 
    wire [1:0] rand_col_index = lfsr_reg[1:0];
    
    reg [3:0] gen_index = 0; 

    reg [3:0]  state = STATE_BOOT_JINGLE;
    reg [24:0] delay_timer = 0;

    // Simon Game Master Sequences
    reg [13:0] game_sequence_r [0:11];
    reg [13:0] game_sequence_c [0:11];
    
    // Player Input History Capture Buffers
    reg [13:0] player_seq_r [0:11];
    reg [13:0] player_seq_c [0:11];
    reg [3:0]  player_step_counter = 0; 

    localparam INIT_SEQ_LEN = 4'd2;         
    localparam MAX_SEQ_LEN  = 4'd12;        

    reg [3:0]  seq_len = INIT_SEQ_LEN; 

    // ---------------------------------------------------------------------
    // HARDENED: Rising Edge Press Detection (Captures when key goes DOWN)
    // ---------------------------------------------------------------------
    reg any_key_pressed_d1 = 1'b0;
    always @(posedge clk) begin
        any_key_pressed_d1 <= any_key_pressed;
    end
    wire local_step_pressed = (any_key_pressed && !any_key_pressed_d1);

    // ---------------------------------------------------------------------
    // Parallel Array-to-Light Decoder Wire Mapping Links
    // ---------------------------------------------------------------------
    wire [13:0] current_step_r = game_sequence_r[audio_play_step];
    wire [13:0] current_step_c = game_sequence_c[audio_play_step];

    reg [1:0] light_row;
    reg [1:0] light_col;

    // Loop indexing and validation registers
    reg        match_failed;
    integer    check_idx;

    always @(*) begin
        case (current_step_r)
            R1:      light_row = 2'd0;
            R2:      light_row = 2'd1;
            R3:      light_row = 2'd2;
            R4:      light_row = 2'd3;
            default: light_row = 2'd0;
        endcase

        case (current_step_c)
            C1:      light_col = 2'd0;
            C2:      light_col = 2'd1;
            C3:      light_col = 2'd2;
            C4:      light_col = 2'd3;
            default: light_col = 2'd0;
        endcase
    end

    always @(posedge clk) begin
        if (state == STATE_SIMON_PLAYBACK) begin
            simon_active_key <= (light_row * 3'd4) + light_col;
        end else begin
            simon_active_key <= 5'd16; 
        end
    end

    // ---------------------------------------------------------------------
    // Symmetrical Live Translation Mapping
    // ---------------------------------------------------------------------
    reg [13:0] live_translated_r;
    reg [13:0] live_translated_c;

    always @(*) begin
        case (matrix_key_code[3:2])
            2'd0:    live_translated_r = R1;
            2'd1:    live_translated_r = R2;
            2'd2:    live_translated_r = R3;
            default: live_translated_r = R4;
        endcase

        case (matrix_key_code[1:0])
            2'd0:    live_translated_c = C1;
            2'd1:    live_translated_c = C2;
            2'd2:    live_translated_c = C3;
            default: live_translated_c = C4;
        endcase
    end

    // ---------------------------------------------------------------------
    // Master State Engine Main Loop Block
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state               <= STATE_BOOT_JINGLE;
            play_trigger        <= 0;
            delay_timer         <= 0;
            input_lockout       <= 1'b1;
            gen_index           <= 4'd0;
            seq_len             <= INIT_SEQ_LEN;
            play_in_simon_mode  <= 1'b0;
            player_step_counter <= 4'd0;
            match_failed        <= 1'b0;
        end else begin
            case (state)
                // --- 1. LOAD AND PLAY BOOTUP SCALE ---
                STATE_BOOT_JINGLE: begin
                    input_lockout   <= 1'b1;
                    playback_length <= 4'd4; 
                    
                    simon_seq_r[0  +: 14] <= R1; simon_seq_c[0  +: 14] <= C1; 
                    simon_seq_r[14 +: 14] <= R2; simon_seq_c[14 +: 14] <= C1;
                    simon_seq_r[28 +: 14] <= R3; simon_seq_c[28 +: 14] <= C1;
                    simon_seq_r[42 +: 14] <= R4; simon_seq_c[42 +: 14] <= C1;

                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        state        <= STATE_START_DELAY;
                    end
                end

                // --- 2. THE 2-SECOND DELAY WINDOW ---
                STATE_START_DELAY: begin
                    delay_timer <= delay_timer + 1'b1;
                    if (delay_timer >= 25'd23_999_999) begin
                        delay_timer <= 0;
                        state       <= STATE_GEN_SEQUENCE;
                    end
                end

                // --- 3. DYNAMIC GENERATOR SETUP ---
                STATE_GEN_SEQUENCE: begin
                    case (rand_row_index)
                        2'd0:    game_sequence_r[gen_index] <= R1;
                        2'd1:    game_sequence_r[gen_index] <= R2;
                        2'd2:    game_sequence_r[gen_index] <= R3;
                        2'd3:    game_sequence_r[gen_index] <= R4;
                    endcase

                    case (rand_col_index)
                        2'd0:    game_sequence_c[gen_index] <= C1;
                        2'd1:    game_sequence_c[gen_index] <= C2;
                        2'd2:    game_sequence_c[gen_index] <= C3;
                        2'd3:    game_sequence_c[gen_index] <= C4;
                    endcase

                    if (gen_index >= 4'd11) begin
                        gen_index <= 0;
                        state     <= STATE_SIMON_PLAYBACK;
                    end else begin
                        gen_index <= gen_index + 1'b1;
                    end
                end

                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY ---
                STATE_SIMON_PLAYBACK: begin
                    playback_length <= seq_len; 

                    // FIX: Explicitly map every array position index [0] through [11]
                    simon_seq_r[0   +: 14] <= game_sequence_r[0];   simon_seq_c[0   +: 14] <= game_sequence_c[0];
                    simon_seq_r[14  +: 14] <= game_sequence_r[1];   simon_seq_c[14  +: 14] <= game_sequence_c[1];
                    simon_seq_r[28  +: 14] <= game_sequence_r[2];   simon_seq_c[28  +: 14] <= game_sequence_c[2];
                    simon_seq_r[42  +: 14] <= game_sequence_r[3];   simon_seq_c[42  +: 14] <= game_sequence_c[3];
                    simon_seq_r[56  +: 14] <= game_sequence_r[4];   simon_seq_c[56  +: 14] <= game_sequence_c[4];
                    simon_seq_r[70  +: 14] <= game_sequence_r[5];   simon_seq_c[70  +: 14] <= game_sequence_c[5];
                    simon_seq_r[84  +: 14] <= game_sequence_r[6];   simon_seq_c[84  +: 14] <= game_sequence_c[6];
                    simon_seq_r[98  +: 14] <= game_sequence_r[7];   simon_seq_c[98  +: 14] <= game_sequence_c[7];
                    simon_seq_r[112 +: 14] <= game_sequence_r[8];   simon_seq_c[112 +: 14] <= game_sequence_c[8];
                    simon_seq_r[126 +: 14] <= game_sequence_r[9];   simon_seq_c[126 +: 14] <= game_sequence_c[9];
                    simon_seq_r[140 +: 14] <= game_sequence_r[10];  simon_seq_c[140 +: 14] <= game_sequence_c[10];
                    simon_seq_r[154 +: 14] <= game_sequence_r[11];  simon_seq_c[154 +: 14] <= game_sequence_c[11];

                    play_in_simon_mode <= 1'b1; 
                    play_trigger       <= 1'b1; 

                    if (sequence_done) begin
                        play_trigger        <= 1'b0;
                        play_in_simon_mode  <= 1'b0; 
                        input_lockout       <= 1'b0; 
                        player_step_counter <= 4'd0; 
                        state               <= STATE_PLAYER_TURN;
                    end
                end

                // --- 5. INTERACTIVE PLAYER INPUT WITH RISING EDGE CAPTURE ---
                STATE_PLAYER_TURN: begin
                    input_lockout   <= 1'b0;
                    playback_length <= 4'd1;

                    if (any_key_pressed) begin
                        play_trigger         <= 1'b1;
                        simon_seq_r[0 +: 14] <= live_translated_r;
                        simon_seq_c[0 +: 14] <= live_translated_c;
                    end else begin
                        play_trigger         <= 1'b0;
                        simon_seq_r[0 +: 14] <= 14'd0;
                        simon_seq_c[0 +: 14] <= 14'd0;
                    end

                    // HARDENED FIX: Commit the active keys instantly when pressed DOWN
                    if (local_step_pressed) begin
                        if (player_step_counter < seq_len) begin
                            player_seq_r[player_step_counter] <= live_translated_r;
                            player_seq_c[player_step_counter] <= live_translated_c;
                            player_step_counter               <= player_step_counter + 1'b1;
                        end
                    end

                    // Watch for the 2-second global inactivity strobe to finish the turn
                    if (final_key_released) begin
                        play_trigger  <= 1'b0;
                        input_lockout <= 1'b1;
                        state         <= STATE_CHECK_ROUND;
                    end
                end

                // --- 6. VALIDATE PLAYER PHRASE AGAINST GAME MEMORY ---
                STATE_CHECK_ROUND: begin
                    match_failed = 1'b0;

                    // Criterion 1: Verify total key entry step length matches
                    if (player_step_counter != seq_len) begin
                        match_failed = 1'b1;
                    end

                    // Criterion 2: Match captured tones up to current active round length
                    for (check_idx = 0; check_idx < 12; check_idx = check_idx + 1) begin
                        if (check_idx < seq_len) begin
                            if ((player_seq_r[check_idx] != game_sequence_r[check_idx]) ||
                                (player_seq_c[check_idx] != game_sequence_c[check_idx])) begin
                                match_failed = 1'b1;
                            end
                        end
                    end

                    // Master Game Logic Core Routing Selection
                    if (match_failed) begin
                        seq_len <= INIT_SEQ_LEN; // Reset difficulty back to 3 on a loss
                        state   <= STATE_FAILURE_CHIME;
                    end else if (seq_len >= MAX_SEQ_LEN) begin
                        seq_len <= INIT_SEQ_LEN; // Reset difficulty back to 3 after full win
                        state   <= STATE_VICTORY_CHIME;
                    end else begin
                        state   <= STATE_MATCH_CHIME;
                    end
                end

                // --- 6c. LOAD AND PLAY SHORT ROUND-MATCH CHIME ---
                // Plays a quick, pleasant rising double-beep on successful rounds
                STATE_MATCH_CHIME: begin
                    playback_length <= 4'd2;
                    
                    simon_seq_r[0  +: 14] <= 14'd2500; simon_seq_c[0  +: 14] <= C1;
                    simon_seq_r[14 +: 14] <= 14'd2000; simon_seq_c[14 +: 14] <= C1;
                    
                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        seq_len      <= seq_len + 1'b1; // Advance level after audio stops
                        state        <= STATE_START_DELAY;
                    end
                end

                // --- 7. LOAD AND PLAY TA-DA LONG VICTORY CHIME ---
                STATE_VICTORY_CHIME: begin
                    playback_length <= 4'd2;
                    
                    simon_seq_r[0  +: 14] <= 14'd3500; simon_seq_c[0  +: 14] <= C1;
                    simon_seq_r[14 +: 14] <= 14'd1500; simon_seq_c[14 +: 14] <= C1;
                    
                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        state        <= STATE_QUIET_LOCKOUT;
                    end
                end

                // --- 8. LOAD AND PLAY LOW WAH-WAH-WAH FAIL CHIME ---
                STATE_FAILURE_CHIME: begin
                    playback_length <= 4'd4;
                    
                    simon_seq_r[0   +: 14] <= 14'd10000; simon_seq_c[0   +: 14] <= 14'd0;
                    simon_seq_r[14  +: 14] <= 14'd11500; simon_seq_c[14  +: 14] <= 14'd0;
                    simon_seq_r[28  +: 14] <= 14'd13000; simon_seq_c[28  +: 14] <= 14'd0;
                    simon_seq_r[42  +: 14] <= 14'd15500; simon_seq_c[42  +: 14] <= 14'd0;
                    
                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        state        <= STATE_QUIET_LOCKOUT;
                    end
                end

                // --- 9. LOCKOUT COOL DOWN STATE ---
                STATE_QUIET_LOCKOUT: begin
                    delay_timer <= delay_timer + 1'b1;
                    if (delay_timer >= 25'd23_999_999) begin
                        delay_timer <= 0;
                        state       <= STATE_BOOT_JINGLE; 
                    end
                    input_lockout <= 1'b1;
                end

                default: state <= STATE_BOOT_JINGLE;
            endcase
        end
    end

endmodule
