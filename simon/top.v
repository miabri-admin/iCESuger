// =========================================================================
// DECOUPLED DTMF ENGINE WITH POWER-UP BOOT MELODY SCALE
// Plays a rising scale on startup, then transitions to 4x4 matrix keypad.
// Matrix Scan = ~250Hz | Audio & Boot Engine = 12MHz
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
    // 2. Continuous Scanning Capture Buffers
    // ---------------------------------------------------------------------
    wire [3:0] cols = {test_in3, test_in2, test_in1, test_in0};
    reg [15:0] raw_keys = 16'd0;

    always @(posedge clk) begin
        case(row_select)
            2'b00: begin
                raw_keys[0] <= ~cols[0]; raw_keys[1] <= ~cols[1]; 
                raw_keys[2] <= ~cols[2]; raw_keys[3] <= ~cols[3];
            end
            2'b01: begin
                raw_keys[4] <= ~cols[0]; raw_keys[5] <= ~cols[1]; 
                raw_keys[6] <= ~cols[2]; raw_keys[7] <= ~cols[3];
            end
            2'b10: begin
                raw_keys[8]  <= ~cols[0]; raw_keys[9]  <= ~cols[1]; 
                raw_keys[10] <= ~cols[2]; raw_keys[11] <= ~cols[3];
            end
            2'b11: begin
                raw_keys[12] <= ~cols[0]; raw_keys[13] <= ~cols[1]; 
                raw_keys[14] <= ~cols[2]; raw_keys[15] <= ~cols[3];
            end
        endcase
    end

    // ---------------------------------------------------------------------
    // 3. Keypad Matrix Encoder Loop
    // ---------------------------------------------------------------------
    reg [4:0] matrix_key_code;

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
    reg [21:0] boot_timer = 0;   // Controls how long each note plays (~0.15s per note)
    reg [2:0]  boot_state = 0;   // Steps through 4 rising notes, then goes to state 4 (Done)
    reg        boot_active = 1;  // High on boot, drops to low when melody ends
    reg [4:0]  boot_key_code;

    always @(posedge clk) begin
        if (boot_active) begin
            boot_timer <= boot_timer + 1'b1;
            if (boot_timer >= 22'd1_999_999) begin // Switch notes roughly every 165ms
                boot_timer <= 0;
                if (boot_state >= 3'd4) begin
                    boot_active <= 0; // Turn off boot control permanently
                end else begin
                    boot_state  <= boot_state + 1'b1;
                end
            end
        end
    end

    // Route the active note assignments to the audio lookup matrix during startup
    always @(*) begin
        if (boot_active) begin
            case(boot_state)
                3'd0:    boot_key_code = 5'd0;  // First low note (Key 1 frequencies)
                3'd1:    boot_key_code = 5'd4;  // Second note (Key 4 frequencies)
                3'd2:    boot_key_code = 5'd8;  // Third note (Key 7 frequencies)
                3'd3:    boot_key_code = 5'd13; // Highest rising note (Key 0 frequencies)
                default: boot_key_code = 5'd16; // Rest / Silent step
            endcase
        end else begin
            boot_key_code = matrix_key_code; // Handover complete control back to keypad matrix
        end
    end

    // ---------------------------------------------------------------------
    // 5. Visual Color Mapping Engine
    // ---------------------------------------------------------------------
    reg [1:0] r_val, g_val, b_val;

    always @(*) begin
        case (boot_key_code) // Switched to respond dynamically to the boot sequence too!
            5'd0:  begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd0; end 
            5'd1:  begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd0; end 
            5'd2:  begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd3; end 
            5'd3:  begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd0; end 
            5'd4:  begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd3; end 
            5'd5:  begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd3; end 
            5'd6:  begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd3; end 
            5'd7:  begin r_val = 2'd1; g_val = 2'd1; b_val = 2'd1; end 
            5'd8:  begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd0; end 
            5'd9:  begin r_val = 2'd1; g_val = 2'd3; b_val = 2'd0; end 
            5'd10: begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd1; end 
            5'd11: begin r_val = 2'd1; g_val = 2'd0; b_val = 2'd3; end 
            5'd12: begin r_val = 2'd0; g_val = 2'd1; b_val = 2'd3; end 
            5'd13: begin r_val = 2'd0; g_val = 2'd2; b_val = 2'd1; end 
            5'd14: begin r_val = 2'd3; g_val = 2'd2; b_val = 2'd0; end 
            5'd15: begin r_val = 2'd2; g_val = 2'd0; b_val = 2'd2; end 
            default: begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd0; end
        endcase
    end

    reg [7:0] pwm_counter = 0;
    always @(posedge clk) pwm_counter <= pwm_counter + 1'b1;
    wire [1:0] pwm_frame = pwm_counter[7:6];

    assign led_r = ~(r_val > pwm_frame);
    assign led_g = ~(g_val > pwm_frame);
    assign led_b = ~(b_val > pwm_frame);

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
        case (boot_key_code)
            5'd0:    begin row_max = ROW1_FREQ_697; col_max = COL1_FREQ_1209; end // Key '1'
            5'd1:    begin row_max = ROW1_FREQ_697; col_max = COL2_FREQ_1336; end // Key '2'
            5'd2:    begin row_max = ROW1_FREQ_697; col_max = COL3_FREQ_1477; end // Key '3'
            5'd3:    begin row_max = ROW1_FREQ_697; col_max = COL4_FREQ_1633; end // Key 'A'
            5'd4:    begin row_max = ROW2_FREQ_770; col_max = COL1_FREQ_1209; end // Key '4'
            5'd5:    begin row_max = ROW2_FREQ_770; col_max = COL2_FREQ_1336; end // Key '5'
            5'd6:    begin row_max = ROW2_FREQ_770; col_max = COL3_FREQ_1477; end // Key '6'
            5'd7:    begin row_max = ROW2_FREQ_770; col_max = COL4_FREQ_1633; end // Key 'B'
            5'd8:    begin row_max = ROW3_FREQ_852; col_max = COL1_FREQ_1209; end // Key '7'
            5'd9:    begin row_max = ROW3_FREQ_852; col_max = COL2_FREQ_1336; end // Key '8'
            5'd10:   begin row_max = ROW3_FREQ_852; col_max = COL3_FREQ_1477; end // Key '9'
            5'd11:   begin row_max = ROW3_FREQ_852; col_max = COL4_FREQ_1633; end // Key 'C'
            5'd12:   begin row_max = ROW4_FREQ_941; col_max = COL1_FREQ_1209; end // Key '*'
            5'd13:   begin row_max = ROW4_FREQ_941; col_max = COL2_FREQ_1336; end // Key '0'
            5'd14:   begin row_max = ROW4_FREQ_941; col_max = COL3_FREQ_1477; end // Key '#'
            5'd15:   begin row_max = ROW4_FREQ_941; col_max = COL4_FREQ_1633; end // Key 'D'
            default: begin row_max = 14'd0;         col_max = 14'd0;
             end
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
    always @(posedge clk) mix_toggle <= ~mix_toggle;

    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
