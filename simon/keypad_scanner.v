// =========================================================================
// ISOLATED 4x4 MATRIX KEYPAD SCANNER MODULE WITH HOLD-LATCH & INACTIVITY DELAY
// HARDENED CONFIGURATION: Enforces a strict 150ms minimum press threshold.
// =========================================================================

module keypad_scanner (
    input            clk,             
    
    // Physical Layout Bus Connections
    output reg       test_out0,       
    output reg       test_out1,       
    output reg       test_out2,       
    output reg       test_out3,       
    input            test_in0,        
    input            test_in1,        
    input            test_in2,        
    input            test_in3,        

    // Decoded Outputs handed up to Upper-Level Engines
    output reg [4:0] matrix_key_code      = 5'd16, 
    output reg       any_key_pressed      = 1'b0,
    output reg       final_key_released   = 1'b0  // Fires 1 cycle on release after 2s quiet
);

    localparam WAIT_TO_SEE_KEY_DELAY = 22'd1800000; // 150 ms: 

    // ---------------------------------------------------------------------
    // 1. Stable Row Multiplexer Clock Generator (~250Hz Row Sweeping)
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
    // 2. Hardware Capture Buffer Matrix Array with Active Clear
    // ---------------------------------------------------------------------
    wire [3:0] cols = {test_in3, test_in2, test_in1, test_in0};
    reg [15:0] raw_keys = 16'd0;

    always @(posedge clk) begin
        case(row_select)
            2'b00: begin raw_keys[3:0]   <= ~cols; raw_keys[15:4]  <= raw_keys[15:4];   end
            2'b01: begin raw_keys[7:4]   <= ~cols; raw_keys[3:0]   <= raw_keys[3:0];   raw_keys[15:8]  <= raw_keys[15:8];  end
            2'b10: begin raw_keys[11:8]  <= ~cols; raw_keys[7:0]   <= raw_keys[7:0];   raw_keys[15:12] <= raw_keys[15:12]; end
            2'b11: begin raw_keys[15:12] <= ~cols; raw_keys[11:0]  <= raw_keys[11:0];  end
        endcase
    end

    // ---------------------------------------------------------------------
    // 3. Look-up Combinatorial Encoder Array with Latch Memory
    // ---------------------------------------------------------------------
    reg [4:0] detected_code;

    always @(*) begin
        if (raw_keys[0])        detected_code = 5'd0;
        else if (raw_keys[1])   detected_code = 5'd1;
        else if (raw_keys[2])   detected_code = 5'd2;
        else if (raw_keys[3])   detected_code = 5'd3;
        else if (raw_keys[4])   detected_code = 5'd4;
        else if (raw_keys[5])   detected_code = 5'd5;
        else if (raw_keys[6])   detected_code = 5'd6;
        else if (raw_keys[7])   detected_code = 5'd7;
        else if (raw_keys[8])   detected_code = 5'd8;
        else if (raw_keys[9])   detected_code = 5'd9;
        else if (raw_keys[10])  detected_code = 5'd10;
        else if (raw_keys[11])  detected_code = 5'd11;
        else if (raw_keys[12])  detected_code = 5'd12;
        else if (raw_keys[13])  detected_code = 5'd13;
        else if (raw_keys[14])  detected_code = 5'd14;
        else if (raw_keys[15])  detected_code = 5'd15;
        else                    detected_code = 5'd16; 
    end

    // ---------------------------------------------------------------------
    // 4. Time-Locked Filter Pipeline & Final Timeout Pulse Generation
    // ---------------------------------------------------------------------
    reg [21:0] press_timer      = 0;    // Counter for 300ms limit verification
    reg [24:0] inactivity_timer = 0;
    reg        has_pressed      = 1'b0; 

    always @(posedge clk) begin
        // --- 300ms PRESS DEBOUNCE EVALUATION STAGE ---
        if (detected_code != 5'd16) begin
            // A key is actively making contact. Increment the verification timer.
            if (press_timer < WAIT_TO_SEE_KEY_DELAY) begin
                press_timer     <= press_timer + 1'b1;
                // KEEP SUPPRESSED: Hold outputs at idle until held long enough
                matrix_key_code <= 5'd16;
                any_key_pressed <= 1'b0;
            end else begin
                // THRESHOLD REACHED: Safe to expose button signals to upper layers
                matrix_key_code <= detected_code;
                any_key_pressed <= 1'b1;
            end
        end else begin
            // Matrix is completely clear: Reset verification pipeline instantly
            press_timer     <= 22'd0;
            matrix_key_code <= 5'd16;
            any_key_pressed <= 1'b0;
        end

        // --- INACTIVITY TIMEOUT CONTROLLER ENGINE ---
        // Utilises the filtered validation flag to handle game phrase sequencing
        if (any_key_pressed) begin
            inactivity_timer   <= 0;
            has_pressed        <= 1'b1; 
            final_key_released <= 1'b0; 
        end 
        else if (has_pressed && (inactivity_timer >= 25'd23_999_999)) begin
            inactivity_timer   <= 0;
            has_pressed        <= 1'b0; 
            final_key_released <= 1'b1; // Trigger FSM round analysis
        end 
        else if (has_pressed) begin
            inactivity_timer   <= inactivity_timer + 1'b1;
            final_key_released <= 1'b0;
        end 
        else begin
            inactivity_timer   <= 0;
            final_key_released <= 1'b0;
        end
    end

endmodule
