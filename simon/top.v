// =========================================================================
// FIXED UNIFIED MASTER CONTROLLER ENGINE (top.v)
// Connects modules seamlessly without state/variable arbitration fights.
// =========================================================================

module top (
    input  clk,
    
    // Physical IO Traces routed directly through sub-modules
    output test_out0, test_out1, test_out2, test_out3,
    input  test_in0,  test_in1,  test_in2,  test_in3,

    output led_r, led_g, led_b,
    output audio_l, audio_r
);

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
    // 4. SYNCHRONOUS ARBITRATION ROUTER (Fixed to hold matrix_key_code!)
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
            // FIXED: Locked into a registered always block to map directly to LEDs
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
    // 6. DTMF Tone Frequency Selector Lookup Table
    // ---------------------------------------------------------------------
    localparam ROW1_FREQ_697  = 14'd8608;
    localparam ROW2_FREQ_770  = 14'd7792;
    localparam ROW3_FREQ_852  = 14'd7042;
    localparam ROW4_FREQ_941  = 14'd6376;
    
    localparam COL1_FREQ_1209 = 14'd4962;
    localparam COL2_FREQ_1336 = 14'd4491;
    localparam COL3_FREQ_1477 = 14'd4062;
    localparam COL4_FREQ_1633 = 14'd3674;

    reg [13:0] row_max;
    reg [13:0] col_max;

    always @(*) begin
        case (active_key_code)
            5'd0:    begin row_max = ROW1_FREQ_697; col_max = COL1_FREQ_1209; end
            5'd1:    begin row_max = ROW1_FREQ_697; col_max = COL2_FREQ_1336; end
            5'd2:    begin row_max = ROW1_FREQ_697; col_max = COL3_FREQ_1477; end
            5'd3:    begin row_max = ROW1_FREQ_697; col_max = COL4_FREQ_1633; end
            
            5'd4:    begin row_max = ROW2_FREQ_770; col_max = COL1_FREQ_1209; end
            5'd5:    begin row_max = ROW2_FREQ_770; col_max = COL2_FREQ_1336; end
            5'd6:    begin row_max = ROW2_FREQ_770; col_max = COL3_FREQ_1477; end
            5'd7:    begin row_max = ROW2_FREQ_770; col_max = COL4_FREQ_1633; end
            
            5'd8:    begin row_max = ROW3_FREQ_852; col_max = COL1_FREQ_1209; end
            5'd9:    begin row_max = ROW3_FREQ_852; col_max = COL2_FREQ_1336; end
            5'd10:   begin row_max = ROW3_FREQ_852; col_max = COL3_FREQ_1477; end
            5'd11:   begin row_max = ROW3_FREQ_852; col_max = COL4_FREQ_1633; end
            
            5'd12:   begin row_max = ROW4_FREQ_941; col_max = COL1_FREQ_1209; end
            5'd13:   begin row_max = ROW4_FREQ_941; col_max = COL2_FREQ_1336; end
            5'd14:   begin row_max = ROW4_FREQ_941; col_max = COL3_FREQ_1477; end
            5'd15:   begin row_max = ROW4_FREQ_941; col_max = COL4_FREQ_1633; end
            
            5'd17:   begin row_max = ROW4_FREQ_941; col_max = 14'd0;         end
            5'd18:   begin row_max = ROW3_FREQ_852; col_max = 14'd0;         end
            5'd19:   begin row_max = ROW2_FREQ_770; col_max = 14'd0;         end
            
            5'd20:   begin row_max = 14'd3000;      col_max = 14'd0;         end 
            5'd21:   begin row_max = 14'd2000;      col_max = 14'd0;         end 
            
            default: begin row_max = 14'd0;         col_max = 14'd0;         end
        endcase
    end

    // ---------------------------------------------------------------------
    // 7. Running Audio Oscillators
    // ---------------------------------------------------------------------
    reg [13:0] row_counter = 0;
    reg [13:0] col_counter = 0;
    reg        row_square = 0;
    reg        col_square = 0;

    always @(posedge clk) begin
        if (row_max == 14'd0) begin
            row_counter <= 0;
            row_square  <= 0;
        end else if (row_counter >= row_max) begin
            row_counter <= 0;
            row_square  <= ~row_square;
        end else begin
            row_counter <= row_counter + 1'b1;
        end

        if (col_max == 14'd0) begin
            col_counter <= 0;
            col_square  <= 0;
        end else if (col_counter >= col_max) begin
            col_counter <= 0;
            col_square  <= ~col_square;
        end else begin
            col_counter <= col_counter + 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // 8. Passive Audio Mixer & Output Pin Mapping
    // ---------------------------------------------------------------------
    reg mix_toggle = 0;
    
    always @(posedge clk) begin
        mix_toggle <= ~mix_toggle;
    end

    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
