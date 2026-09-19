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

    // Game variables - Reworked into dedicated Row/Column memory arrays
    // Sized to hold 12 slots of 14-bit frequency tokens
    reg [13:0] game_sequence_r [0:11];
    reg [13:0] game_sequence_c [0:11];
    
    reg [3:0]  level_length = 4'd12; // Adjusted to test all 12 entries



    // ---------------------------------------------------------------------
    // Parallel Array-to-Light Decoder Wire Mapping Links
    // ---------------------------------------------------------------------
    wire [13:0] current_step_r = game_sequence_r[audio_play_step];
    wire [13:0] current_step_c = game_sequence_c[audio_play_step];

    reg [1:0] light_row;
    reg [1:0] light_col;

    // Direct combinatorial decoding maps constants instantly to coordinates
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

    // Synchronous clock block locks down the clean active lighting output coordinate
    always @(posedge clk) begin
        if (state == STATE_SIMON_PLAYBACK) begin
            simon_active_key <= (light_row * 3'd4) + light_col;
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

                // --- 3. PSEUDO GENERATOR SETUP (Reworked to store frequency constants) ---
                STATE_GEN_SEQUENCE: begin
                    // Slot 0 (Key 1)
                    game_sequence_r[0]  <= R1; game_sequence_c[0]  <= C1;
                    // Slot 1 (Key 5)
                    game_sequence_r[1]  <= R2; game_sequence_c[1]  <= C2;
                    // Slot 2 (Key 9)
                    game_sequence_r[2]  <= R3; game_sequence_c[2]  <= C3;
                    // Slot 3 (Key D)
                    game_sequence_r[3]  <= R4; game_sequence_c[3]  <= C4;
                    // Slot 4
                    game_sequence_r[4]  <= R1; game_sequence_c[4]  <= C2;
                    // Slot 5
                    game_sequence_r[5]  <= R2; game_sequence_c[5]  <= C3;
                    // Slot 6
                    game_sequence_r[6]  <= R3; game_sequence_c[6]  <= C4;
                    // Slot 7
                    game_sequence_r[7]  <= R4; game_sequence_c[7]  <= C1;
                    // Slot 8
                    game_sequence_r[8]  <= R1; game_sequence_c[8]  <= C3;
                    // Slot 9
                    game_sequence_r[9]  <= R2; game_sequence_c[9]  <= C4;
                    // Slot 10
                    game_sequence_r[10] <= R3; game_sequence_c[10] <= C1;
                    // Slot 11
                    game_sequence_r[11] <= R4; game_sequence_c[11] <= C2;

                    state <= STATE_SIMON_PLAYBACK;
                end

                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY (Reworked to copy arrays) ---
                STATE_SIMON_PLAYBACK: begin
                    playback_length <= level_length; 

                    // Directly copy our memory arrays over to the parallel bus channels
                    out_seq_r[0   +: 14] <= game_sequence_r[0];  out_seq_c[0   +: 14] <= game_sequence_c[0];
                    out_seq_r[14  +: 14] <= game_sequence_r[1];  out_seq_c[14  +: 14] <= game_sequence_c[1];
                    out_seq_r[28  +: 14] <= game_sequence_r[2];  out_seq_c[28  +: 14] <= game_sequence_c[2];
                    out_seq_r[42  +: 14] <= game_sequence_r[3];  out_seq_c[42  +: 14] <= game_sequence_c[3];
                    out_seq_r[56  +: 14] <= game_sequence_r[4];  out_seq_c[56  +: 14] <= game_sequence_c[4];
                    out_seq_r[70  +: 14] <= game_sequence_r[5];  out_seq_c[70  +: 14] <= game_sequence_c[5];
                    out_seq_r[84  +: 14] <= game_sequence_r[6];  out_seq_c[84  +: 14] <= game_sequence_c[6];
                    out_seq_r[98  +: 14] <= game_sequence_r[7];  out_seq_c[98  +: 14] <= game_sequence_c[7];
                    out_seq_r[112 +: 14] <= game_sequence_r[8];  out_seq_c[112 +: 14] <= game_sequence_c[8];
                    out_seq_r[126 +: 14] <= game_sequence_r[9];  out_seq_c[126 +: 14] <= game_sequence_c[9];
                    out_seq_r[140 +: 14] <= game_sequence_r[10]; out_seq_c[140 +: 14] <= game_sequence_c[10];
                    out_seq_r[154 +: 14] <= game_sequence_r[11]; out_seq_c[154 +: 14] <= game_sequence_c[11];

                    play_trigger <= 1'b1; // Request playback start
                    
                    if (sequence_done) begin
                        play_trigger <= 1'b0; // Clean pull down request line
                        state        <= STATE_CHECK_ANSWER_DELAY; 
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
