// =========================================================================
// DECOUPLED DTMF ENGINE WITH POWER-UP BOOT MELODY & WATCHDOG FIX
// Matrix Scan = ~250Hz | Audio, Boot, & Watchdog Engines = 12MHz
// =========================================================================

module top (
    input  clk,
    
    // 4x4 Matrix Interface Pins
    output reg test_out0, // Row 1
    output reg test_out1, // Row 2
    output reg test_out2, // Row 3
    output reg test_out3, // Row 4
    input      test_in0,  // Column 1
    input      test_in1,  // Column 2
    input      test_in2,  // Column 3
    input      test_in3,  // Column 4

    // Onboard Diagnostic Indicator LEDs (Active-Low)
    output led_r,
    output led_g,
    output led_b,

    // Audio Output Channels
    output audio_l,       // Connects to PMOD2 Pin 1 (iCE40 Pin 46)
    output audio_r        // Connects to PMOD2 Pin 2 (iCE40 Pin 44)
);

    // ---------------------------------------------------------------------
    // 1. Stable, Glitch-Free Row Multiplexer (Run at safe 250Hz rate)
    // ---------------------------------------------------------------------
    reg [1:0]  row_select = 2'b00; 
    reg [15:0] scan_counter = 0;

    always @(posedge clk) begin
        if (scan_counter >= 16'd47999) begin 
            scan_counter <= 0;
            row_select   <= row_select + 1'b1; 
        end else begin
            scan_counter <= scan_counter + 1'b1;
        end
    end

    // Active-Low 1-hot Row Multiplexer Sequence
    always @(*) begin
        case(row_select)
            2'b00: begin test_out0 = 1'b0; test_out1 = 1'b1; test_out2 = 1'b1; test_out3 = 1'b1; end 
            2'b01: begin test_out0 = 1'b1; test_out1 = 1'b0; test_out2 = 1'b1; test_out3 = 1'b1; end 
            2'b10: begin test_out0 = 1'b1; test_out1 = 1'b1; test_out2 = 1'b0; test_out3 = 1'b1; end 
            2'b11: begin test_out0 = 1'b1; test_out1 = 1'b1; test_out2 = 1'b1; test_out3 = 1'b0; end 
        endcase
    end

    // ---------------------------------------------------------------------
    // 2. FIXED: Continuous Capture Buffer with Active Clear
    // ---------------------------------------------------------------------
    wire [3:0] cols = {test_in3, test_in2, test_in1, test_in0};
    reg [15:0] raw_keys = 16'd0;

    always @(posedge clk) begin
        // Clear old row traces completely when a new row is scanned to prevent key traps
        case(row_select)
            2'b00: begin
                raw_keys[3:0]   <= ~cols;
                raw_keys[15:4]  <= raw_keys[15:4]; // Keep others
            end
            2'b01: begin
                raw_keys[7:4]   <= ~cols;
                raw_keys[3:0]   <= raw_keys[3:0];
                raw_keys[15:8]  <= raw_keys[15:8];
            end
            2'b10: begin
                raw_keys[11:8]  <= ~cols;
                raw_keys[7:0]   <= raw_keys[7:0];
                raw_keys[15:12] <= raw_keys[15:12];
            end
            2'b11: begin
                raw_keys[15:12] <= ~cols;
                raw_keys[11:0]  <= raw_keys[11:0];
            end
        endcase
    end

    // ---------------------------------------------------------------------
    // 3. Keypad Matrix Encoder Loop
    // ---------------------------------------------------------------------
    reg [4:0] matrix_key_code;
    wire      any_key_pressed = (matrix_key_code != 5'd16);

    always @(*) begin
        if (raw_keys[0])        matrix_key_code = 5'd0;
        else if (raw_keys[1])   matrix_key_code = 5'd1;
        else if (raw_keys[2])   matrix_key_code = 5'd2;
        else if (raw_keys[3])   matrix_key_code = 5'd3;
        else if (raw_keys[4])   matrix_key_code = 5'd4;
        else if (raw_keys[5])   matrix_key_code = 5'd5;
        else if (raw_keys[6])   matrix_key_code = 5'd6;
        else if (raw_keys[7])   matrix_key_code = 5'd7;
        else if (raw_keys[8])   matrix_key_code = 5'd8;
        else if (raw_keys[9])   matrix_key_code = 5'd9;
        else if (raw_keys[10])  matrix_key_code = 5'd10;
        else if (raw_keys[11])  matrix_key_code = 5'd11;
        else if (raw_keys[12])  matrix_key_code = 5'd12;
        else if (raw_keys[13])  matrix_key_code = 5'd13;
        else if (raw_keys[14])  matrix_key_code = 5'd14;
        else if (raw_keys[15])  matrix_key_code = 5'd15;
        else                    matrix_key_code = 5'd16; 
    end

    // ---------------------------------------------------------------------
    // 4. Power-Up Boot Sequencer State Machine
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
    // 5. 2-Second Inactivity Watchdog & Fail Sequencer
    // ---------------------------------------------------------------------
    reg [24:0] watchdog_timer = 0;
    reg        fail_active = 0;
    reg [1:0]  fail_state = 0;
    reg [22:0] fail_note_timer = 0;
    reg        fail_played = 0; // NEW: Prevents infinite looping after completion

    always @(posedge clk) begin
        if (boot_active) begin
            watchdog_timer  <= 0;
            fail_active     <= 0;
            fail_played     <= 0;
        end else if (any_key_pressed) begin
            // Reset watchdog and clear play lock flag if user touches keypad
            watchdog_timer   <= 0;
            fail_active      <= 0;
            fail_state       <= 0;
            fail_note_timer  <= 0;
            fail_played      <= 0; 
        end else if (!fail_active) begin
            // Only count if failure has not already been played for this cycle
            if (!fail_played) begin
                if (watchdog_timer >= 25'd23_999_999) begin
                    fail_active     <= 1'b1; 
                    fail_state      <= 2'd0;
                    watchdog_timer  <= 0;
                end else begin
                    watchdog_timer  <= watchdog_timer + 1'b1;
                end
            end else begin
                watchdog_timer <= 0;
            end
        end else begin
            watchdog_timer  <= 0; 
            fail_note_timer <= fail_note_timer + 1'b1;
            if (fail_note_timer >= 23'd2_999_999) begin
                fail_note_timer <= 0;
                if (fail_state == 2'd2) begin
                    fail_active    <= 1'b0; 
                    fail_played    <= 1'b1; // Lock failure chime until next keypress
                    watchdog_timer <= 0;    
                end else begin
                    fail_state     <= fail_state + 1'b1;
                end
            end
        end
    end

    // Master Key Arbitration Router
    reg [4:0] active_key_code;
    always @(*) begin
        if (boot_active) begin
            case(boot_state)
                3'd0:    active_key_code = 5'd0;  
                3'd1:    active_key_code = 5'd4;  
                3'd2:    active_key_code = 5'd8;  
                3'd3:    active_key_code = 5'd13; 
                default: active_key_code = 5'd16; 
            endcase
        end else if (fail_active) begin
            case(fail_state)
                2'd0:    active_key_code = 5'd17; 
                2'd1:    active_key_code = 5'd18; 
                2'd2:    active_key_code = 5'd19; 
                default: active_key_code = 5'd16;
            endcase
        end else begin
            active_key_code = matrix_key_code; 
        end
    end

    // ---------------------------------------------------------------------
    // 6. REFACTORED: Isolated RGB Mixer Sub-Module Instantiation
    // ---------------------------------------------------------------------
    rgb_mixer u_rgb_mixer (
        .clk             (clk),
        .active_key_code (active_key_code),
        .led_r           (led_r),
        .led_g           (led_g),
        .led_b           (led_b)
    );

    reg [7:0] pwm_counter = 0;
    always @(posedge clk) pwm_counter <= pwm_counter + 1'b1;
    wire [1:0] pwm_frame = pwm_counter[7:6];

    assign led_r = ~(r_val > pwm_frame);
    assign led_g = ~(g_val > pwm_frame);
    assign led_b = ~(b_val > pwm_frame);

    // ---------------------------------------------------------------------
    // 7. DTMF Tone Frequency Selector Lookup Table
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
            
            default: begin row_max = 14'd0;         col_max = 14'd0;         end
        endcase
    end

    // ---------------------------------------------------------------------
    // 8. Running Audio Oscillators
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
    // 9. Passive Audio Mixer & Output Pin Mapping
    // ---------------------------------------------------------------------
    reg mix_toggle = 0;
    always @(posedge clk) mix_toggle <= ~mix_toggle;

    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
