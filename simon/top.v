// =========================================================================
// DECOUPLED HIGH-FIDELITY DTMF ENGINE & GHOST-FREE MATRIX
// Matrix Scan = ~250Hz (Ghost protection) | Audio Loop = 12MHz (Full speed)
// Rows = test_out0..3 | Columns = test_in0..3 via unified input bus
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
    // 2. Continuous Scanning Capture Buffers (One stable bit per key)
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
                raw_keys[8] <= ~cols[0]; raw_keys[9] <= ~cols[1]; 
                raw_keys[10]<= ~cols[2]; raw_keys[11]<= ~cols[3];
            end
            2'b11: begin
                raw_keys[12]<= ~cols[0]; raw_keys[13]<= ~cols[1]; 
                raw_keys[14]<= ~cols[2]; raw_keys[15]<= ~cols[3];
            end
        endcase
    end

    // ---------------------------------------------------------------------
    // 3. Encoder: Map stable buffers directly to key_code
    // ---------------------------------------------------------------------
    reg [4:0] key_code;

    always @(*) begin
        if (raw_keys[0])        key_code = 5'd0;
        else if (raw_keys[1])   key_code = 5'd1;
        else if (raw_keys[2])   key_code = 5'd2;
        else if (raw_keys[3])   key_code = 5'd3;
        else if (raw_keys[4])   key_code = 5'd4;
        else if (raw_keys[5])   key_code = 5'd5;
        else if (raw_keys[6])   key_code = 5'd6;
        else if (raw_keys[7])   key_code = 5'd7;
        else if (raw_keys[8])   key_code = 5'd8;
        else if (raw_keys[9])   key_code = 5'd9;
        else if (raw_keys[10])  key_code = 5'd10;
        else if (raw_keys[11])  key_code = 5'd11;
        else if (raw_keys[12])  key_code = 5'd12;
        else if (raw_keys[13])  key_code = 5'd13;
        else if (raw_keys[14])  key_code = 5'd14;
        else if (raw_keys[15])  key_code = 5'd15;
        else                    key_code = 5'd16; // Stable default off state
    end

    // ---------------------------------------------------------------------
    // 4. Color Generation Table (2-Bit PWM Space)
    // ---------------------------------------------------------------------
    reg [1:0] r_val, g_val, b_val;

    always @(*) begin
        case (key_code)
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
    // 5. High-Speed 12MHz DTMF Divider Targets
    // ---------------------------------------------------------------------
    reg [13:0] row_max;
    reg [13:0] col_max;

    always @(*) begin
        case (key_code)
            5'd0:    begin row_max = 14'd8608; col_max = 14'd4962; end // 1
            5'd1:    begin row_max = 14'd8608; col_max = 14'd4491; end // 2
            5'd2:    begin row_max = 14'd8608; col_max = 14'd4062; end // 3
            5'd3:    begin row_max = 14'd8608; col_max = 14'd3674; end // A
            5'd4:    begin row_max = 14'd7792; col_max = 14'd4962; end // 4
            5'd5:    begin row_max = 14'd7792; col_max = 14'd4491; end // 5
            5'd6:    begin row_max = 14'd7792; col_max = 14'd4062; end // 6
            5'd7:    begin row_max = 14'd7792; col_max = 14'd3674; end // B
            5'd8:    begin row_max = 14'd7042; col_max = 14'd4962; end // 7
            5'd9:    begin row_max = 14'd7042; col_max = 14'd4491; end // 8
            5'd10:   begin row_max = 14'd7042; col_max = 14'd4062; end // 9
            5'd11:   begin row_max = 14'd7042; col_max = 14'd3674; end // C
            5'd12:   begin row_max = 14'd6376; col_max = 14'd4962; end // *
            5'd13:   begin row_max = 14'd6376; col_max = 14'd4491; end // 0
            5'd14:   begin row_max = 14'd6376; col_max = 14'd4062; end // #
            5'd15:   begin row_max = 14'd6376; col_max = 14'd3674; end // D
            default: begin row_max = 14'd0;    col_max = 14'd0;    end 
        endcase
    end

    // ---------------------------------------------------------------------
    // 6. Running Oscillators (Uninterrupted 12MHz execution)
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
    // 7. Passive Audio Mixer
    // ---------------------------------------------------------------------
    reg mix_toggle = 0;
    always @(posedge clk) mix_toggle <= ~mix_toggle;

    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
