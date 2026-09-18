// =========================================================================
// FULL 4x4 MATRIX DECODER (16 KEYS MAPPED 0-15, 16 = DEFAULT OFF)
// Rows = test_out0..3 | Columns = test_in0..3
// key_code: 0 to 15 = Active Keys, 16 = Idle/Off
// =========================================================================

module top (
    input  clk,
    
    // Expanded 4x4 Matrix Interface Pins
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
    // 1. Internal Scan Multiplexer Clock (Upgraded for 4 Rows)
    // ---------------------------------------------------------------------
    reg [1:0]  row_select = 2'b00; // 2-bit pointer for 4 rows
    reg [11:0] scan_counter = 0;

    always @(posedge clk) begin
        if (scan_counter >= 12'd3999) begin 
            scan_counter <= 0;
            row_select   <= row_select + 1'b1; // Steps cleanly through 00 -> 01 -> 10 -> 11
        end else begin
            scan_counter <= scan_counter + 1'b1;
        end
    end

    // Active-Low 1-hot Row Multiplexer Sequence
    always @(*) begin
        case(row_select)
            2'b00: begin test_out0 = 1'b0; test_out1 = 1'b1; test_out2 = 1'b1; test_out3 = 1'b1; end // Row 1 Active
            2'b01: begin test_out0 = 1'b1; test_out1 = 1'b0; test_out2 = 1'b1; test_out3 = 1'b1; end // Row 2 Active
            2'b10: begin test_out0 = 1'b1; test_out1 = 1'b1; test_out2 = 1'b0; test_out3 = 1'b1; end // Row 3 Active
            2'b11: begin test_out0 = 1'b1; test_out1 = 1'b1; test_out2 = 1'b1; test_out3 = 1'b0; end // Row 4 Active
        endcase
    end

    // ---------------------------------------------------------------------
    // 2. Full 16-Key Continuous Scanning Capture Buffer
    // ---------------------------------------------------------------------
    reg raw_k0=0, raw_k1=0, raw_k2=0, raw_k3=0;
    reg raw_k4=0, raw_k5=0, raw_k6=0, raw_k7=0;
    reg raw_k8=0, raw_k9=0, raw_k10=0, raw_k11=0;
    reg raw_k12=0, raw_k13=0, raw_k14=0, raw_k15=0;

    always @(posedge clk) begin
        if (test_out0 == 1'b0) begin 
            raw_k0 <= ~test_in0; raw_k1 <= ~test_in1; raw_k2 <= ~test_in2; raw_k3 <= ~test_in3;
        end 
        if (test_out1 == 1'b0) begin 
            raw_k4 <= ~test_in0; raw_k5 <= ~test_in1; raw_k6 <= ~test_in2; raw_k7 <= ~test_in3;
        end
        if (test_out2 == 1'b0) begin 
            raw_k8 <= ~test_in0; raw_k9 <= ~test_in1; raw_k10 <= ~test_in2; raw_k11 <= ~test_in3;
        end
        if (test_out3 == 1'b0) begin 
            raw_k12 <= ~test_in0; raw_k13 <= ~test_in1; raw_k14 <= ~test_in2; raw_k15 <= ~test_in3;
        end
    end

    // ---------------------------------------------------------------------
    // 3. Encoder: Prioritised 16-Key Map to numeric values 0-15 (16 = idle)
    // ---------------------------------------------------------------------
    reg [4:0] key_code; 

    always @(*) begin
        if (raw_k0)        key_code = 5'd0;
        else if (raw_k1)   key_code = 5'd1;
        else if (raw_k2)   key_code = 5'd2;
        else if (raw_k3)   key_code = 5'd3;
        else if (raw_k4)   key_code = 5'd4;
        else if (raw_k5)   key_code = 5'd5;
        else if (raw_k6)   key_code = 5'd6;
        else if (raw_k7)   key_code = 5'd7;
        else if (raw_k8)   key_code = 5'd8;
        else if (raw_k9)   key_code = 5'd9;
        else if (raw_k10)  key_code = 5'd10;
        else if (raw_k11)  key_code = 5'd11;
        else if (raw_k12)  key_code = 5'd12;
        else if (raw_k13)  key_code = 5'd13;
        else if (raw_k14)  key_code = 5'd14;
        else if (raw_k15)  key_code = 5'd15;
        else               key_code = 5'd16; // Default state: Nothing pressed -> LEDs Off
    end

    // ---------------------------------------------------------------------
    // 4. 17-State Distinct Mix Look-up (PWM Level Blending Matrix)
    // ---------------------------------------------------------------------
    reg [1:0] r_val;
    reg [1:0] g_val;
    reg [1:0] b_val;

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
