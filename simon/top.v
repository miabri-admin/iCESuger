// =========================================================================
// FIXED UNIFIED MASTER CONTROLLER ENGINE (top.v)
// Integrates isolated scanner, mixer, and audio engine blocks safely.
// =========================================================================

module top (
    input  clk,
    
    // Physical IO Traces routed directly through sub-modules
    output test_out0, test_out1, test_out2, test_out3,
    input  test_in0,  test_in1,  test_in2,  test_in3,

    output led_r, led_g, led_b,
    output audio_l, audio_r
);

    localparam INIT_SEQ_LEN  = d3;

    localparam MAX_SEQ_LEN = 12; // Use integer literal for array dimensions

    // 2. The Random Game Sequence Array
    // Holds 3 elements, where each slot is 5 bits wide (capable of storing 0-31)
    reg [4:0] simon_sequence [0:MAX_SEQ_LEN-1];

    // 3. The Player's Input Response Array
    // Identical structural dimensions to match and compare against Simon
    reg [4:0] player_sequence [0:MAX_SEQ_LEN-1];



    // Internal interconnecting wire routing links from scanner
    wire [4:0] matrix_key_code;
    wire       any_key_pressed;

    // ---------------------------------------------------------------------
    // 1. Instantiation of Isolated Keypad Scanner Module
    // ---------------------------------------------------------------------
    keypad_scanner u_keypad_scanner (
        .clk             (clk),
        .test_out0       (test_out0),
        .test_out1       (test_out1),
        .test_out2       (test_out2),
        .test_out3       (test_out3),
        .test_in0        (test_in0),
        .test_in1        (test_in1),
        .test_in2        (test_in2),
        .test_in3        (test_in3),
        .matrix_key_code (matrix_key_code),
        .any_key_pressed (any_key_pressed)
    );

    // ---------------------------------------------------------------------
    // 2. Power-Up Boot Sequencer State Machine
    // ---------------------------------------------------------------------
    reg [21:0] boot_timer = 0;   
    reg [2:0]  boot_state = 0;   
    reg        boot_active = 1;  

    always @(posedge clk) begin
        if (boot_active) begin
            boot_timer <= boot_timer + 1'b1;
            if (boot_timer >= 22'd1_999_999) begin 
                boot_timer <= 0;
                if (boot_state >= 3'd4) begin
                    boot_active <= 0; 
                end else begin
                    boot_state  <= boot_state + 1'b1;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 3. Code Tracker, Watchdog, & Chime Sequencer
    // ---------------------------------------------------------------------
    reg [24:0] watchdog_timer = 0;
    reg [1:0]  input_count = 0; 
    reg        last_pressed_state = 0;
    
    reg        tada_active = 0;
    reg        fail_active = 0;
    reg        chime_played = 0;
    reg [1:0]  chime_state = 0;
    reg [22:0] chime_note_timer = 0;
    
    // Explicit password slots to verify 1234
    reg [4:0] slot0, slot1, slot2;

    always @(posedge clk) begin
        if (boot_active) begin
            watchdog_timer      <= 0;
            input_count         <= 0;
            tada_active         <= 0;
            fail_active         <= 0;
            chime_played        <= 0;
            last_pressed_state  <= 0;
            slot0 <= 5'd16; slot1 <= 5'd16; slot2 <= 5'd16;
        end else begin
            // Catch clean finger edges
            last_pressed_state <= any_key_pressed;

            if (any_key_pressed) begin
                watchdog_timer <= 0;
                if (chime_played) begin
                    chime_played <= 0; // Release lockouts when user starts typing again
                    input_count  <= 0;
                end
            end

            // --- ON FINGER RELEASE: Log code sequence ---
            if (last_pressed_state && !any_key_pressed && !tada_active && !fail_active && !chime_played) begin
                case (input_count)
                    2'd0: begin slot0 <= matrix_key_code; input_count <= 2'd1; end
                    2'd1: begin slot1 <= matrix_key_code; input_count <= 2'd2; end
                    2'd2: begin slot2 <= matrix_key_code; input_count <= 2'd3; end
                    2'd3: begin 
                        // Verify absolute pattern status (1-2-3-4 entered)
                        if (slot0 == 5'd0 && slot1 == 5'd1 && slot2 == 5'd2 && matrix_key_code == 5'd4) begin
                            tada_active <= 1'b1;
                        end else begin
                            fail_active <= 1'b1;
                        end
                        input_count      <= 2'd0;
                        chime_state      <= 2'd0;
                        chime_note_timer <= 0;
                    end
                endcase
            end

            // --- WATCHDOG FAILURE TIMEOUT (2 SECONDS) ---
            if (!any_key_pressed && !tada_active && !fail_active && !chime_played) begin
                if (watchdog_timer >= 25'd23_999_999) begin 
                    fail_active    <= 1'b1; 
                    chime_state    <= 2'd0;
                    watchdog_timer <= 0;
                    input_count    <= 2'd0;
                end else begin
                    watchdog_timer <= watchdog_timer + 1'b1;
                end
            end

            // --- ACTIVE SOUND EFFECT SEQUENCERS ---
            if (tada_active || fail_active) begin
                watchdog_timer   <= 0;
                chime_note_timer <= chime_note_timer + 1'b1;
                
                if (chime_note_timer >= 23'd2_999_999) begin
                    chime_note_timer <= 0;
                    
                    if ((tada_active && chime_state == 2'd1) || (fail_active && chime_state == 2'd2)) begin
                        tada_active  <= 1'b0;
                        fail_active  <= 1'b0;
                        chime_played <= 1'b1; // Lock system into silent standby
                        slot0 <= 5'd16; slot1 <= 5'd16; slot2 <= 5'd16;
                    end else begin
                        chime_state <= chime_state + 1'b1;
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 4. SYNCHRONOUS ARBITRATION ROUTER
    // ---------------------------------------------------------------------
    reg [4:0] active_key_code;
    
    always @(posedge clk) begin
        if (boot_active) begin
            case(boot_state)
                3'd0:    active_key_code <= 5'd0;  
                3'd1:    active_key_code <= 5'd4;  
                3'd2:    active_key_code <= 5'd8;  
                3'd3:    active_key_code <= 5'd13; 
                default: active_key_code <= 5'd16; 
            endcase
        end else if (tada_active) begin
            case(chime_state)
                2'd0:    active_key_code <= 5'd20; 
                2'd1:    active_key_code <= 5'd21; 
                default: active_key_code <= 5'd16;
            endcase
        end else if (fail_active) begin
            case(chime_state)
                2'd0:    active_key_code <= 5'd17; 
                2'd1:    active_key_code <= 5'd18; 
                2'd2:    active_key_code <= 5'd19; 
                default: active_key_code <= 5'd16;
            endcase
        end else begin
            active_key_code <= matrix_key_code; 
        end
    end

    // ---------------------------------------------------------------------
    // 5. Instantiation of Isolated RGB Mixer Module
    // ---------------------------------------------------------------------
    rgb_mixer u_rgb_mixer (
        .clk             (clk),
        .active_key_code (active_key_code),
        .led_r           (led_r),
        .led_g           (led_g),
        .led_b           (led_b)
    );

    // ---------------------------------------------------------------------
    // 6. Instantiation of Isolated Audio Engine Module
    // ---------------------------------------------------------------------
    audio_engine u_audio_engine (
        .clk             (clk),
        .active_key_code (active_key_code),
        .audio_l         (audio_l),
        .audio_r         (audio_r)
    );

endmodule
