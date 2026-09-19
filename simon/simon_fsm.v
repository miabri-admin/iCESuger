// =========================================================================
// RESTRUCTURED CLEAN MASTER SIMON SAYS ENGINE (simon_fsm.v)
// Employs Shared Array Data Bus and deterministic peripheral jump handshakes.
// =========================================================================

module simon_fsm (
    input             clk,
    input             reset,
    input      [4:0]  matrix_key_code,
    input             any_key_pressed,

    // Communication bus lines linked directly to the Tier-2 Audio Engine
    output reg        play_trigger,
    output reg [3:0]  playback_length,
    output reg [167:0] out_seq_r,
    output reg [167:0] out_seq_c,
    input             sequence_done,

    output reg        input_lockout,

    // Light Interface Feedback Bus Port Connections
    input      [3:0]  audio_play_step,
    output reg [4:0]  simon_active_key

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
    localparam STATE_CHECK_ANSWER_DELAY = 4'd6;
    localparam STATE_VICTORY_CHIME      = 4'd7;
    localparam STATE_FAILURE_CHIME      = 4'd8;
    localparam STATE_QUIET_LOCKOUT      = 4'd9;

    reg [3:0]  state = STATE_BOOT_JINGLE;
    reg [24:0] delay_timer = 0;

   // Game variables
    reg [3:0]  level_length = 4'd3;
    reg [4:0]  game_memory_sequence [0:11];

    // Extracts the active 14-bit frequency tokens playing on the bus right now
    wire [13:0] active_row_freq = out_seq_r[(audio_play_step * 14) +: 14];
    wire [13:0] active_col_freq = out_seq_c[(audio_play_step * 14) +: 14];

    // Decode frequencies back to a 2-bit row index and 2-bit col index
    reg [1:0] decoded_row;
    reg [1:0] decoded_col;

    always @(*) begin
        // Row Decoder
        if      (active_row_freq == R1) decoded_row = 2'd0;
        else if (active_row_freq == R2) decoded_row = 2'd1;
        else if (active_row_freq == R3) decoded_row = 2'd2;
        else if (active_row_freq == R4) decoded_row = 2'd3;
        else                            decoded_row = 2'd0;

        // Column Decoder
        if      (active_col_freq == C1) decoded_col = 2'd0;
        else if (active_col_freq == C2) decoded_col = 2'd1;
        else if (active_col_freq == C3) decoded_col = 2'd2;
        else if (active_col_freq == C4) decoded_col = 2'd3;
        else                            decoded_col = 2'd0;
    end

    // Clocked assignment maps (row * 4) + col dynamically to match the bus data
    always @(posedge clk) begin
        if (state == STATE_SIMON_PLAYBACK) begin
            // Reconstructs the 0-15 layout index directly from the bus content!
            simon_active_key <= (decoded_row * 3'd4) + decoded_col;
        end else begin
            simon_active_key <= 5'd16; // Standby / Off
        end
    end


    // ---------------------------------------------------------------------
    // Master State Engine Main Loop Block
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state        <= STATE_BOOT_JINGLE;
            play_trigger <= 0;
            delay_timer  <= 0;
            input_lockout<= 1'b1;
        end else begin
            case (state)
                // --- 1. LOAD AND PLAY BOOTUP SCALE ---
                STATE_BOOT_JINGLE: begin
                    input_lockout   <= 1'b1;
                    playback_length <= 4'd4; // 4 notes in startup melody
                    
                    // Directly load our target frequency notes step-by-step
                    out_seq_r[0  +: 14] <= R1; out_seq_c[0  +: 14] <= 14'd0;
                    out_seq_r[14 +: 14] <= R2; out_seq_c[14 +: 14] <= 14'd0;
                    out_seq_r[28 +: 14] <= R3; out_seq_c[28 +: 14] <= 14'd0;
                    out_seq_r[42 +: 14] <= R4; out_seq_c[42 +: 14] <= 14'd0;

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

                // --- 3. PSEUDO GENERATOR SETUP ---
                STATE_GEN_SEQUENCE: begin
                    // (Mock random sequence indices saved internally)
                    game_memory_sequence[0] <= 5'd0;  // Key 1
                    game_memory_sequence[1] <= 5'd5;  // Key 5
                    game_memory_sequence[2] <= 5'd10; // Key 9
                    state                   <= STATE_SIMON_PLAYBACK;
                end

                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY ---
                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY ---
                STATE_SIMON_PLAYBACK: begin
                    playback_length <= 4'd12; // Test Override: Full 12 note run
                    
                    
                    // Parallel Bus Data Vector Assignments
                    out_seq_r[0   +: 14] <= R1; out_seq_c[0   +: 14] <= C1; 
                    out_seq_r[14  +: 14] <= R2; out_seq_c[14  +: 14] <= C2; 
                    out_seq_r[28  +: 14] <= R3; out_seq_c[28  +: 14] <= C3; 
                    out_seq_r[42  +: 14] <= R4; out_seq_c[42  +: 14] <= C4; 
                    out_seq_r[56  +: 14] <= R1; out_seq_c[56  +: 14] <= C2; 
                    out_seq_r[70  +: 14] <= R2; out_seq_c[70  +: 14] <= C3; 
                    out_seq_r[84  +: 14] <= R3; out_seq_c[84  +: 14] <= C4; 
                    out_seq_r[98  +: 14] <= R4; out_seq_c[98  +: 14] <= C1; 
                    out_seq_r[112 +: 14] <= R1; out_seq_c[112 +: 14] <= C3; 
                    out_seq_r[126 +: 14] <= R2; out_seq_c[126 +: 14] <= C4; 
                    out_seq_r[140 +: 14] <= R3; out_seq_c[140 +: 14] <= C1; 
                    out_seq_r[154 +: 14] <= R4; out_seq_c[154 +: 14] <= C2; 

                    play_trigger <= 1'b1; // Request playback start
                    
                    if (sequence_done) begin
                        play_trigger     <= 1'b0; // Clean pull down request line
                        state            <= STATE_CHECK_ANSWER_DELAY; 
                    end
                end

                // --- 5. END OF PLAYBACK STANDBY FOR 2 SECONDS ---
                STATE_CHECK_ANSWER_DELAY: begin
                    delay_timer <= delay_timer + 1'b1;
                    if (delay_timer >= 25'd23_999_999) begin
                        delay_timer <= 0;
                        state       <= STATE_VICTORY_CHIME;
                    end
                end

                // --- 6. LOAD AND PLAY TA-DA CHIME ---
                STATE_VICTORY_CHIME: begin
                    playback_length <= 4'd2; // 2 notes inside our Ta-Da chime
                    
                    out_seq_r[0  +: 14] <= 14'd3500; out_seq_c[0  +: 14] <= 14'd0; // Note 1
                    out_seq_r[14 +: 14] <= 14'd1500; out_seq_c[14 +: 14] <= 14'd0; // Note 2 (Triumphant High)

                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        state        <= STATE_QUIET_LOCKOUT;
                    end
                end

                // --- 7. END OF CYCLE STANDBY FOR 2 SECONDS ---
                STATE_QUIET_LOCKOUT: begin
                    delay_timer <= delay_timer + 1'b1;
                    if (delay_timer >= 25'd23_999_999) begin
                        delay_timer <= 0;
                        state       <= STATE_BOOT_JINGLE; 
                    end
                end
                
                default: state <= STATE_BOOT_JINGLE;
            endcase
        end
    end

endmodule
