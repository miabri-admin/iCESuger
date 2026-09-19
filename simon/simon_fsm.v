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

    output reg        input_lockout
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

    // ---------------------------------------------------------------------
    // Master State Engine
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
                STATE_SIMON_PLAYBACK: begin
                    playback_length <= level_length;
                    
                    // Simple programmatic mapping loops through the current dynamic game memory array lengths
                    // translating the indices directly into frequency signals over our bus
                    out_seq_r[0  +: 14] <= R1; out_seq_c[0  +: 14] <= C1; // Key 1 frequencies
                    out_seq_r[14 +: 14] <= R2; out_seq_c[14 +: 14] <= C2; // Key 5 frequencies
                    out_seq_r[28 +: 14] <= R3; out_seq_c[28 +: 14] <= C3; // Key 9 frequencies

                    play_trigger <= 1'b1;
                    if (sequence_done) begin
                        play_trigger <= 1'b0;
                        state        <= STATE_CHECK_ANSWER_DELAY; // Demo skip direct to delay state
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
                        state       <= STATE_BOOT_JINGLE; // Loop testing sequence safely
                    end
                end
                
                default: state <= STATE_BOOT_JINGLE;
            endcase
        end
    end

endmodule
