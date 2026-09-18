// =========================================================================
// REFACTORED 4x4 MATRIX DECODER (COLUMN SELECT PATTERN)
// Rows = test_out0..3 | Columns = test_in0..3 via unified input bus
// key_code: 0 to 15 = Active Keys, 16 = Idle/Off
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
    output led_b
);

    // ---------------------------------------------------------------------
    // 1. Internal Scan Multiplexer Clock (Row Pointers)
    // ---------------------------------------------------------------------
    reg [1:0]  row_select = 2'b00; 
    reg [11:0] scan_counter = 0;
    reg [1:0] r_val, g_val, b_val;

    always @(posedge clk) begin
        if (scan_counter >= 12'd3999) begin 
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
    // 2. Column Select Array & Latch Register Arrays
    // ---------------------------------------------------------------------
    wire [3:0] cols = {test_in3, test_in2, test_in1, test_in0}; // Unified vector input
    reg  [1:0] col_select;
    reg        key_found;

    // Decode active low column inputs down to a 2-bit selection index
    always @(*) begin
        col_select = 2'b00;
        key_found  = 1'b0;
        if (!cols[0])      begin col_select = 2'b00; key_found = 1'b1; end
        else if (!cols[1]) begin col_select = 2'b01; key_found = 1'b1; end
        else if (!cols[2]) begin col_select = 2'b10; key_found = 1'b1; end
        else if (!cols[3]) begin col_select = 2'b11; key_found = 1'b1; end
    end

    // ---------------------------------------------------------------------
    // 3. Encoder: Map row_select + col_select into a single 5-bit key_code
    // ---------------------------------------------------------------------
    reg [4:0] key_code = 5'd16;

    always @(posedge clk) begin
        if (key_found) begin
            // Math shortcut mapping: (row * 4) + column
            key_code <= {row_select, col_select}; 
        end else begin
            // Optional sweep clean: Only release code if the active row scanning has no press
            // Keeps the key output continuous across the alternate matrix cycles
            if (scan_counter == 12'd0) begin
                key_code <= 5'd16; 
            end
        end
    end


    always @(*) begin
        case (key_code)
            5'd0:  begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd0; end // 0. Pure Red
            5'd1:  begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd0; end // 1. Pure Green
            5'd2:  begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd3; end // 2. Pure Blue
            5'd3:  begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd0; end // 3. Bright Yellow
            5'd4:  begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd3; end // 4. Cyan
            5'd5:  begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd3; end // 5. Magenta
            5'd6:  begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd3; end // 6. Pure White
            5'd7:  begin r_val = 2'd1; g_val = 2'd1; b_val = 2'd1; end // 7. Dim Grey
            5'd8:  begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd0; end // 8. Orange
            5'd9:  begin r_val = 2'd1; g_val = 2'd3; b_val = 2'd0; end // 9. Lime Green
            5'd10: begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd1; end // 10. Soft Pink
            5'd11: begin r_val = 2'd1; g_val = 2'd0; b_val = 2'd3; end // 11. Deep Violet
            5'd12: begin r_val = 2'd0; g_val = 2'd1; b_val = 2'd3; end // 12. Sky Blue
            5'd13: begin r_val = 2'd0; g_val = 2'd2; b_val = 2'd1; end // 13. Dark Teal
            5'd14: begin r_val = 2'd3; g_val = 2'd2; b_val = 2'd0; end // 14. Amber / Gold
            5'd15: begin r_val = 2'd2; g_val = 2'd0; b_val = 2'd2; end // 15. Plum / Dark Purple
            
            // 16. Default Idle State (Completely Turn off LEDs)
            5'd16: begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd0; end 
            
            default: begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd0; end
        endcase
    end


    // ---------------------------------------------------------------------
    // 5. Fast 2-Bit PWM Modulation Engine
    // ---------------------------------------------------------------------
    reg [7:0] pwm_counter = 0;
    
    always @(posedge clk) begin
        pwm_counter <= pwm_counter + 1'b1;
    end

    wire [1:0] pwm_frame = pwm_counter[7:6];

    // Inverted (~) out for iCE Sugar active-low diagnostic LEDs
    assign led_r = ~(r_val > pwm_frame);
    assign led_g = ~(g_val > pwm_frame);
    assign led_b = ~(b_val > pwm_frame);


endmodule
