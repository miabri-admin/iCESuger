// =========================================================================
// SIMPLE 2x2 TO 4-KEY PASSTHROUGH CONVERTER
// Rows = test_out, test_out2 | Columns = test_in, test_in2
// =========================================================================

module top (
    input  clk,
    
    // Your exact Matrix pins
    output reg test_out,  // Row 1 (PMOD1 Pin 1)
    output reg test_out2, // Row 2
    input      test_in,   // Column 1 (PMOD4 Pin 1)
    input      test_in2,  // Column 2

    // Onboard Diagnostic Indicator LEDs (Active-Low)
    output led_r,
    output led_g,
    output led_b
);

    // ---------------------------------------------------------------------
    // 1. Internal Scan Registers & Generated Outputs
    // ---------------------------------------------------------------------
    reg        row_select = 0;
    reg [11:0] scan_counter = 0;

    // The 4 generated separate key channels (1 = Pressed, 0 = Idle)
    reg key1, key2, key3, key4;

    // Rapidly toggle row_select to alternate between rows
    always @(posedge clk) begin
        if (scan_counter >= 12'd3999) begin 
            scan_counter <= 0;
            row_select   <= ~row_select;   
        end else begin
            scan_counter <= scan_counter + 1'b1;
        end
    end

    // Active-Low Row multiplexer configuration
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
    // 2. Sample and Decode columns into 4 independent variables
    // ---------------------------------------------------------------------
    always @(posedge clk) begin
        if (test_out == 1'b0) begin // Sampling Row 1
            key1 <= ~test_in;   // Row 1, Col 1
            key2 <= ~test_in2;  // Row 1, Col 2
        end else if (test_out2 == 1'b0) begin // Sampling Row 2
            key3 <= ~test_in;   // Row 2, Col 1
            key4 <= ~test_in2;  // Row 2, Col 2
        end
    end

    // ---------------------------------------------------------------------
    // 3. Visual Pass-Through mapping to RGB LEDs
    // Active-Low LEDs mean 1'b0 turns them ON.
    // ---------------------------------------------------------------------
    //assign led_r = ~key1;          // Key 1 turns on RED
    //assign led_g = ~key2;          // Key 2 turns on GREEN
    
    assign led_b = ~key3;          // Key 3 turns on BLUE
    
    // Key 4 turns on RED + GREEN (Creates Yellow) so you can test all four
    assign led_r = ~(key1 | key4);
    assign led_g = ~(key2 | key4);

endmodule
