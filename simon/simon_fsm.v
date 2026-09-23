// =========================================================================
// RESTRUCTURED CLEAN MASTER SIMON SAYS ENGINE (simon_fsm.v) - FULL FIXED
// History stored exclusively as 4-bit key codes (0-15) in 1D arrays.
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
    localparam STATE_RESOLVE_MATCH      = 4'd11; 

    // Hardware LFSR Engine
    reg [3:0] lfsr_reg = 4'b1011; 
    reg       lfsr_freeze = 1'b0; 

     // =========================================================================
    // HARDENED PSEUDO-RANDOM LFSR ENGINE (Maximal Length Taps 3 and 0)
    // =========================================================================
    reg [3:0] lfsr_reg = 4'b1011; 
    reg       lfsr_freeze = 1'b0; 

    always @(posedge clk) begin
        if (reset) begin
            lfsr_reg <= 4'b1011; 
        end else if (!lfsr_freeze) begin
            lfsr_reg <= {lfsr_reg[2:0], lfsr_reg[3] ^ lfsr_reg[0]};
        end
    end

    // EASY MODIFICATION: Hardlock rows to 0. Columns swing randomly between 0, 1, 2, 3
    wire [1:0] rand_row_index = 2'd0;          // FIXED: Hardlocked to first row
    wire [1:0] rand_col_index = lfsr_reg[1:0]; // Dynamic lower bits provide a 0-3 random sweep

    
    reg [3:0] gen_index = 0; 
    reg [3:0] state = STATE_BOOT_JINGLE;
    reg [24:0] delay_timer = 0;

    // REFOCUSED SINGLE ARRAYS: Storing clean 4-bit codes (0-15)
    reg [3:0] game_sequence [0:11];
    reg [3:0] player_seq    [0:11];
    reg [3:0] player_step_counter = 0; 

    localparam INIT_SEQ_LEN = 4'd2;         
    localparam MAX_SEQ_LEN  = 4'd12;        
    reg [3:0]  seq_len = INIT_SEQ_LEN; 

    // Falling Edge Capture (Detects exactly when user RELEASES a key)
    reg any_key_pressed_d1 = 1'b0;
    always @(posedge clk) begin
        any_key_pressed_d1 <= any_key_pressed;
    end
    wire local_key_released = (!any_key_pressed && any_key_pressed_d1);

    // Keep track of what key was physically held down prior to release
    reg [3:0] held_key_latched = 4'd0;
    always @(posedge clk) begin
        if (any_key_pressed && (matrix_key_code != 5'd16)) begin
            held_key_latched <= matrix_key_code[3:0];
        end
    end

    // ---------------------------------------------------------------------
    // Parallel Array-to-Light Decoder Wire Mapping Links
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (state == STATE_SIMON_PLAYBACK) begin
            // Read directly from your single unified 4-bit array slot
            simon_active_key <= {1'b0, game_sequence[audio_play_step]};
        end else begin
            simon_active_key <= 5'd16; 
        end
    end

    // Helper Function to translate 4-bit codes to 14-bit Row Frequencies
    function [13:0] get_row_freq;
        input [3:0] key;
        begin
            case (key[3:2])
                2'd0: get_row_freq = R1;
                2'd1: get_row_freq = R2;
                2'd2: get_row_freq = R3;
                default: get_row_freq = R4;
            endcase
        end
    endfunction

    // Helper Function to translate 4-bit codes to 14-bit Column Frequencies
    function [13:0] get_col_freq;
        input [3:0] key;
        begin
            case (key[1:0])
                2'd0: get_col_freq = C1;
                2'd1: get_col_freq = C2;
                2'd2: get_col_freq = C3;
                default: get_col_freq = C4;
            endcase
        end
    endfunction

    // Master state tracking logic
    reg        match_failed;
    integer    check_idx;

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
            lfsr_freeze         <= 1'b0;
        end else begin
            lfsr_freeze <= 1'b0; 

            case (state)
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

                STATE_START_DELAY: begin
                    delay_timer <= delay_timer + 1'b1;
                    if (delay_timer >= 25'd23_999_999) begin
                        delay_timer <= 0;
                        gen_index   <= 0;
                        state       <= STATE_GEN_SEQUENCE;
                    end
                end

                STATE_GEN_SEQUENCE: begin
                    lfsr_freeze <= 1'b1; 

                    // Storing a simple unified 4-bit key layout (0-15)
                    game_sequence[gen_index] <= (rand_row_index * 3'd4) + rand_col_index;

                    if (gen_index >= 4'd11) begin
                        gen_index <= 0;
                        state     <= STATE_SIMON_PLAYBACK;
                    end else begin
                        gen_index <= gen_index + 1'b1;
                    end
                end
                
                STATE_SIMON_PLAYBACK: begin
                    playback_length    <= seq_len; 
                    play_in_simon_mode <= 1'b1; 
                    play_trigger       <= 1'b1; 

                    // Dynamically map frequencies over the bus right out of the simple 4-bit array cells
                    for (check_idx = 0; check_idx < 12; check_idx = check_idx + 1) begin
                        simon_seq_r[check_idx*14 +: 14] <= get_row_freq(game_sequence[check_idx]);
                        simon_seq_c[check_idx*14 +: 14] <= get_col_freq(game_sequence[check_idx]);
                    end

                    if (sequence_done) begin
                        play_trigger        <= 1'b0;
                        play_in_simon_mode  <= 1'b0; 
                        input_lockout       <= 1'b0; 
                        player_step_counter <= 4'd0; 
                        
                        // Wipe player array 
                        for (check_idx = 0; check_idx < 12; check_idx = check_idx + 1) begin
                            player_seq[check_idx] <= 4'd0;
                        end
                        state <= STATE_PLAYER_TURN;
                    end
                end

                STATE_PLAYER_TURN: begin
                    input_lockout   <= 1'b0;
                    playback_length <= 4'd1;

                    // LIVE USER SOUND FEEDBACK: Pipe exactly one note down step 0 when pressed
                    if (any_key_pressed && (matrix_key_code != 5'd16)) begin
                        play_trigger         <= 1'b1;
                        simon_seq_r[0 +: 14] <= get_row_freq(matrix_key_code[3:0]);
                        simon_seq_c[0 +: 14] <= get_col_freq(matrix_key_code[3:0]);
                    end else begin
                        play_trigger         <= 1'b0;
                        simon_seq_r[0 +: 14] <= 14'd0;
                        simon_seq_c[0 +: 14] <= 14'd0;
                    end

                    // FIXED: Commit keystroke into your simple array strictly ON RELEASE edge
                    if (local_key_released) begin
                        if (player_step_counter < seq_len) begin
                            player_seq[player_step_counter] <= held_key_latched;
                            player_step_counter             <= player_step_counter + 1'b1;
                        end
                    end

                    if (final_key_released) begin
                        play_trigger  <= 1'b0;
                        input_lockout <= 1'b1;
                        state         <= STATE_CHECK_ROUND;
                    end
                end

                STATE_CHECK_ROUND: begin
                    match_failed <= 1'b0; 

                    if (player_step_counter != seq_len) begin
                        match_failed <= 1'b1;
                    end

                    // Clean, atomic comparative layout loops
                    for (check_idx = 0; check_idx < 12; check_idx = check_idx + 1) begin
                        if (check_idx < seq_len) begin
                            if (player_seq[check_idx] != game_sequence[check_idx]) begin
                                match_failed <= 1'b1;
                            end // <--- Closes: if (player_seq != game_sequence)
                        end // <--- Closes: if (check_idx < seq_len)
                    end // <--- Closes: for (check_idx = 0...)

                    state <= STATE_RESOLVE_MATCH;
                end // <--- Closes: STATE_CHECK_ROUND: begin

                STATE_RESOLVE_MATCH: begin
                    if (match_failed) begin
                        seq_len <= INIT_SEQ_LEN;
                        state   <= STATE_FAILURE_CHIME;
                    end else if (seq_len >= MAX_SEQ_LEN) begin
                        seq_len <= INIT_SEQ_LEN;
                        state   <= STATE_VICTORY_CHIME;
                    end else begin
                        state   <= STATE_MATCH_CHIME;
                    end
                end

                STATE_MATCH_CHIME: begin
                    playback_length <= 4'd2;
                    simon_seq_r[0  +: 14] <= 14'd2500; simon_seq_c[0  +: 14] <= C1;
                    simon_seq_r[14 +: 14] <= 14'd2000; simon_seq_c[14 +: 14] <= C1;
                    play_trigger <= 1'b1;
                    
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        seq_len      <= seq_len + 1'b1;
                        state        <= STATE_START_DELAY;
                    end
                end

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
