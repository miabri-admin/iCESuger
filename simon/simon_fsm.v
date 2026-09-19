// =========================================================================
// SIMON SAYS CODENAME CORE FINITE STATE MACHINE (FSM)
// Implements full game loop arbitration, watchdog limits, and sound routing.
// =========================================================================

module simon_fsm (
    input             clk,                  // Master 12MHz hardware clock source
    input             reset,                // Hardware master system override reset
    input      [4:0]  matrix_key_code,      // Filtered key input from peripheral scanner
    input             any_key_pressed,      // Synchronous button trace listener line

    output reg [4:0]  arbitrated_key_code,  // Sound/LED code out to peripherals
    output reg        input_lockout         // Suspends scanning peripherals during playbacks
);

    // ---------------------------------------------------------------------
    // 1. Array Definitions & Depth Sizing Configurations
    // ---------------------------------------------------------------------
    localparam INIT_SEQ_LEN = 4'd3;         // Sized as a small 4-bit integer literal
    localparam MAX_SEQ_LEN  = 4'd12;        // Upgraded depth index dynamically up to 12

    reg [3:0]  seq_len = INIT_SEQ_LEN;      // Holds the current round's sequence length
    reg [3:0]  current_step = 4'd0;         // Tracks progression inside loops

    // 2D Array Memories storing the 5-bit key values (0 to 15) up to 12 slots deep
    reg [4:0] simon_sequence  [0:11];
    reg [4:0] player_sequence [0:11];

    // ---------------------------------------------------------------------
    // 2. FSM State Definition Constants Layout
    // ---------------------------------------------------------------------
    localparam PLAY_START_TONE      = 4'd0;
    localparam GENERATE_SEQUENCE    = 4'd1;
    localparam PLAY_SIMON_SEQUENCE  = 4'd2;
    localparam ENTER_LISTENING_MODE = 4'd3;
    localparam CHECK_MATCH          = 4'd4;
    localparam PLAY_WAWAWA          = 4'd5;
    localparam PLAY_TADA            = 4'd6;
    localparam PLAY_EXTENDED_TATA   = 4'd7;
    localparam QUIET_STATE          = 4'd8;

    reg [3:0] state = PLAY_START_TONE;

    // ---------------------------------------------------------------------
    // 3. Timing and Watchdog Duration Reference Registers
    // ---------------------------------------------------------------------
    reg [24:0] generic_timer = 0;           // Generates accurate time steps up to 2 seconds
    reg        last_pressed_state = 0;      // Registers click release edges

    // Pseudo-Random Number Generation Link register (Cycles continuous 0-15 wheel)
    reg [3:0] lfsr_rng = 4'd0;
    always @(posedge clk) lfsr_rng <= lfsr_rng + 1'b1;

    // ---------------------------------------------------------------------
    // 4. Synchronous Master FSM Loop Engine Execution Block
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset) begin
            state          <= PLAY_START_TONE;
            seq_len        <= INIT_SEQ_LEN;
            generic_timer  <= 0;
            current_step   <= 0;
            input_lockout  <= 1'b1;
            last_pressed_state <= 1'b0;
        end else begin
            last_pressed_state <= any_key_pressed; // Track finger state shift

            case (state)
                // --- STATE 0: Play Power-up Startup Jingle ---
                PLAY_START_TONE: begin
                    input_lockout <= 1'b1;
                    generic_timer <= generic_timer + 1'b1;
                    if (generic_timer >= 25'd11_999_999) begin // 1 Second Jingle Duration
                        generic_timer <= 0;
                        state         <= GENERATE_SEQUENCE;
                    end
                end

                // --- STATE 1: Generate Complete Random Array Sequence ---
                GENERATE_SEQUENCE: begin
                    // Populates target steps sequentially based on the rolling RNG wheel
                    simon_sequence[0] <= {1'b0, lfsr_rng};
                    simon_sequence[1] <= {1'b0, lfsr_rng + 4'd3};
                    simon_sequence[2] <= {1'b0, lfsr_rng + 4'd7};
                    simon_sequence[3] <= {1'b0, lfsr_rng + 4'd11};
                    simon_sequence[4] <= {1'b0, lfsr_rng + 4'd2};
                    simon_sequence[5] <= {1'b0, lfsr_rng + 4'd5};
                    simon_sequence[6] <= {1'b0, lfsr_rng + 4'd9};
                    simon_sequence[7] <= {1'b0, lfsr_rng + 4'd1};
                    simon_sequence[8] <= {1'b0, lfsr_rng + 4'd4};
                    simon_sequence[9] <= {1'b0, lfsr_rng + 4'd8};
                    simon_sequence[10]<= {1'b0, lfsr_rng + 4'd6};
                    simon_sequence[11]<= {1'b0, lfsr_rng + 4'd10};
                    
                    current_step  <= 0;
                    generic_timer <= 0;
                    state         <= PLAY_SIMON_SEQUENCE;
                end

                // --- STATE 2: Playback Simon's Sequence with Lights ---
                PLAY_SIMON_SEQUENCE: begin
                    input_lockout <= 1'b1;
                    generic_timer <= generic_timer + 1'b1;
                    
                    if (generic_timer >= 25'd5_999_999) begin // Play note length (~500ms)
                        generic_timer <= 0;
                        if (current_step >= (seq_len - 1'b1)) begin
                            current_step <= 0;
                            state        <= ENTER_LISTENING_MODE;
                        end else begin
                            current_step <= current_step + 1'b1;
                        end
                    end
                end

                // --- STATE 3: User Response Capture with 2-Second Watchdog ---
                ENTER_LISTENING_MODE: begin
                    input_lockout <= 1'b0; // Release lockout to accept clicks

                    if (any_key_pressed) begin
                        watchdog_clear();
                    end

                    // Log capture into player memory array exactly on physical button release edge
                    if (last_pressed_state && !any_key_pressed) begin
                        player_sequence[current_step] <= matrix_key_code;
                        
                        if (current_step >= (seq_len - 1'b1)) begin
                            state <= CHECK_MATCH;
                        end else begin
                            current_step <= current_step + 1'b1;
                        end
                    end

                    // 2-Second Inactivity Timeout check
                    if (!any_key_pressed) begin
                        if (generic_timer >= 25'd23_999_999) begin // 2 Seconds exact
                            state <= PLAY_WAWAWA; // Timeout counts as automatic fail
                        end else begin
                            generic_timer <= generic_timer + 1'b1;
                        end
                    end
                end

                // --- STATE 4: Evaluate Player's Entry vs Simon's Memory Matrix ---
                CHECK_MATCH: begin
                    input_lockout <= 1'b1;
                    
                    // Static inline comparison check against the running step count boundary lengths
                    if ((seq_len > 4'd0  && player_sequence[0]  != simon_sequence[0])  ||
                        (seq_len > 4'd1  && player_sequence[1]  != simon_sequence[1])  ||
                        (seq_len > 4'd2  && player_sequence[2]  != simon_sequence[2])  ||
                        (seq_len > 4'd3  && player_sequence[3]  != simon_sequence[3])  ||
                        (seq_len > 4'd4  && player_sequence[4]  != simon_sequence[4])  ||
                        (seq_len > 4'd5  && player_sequence[5]  != simon_sequence[5])  ||
                        (seq_len > 4'd6  && player_sequence[6]  != simon_sequence[6])  ||
                        (seq_len > 4'd7  && player_sequence[7]  != simon_sequence[7])  ||
                        (seq_len > 4'd8  && player_sequence[8]  != simon_sequence[8])  ||
                        (seq_len > 4'd9  && player_sequence[9]  != simon_sequence[9])  ||
                        (seq_len > 4'd10 && player_sequence[10] != simon_sequence[10]) ||
                        (seq_len > 4'd11 && player_sequence[11] != simon_sequence[11])) begin
                        
                        // BAD MATCH: Failure
                        seq_len <= INIT_SEQ_LEN;
                        state   <= PLAY_WAWAWA;
                    end else begin
                        // GOOD MATCH: Success
                        if (seq_len >= MAX_SEQ_LEN) begin
                            seq_len <= INIT_SEQ_LEN; // Game Completed Victory Reset
                            state   <= PLAY_EXTENDED_TATA;
                        end else begin
                            seq_len <= seq_len + 1'b1; // Advance Level Length
                            state   <= PLAY_TADA;
                        end
                    end
                    generic_timer <= 0;
                end

                // --- STATES 5, 6, 7: Audio Chime Sequence Durations ---
                PLAY_WAWAWA: begin
                    generic_timer <= generic_timer + 1'b1;
                    if (generic_timer >= 25'd8_999_999) begin // ~750ms failure duration
                        generic_timer <= 0;
                        state         <= QUIET_STATE;
                    end
                end

                PLAY_TADA: begin
                    generic_timer <= generic_timer + 1'b1;
                    if (generic_timer >= 25'd5_999_999) begin // ~500ms success duration
                        generic_timer <= 0;
                        state         <= QUIET_STATE;
                    end
                end

                PLAY_EXTENDED_TATA: begin
                    generic_timer <= generic_timer + 1'b1;
                    if (generic_timer >= 25'd17_999_999) begin // ~1.5s victory jingle
                        generic_timer <= 0;
                        state         <= QUIET_STATE;
                    end
                end

                // --- STATE 8: Enforce 2 Seconds of Absolute System Silence ---
                QUIET_STATE: begin
                    input_lockout <= 1'b1;
                    generic_timer <= generic_timer + 1'b1;
                    if (generic_timer >= 25'd23_999_999) begin // 2-second forced freeze
                        generic_timer <= 0;
                        state         <= PLAY_START_TONE; // Restart game loop
                    end
                end

                default: state <= PLAY_START_TONE;
            endcase
        end
    end

    // Helper task function to clear the inactivity watchdog counter window
    task watchdog_clear;
        begin
            generic_timer <= 0;
        end
    endtask

    // ---------------------------------------------------------------------
    // 5. Output Combinatorial Arbitration Routing Logic
    // Maps state-controlled tones and player keys to peripherals seamlessly.
    // ---------------------------------------------------------------------
    always @(*) begin
        case (state)
            PLAY_START_TONE:      arbitrated_key_code = 5'd16; // Audio plays via sequence counter, no lights
            PLAY_SIMON_SEQUENCE:  arbitrated_key_code = simon_sequence[current_step]; // Show Simon's keys
            ENTER_LISTENING_MODE: arbitrated_key_code = matrix_key_code; // Show active presses live
            PLAY_WAWAWA:          arbitrated_key_code = 5'd17; // Route sound-only indices to mixers
            PLAY_TADA:            arbitrated_key_code = 5'd20;
            PLAY_EXTENDED_TATA:   arbitrated_key_code = 5'd21;
            QUIET_STATE:          arbitrated_key_code = 5'd16; // Absolute Off
            default:              arbitrated_key_code = 5'd16;
        endcase
    end

endmodule
