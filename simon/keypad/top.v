// =========================================================================
// FIXED 2x2 MATRIX DECODER (0-3 KEY INDEX, 16 = DEFAULT OFF)
// Rows = test_out, test_out2 | Columns = test_in, test_in2
// key_code: 0=Key1, 1=Key2, 2=Key3, 3=Key4, 16=Idle/Off
// =========================================================================

module top (
    input  clk,
    
    // Matrix Interface Pins
    output reg test_out,  // Row 1
    output reg test_out2, // Row 2
    input      test_in,   // Column 1
    input      test_in2,  // Column 2

    // Onboard Diagnostic Indicator LEDs (Active-Low)
    output led_r,
    output led_g,
    output led_b
);

    // ---------------------------------------------------------------------
    // 1. Internal Scan Multiplexer Clock
    // ---------------------------------------------------------------------
    reg        row_select = 0;
    reg [11:0] scan_counter = 0;

    always @(posedge clk) begin
        if (scan_counter >= 12'd3999) begin 
            scan_counter <= 0;
            row_select   <= ~row_select;   
        end else begin
            scan_counter <= scan_counter + 1'b1;
        end
    end

    // Drive rows active-low depending on the current select state
    always @(*) begin
        if (row_select == 1'b0) begin
            test_out  = 1'b0; // Drive Row 1 LOW
            test_out2 = 1'b1; // Keep Row 2 HIGH
        end else begin
            test_out  = 1'b1; // Keep Row 1 HIGH
            test_out2 = 1'b0; // Drive Row 2 LOW
        end
    end

    // ---------------------------------------------------------------------
    // 2. Continuous Scanning Capture Buffer
    // ---------------------------------------------------------------------
    reg raw_key1 = 0;
    reg raw_key2 = 0;
    reg raw_key3 = 0;
    reg raw_key4 = 0;

    always @(posedge clk) begin
        if (test_out == 1'b0) begin 
            raw_key1 <= ~test_in;   // Sample Key 1
            raw_key2 <= ~test_in2;  // Sample Key 2
        end 
        if (test_out2 == 1'b0) begin 
            raw_key3 <= ~test_in;   // Sample Key 3
            raw_key4 <= ~test_in2;  // Sample Key 4
        end
    end

    // ---------------------------------------------------------------------
    // 3. Encoder: Map the 4 raw keys into your 0-3 index line (16 = idle)
    // ---------------------------------------------------------------------
    reg [4:0] key_code; // 5-bit register holds values 0 to 16 safely

    always @(*) begin
        if (raw_key1)      key_code = 5'd0;
        else if (raw_key2) key_code = 5'd1;
        else if (raw_key3) key_code = 5'd2;
        else if (raw_key4) key_code = 5'd3;
        else               key_code = 5'd16; // Default state: Not pressed
    end

    // ---------------------------------------------------------------------
    // 4. 17-State Distinct Mix Matrix Look-up (Fixed Widths & State 16)
    // Brightness ranges from 2'd0 (Off) to 2'd3 (Full Brightness)
    // ---------------------------------------------------------------------
    reg [1:0] r_val;
    reg [1:0] g_val;
    reg [1:0] b_val;

    always @(*) begin
        case (key_code)
            5'd0:  begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd0; end // Key 1 = Pure Red
            5'd1:  begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd0; end // Key 2 = Pure Green
            5'd2:  begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd3; end // Key 3 = Pure Blue
            5'd3:  begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd0; end // Key 4 = Bright Yellow
            
            // Unused slots for potential future expanded keys (4 to 15)
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
            
            // 16. Default Not Pressed (Completely Turn off LEDs)
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

    // Inverted (~) because the iCE Sugar RGB LEDs are structurally Active-Low.
    assign led_r = ~(r_val > pwm_frame);
    assign led_g = ~(g_val > pwm_frame);
    assign led_b = ~(b_val > pwm_frame);

endmodule
