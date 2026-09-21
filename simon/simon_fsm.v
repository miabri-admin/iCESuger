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
    output reg [4:0]  simon_active_key,
    output reg        play_at_half_speed,

    input             key_released

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



    // ---------------------------------------------------------------------
    // Hardware Pseudo-Random Number Generator (4-bit LFSR Engine)
    // Cycles through a random pattern continuously at 12MHz.
    // ---------------------------------------------------------------------
    reg [3:0] lfsr_reg = 4'b1011; // Must be initialized to a non-zero value!

    always @(posedge clk) begin
        if (reset) begin
            lfsr_reg <= 4'b1011;   // Seed value fallback
        end else begin
            // Tap configuration for a maximal-period 4-bit LFSR (Taps: bits 4 and 3)
            lfsr_reg <= {lfsr_reg[2:0], lfsr_reg[3] ^ lfsr_reg[2]};
        end
    end

    // Split the running 4-bit random register into two 2-bit selection indices
    wire [1:0] rand_row_index = lfsr_reg[3:2];
    wire [1:0] rand_col_index = lfsr_reg[1:0];

    reg [3:0] gen_index = 0; // Tracks which array slot we are loading during setup



    reg [3:0]  state = STATE_BOOT_JINGLE;
    reg [24:0] delay_timer = 0;

    // Game variables - Reworked into dedicated Row/Column memory arrays
    // Sized to hold 12 slots of 14-bit frequency tokens
    reg [13:0] game_sequence_r [0:11];
    reg [13:0] game_sequence_c [0:11];
    
    localparam INIT_SEQ_LEN = 4'd3;         // Sized as a small 4-bit integer literal
    localparam MAX_SEQ_LEN  = 4'd12;        // Upgraded depth index dynamically up to 12


    reg [3:0]  seq_len = INIT_SEQ_LEN; // Adjusted to test all 12 entries



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
                // --- 3. DYNAMIC GENERATOR SETUP: Populates all 12 slots randomly ---
                STATE_GEN_SEQUENCE: begin
                    // 1. Map the running random row index to our frequency constants
                    case (rand_row_index)
                        2'd0:    game_sequence_r[gen_index] <= R1;
                        2'd1:    game_sequence_r[gen_index] <= R2;
                        2'd2:    game_sequence_r[gen_index] <= R3;
                        2'd3:    game_sequence_r[gen_index] <= R4;
                    endcase

                    // 2. Map the running random column index to our frequency constants
                    case (rand_col_index)
                        2'd0:    game_sequence_c[gen_index] <= C1;
                        2'd1:    game_sequence_c[gen_index] <= C2;
                        2'd2:    game_sequence_c[gen_index] <= C3;
                        2'd3:    game_sequence_c[gen_index] <= C4;
                    endcase

                    // 3. Step Sequencer Iterator Loop
                    if (gen_index >= 4'd11) begin
                        gen_index <= 0; // Array is fully loaded with random keys!
                        state     <= STATE_SIMON_PLAYBACK; // Move to note playback
                    end else begin
                        gen_index <= gen_index + 1'b1; // Advance to the next slot
                    end
                end


                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY (Reworked to copy arrays) ---
                // --- 4. LOAD CURRENT ROUND RANDOM NOTES DYNAMICALLY ---
                STATE_SIMON_PLAYBACK: begin
                    playback_length <= seq_len; 

                    // Directly copy memory array indices to parallel bus streams
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

                    play_trigger <= 1'b1; 

                    // Handshake validation logic to transition out of playback
                    if (sequence_done) begin
                        play_trigger  <= 1'b0;
                        input_lockout <= 1'b0;             // CRITICAL: Unlock inputs for scanner
                        state         <= STATE_PLAYER_TURN; // Advance to player input monitoring
                    end
                end

                // --- 5. WAIT FOR DEBOUCED KEY RELEASE ---
                STATE_PLAYER_TURN: begin
                    // FSM loops safely here until a clean, 1-cycle key release pulse arrives
                    if (key_released) begin
                        input_lockout <= 1'b1;             // Re-lock to avoid double-tap glitches
                        state         <= STATE_CHECK_ANSWER_DELAY; 
                    end
                end

                // --- 6. CHECK ANSWER DELAY ---
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

   // Drive the half speed flag exclusively when Simon is showcasing his sequence memory notes
    always @(*) begin
        if (state == STATE_SIMON_PLAYBACK)
            play_at_half_speed = 1'b1; // Simon plays slow (~600ms)
        else
            play_at_half_speed = 1'b0; // Everything else (Tada, Startup, etc) plays fast (~300ms)
    end

endmodule
