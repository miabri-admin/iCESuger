// =========================================================================
// HIGH-SPEED TIME-INTERLEAVED 16-DIGIT DTMF SEQUENCER FOR ICESUGAR V1.5
// Expanded to sequence: 1-5-4-3-2-9-5-4-3-2-9-5-4-3-4-2 seamlessly.
// =========================================================================

module top (
    input clk,            // Onboard 12MHz master clock line from Pin 35
    input ext_switch,     // Trigger switch input (Pin 32)
    output led_r, led_g, led_b,
    output audio_l,       // Connects to PMOD2 Pin 1 (iCE40 Pin 46)
    output audio_r        // Connects to PMOD2 Pin 2 (iCE40 Pin 44)
);

    // ---------------------------------------------------------------------
    // 1. FIXED: Expanded 64-Bit Telephone Array Vector (16 Digits * 4-bits)
    // Packed in reverse order so index 0 extracts the leftmost number (4'd1)
    // ---------------------------------------------------------------------
    wire [63:0] phone_number = {
        4'd2, 4'd4, 4'd3, 4'd4, // [15:12] -> 2, 4, 3, 4
        4'd5, 4'd9, 4'd2, 4'd3, // [11:8]  -> 5, 9, 2, 3
        4'd4, 4'd5, 4'd9, 4'd2, // [7:4]   -> 4, 5, 9, 2
        4'd3, 4'd4, 4'd5, 4'd1  // [3:0]   -> 3, 4, 5, 1
    };

    // ---------------------------------------------------------------------
    // 2. High-Speed Oscillator Engine Clocks
    // ---------------------------------------------------------------------
    reg [13:0] row_counter = 0;
    reg [13:0] col_counter = 0;
    
    reg [13:0] row_max;
    reg [13:0] col_max;
    
    reg row_square = 0;
    reg col_square = 0;

    always @(posedge clk) begin
        if (row_counter >= row_max) begin
            row_counter <= 0;
            row_square  <= ~row_square;
        end else begin
            row_counter <= row_counter + 1'b1;
        end

        if (col_counter >= col_max) begin
            col_counter <= 0;
            col_square  <= ~col_square;
        end else begin
            col_counter <= col_counter + 1'b1;
        end
    end

    // ---------------------------------------------------------------------
    // 3. FIXED: 4-Bit Paced Character Loop Sequencer (~333ms per sound)
    // Expanded pointer boundary perfectly cycles across indices 0 to 15
    // ---------------------------------------------------------------------
    reg [21:0] frame_counter = 0;
    reg [3:0]  digit_ptr = 0; // 4-bit width maps 0-15 steps safely
    
    reg [3:0] active_digit;
    always @(*) begin
        case(digit_ptr)
            4'd0:  active_digit = phone_number[3:0];   // 1
            4'd1:  active_digit = phone_number[7:4];   // 5
            4'd2:  active_digit = phone_number[11:8];  // 4
            4'd3:  active_digit = phone_number[15:12]; // 3
            4'd4:  active_digit = phone_number[19:16]; // 2
            4'd5:  active_digit = phone_number[23:20]; // 9
            4'd6:  active_digit = phone_number[27:24]; // 5
            4'd7:  active_digit = phone_number[31:28]; // 4
            4'd8:  active_digit = phone_number[35:32]; // 3
            4'd9:  active_digit = phone_number[39:36]; // 2
            4'd10: active_digit = phone_number[43:40]; // 9
            4'd11: active_digit = phone_number[47:44]; // 5
            4'd12: active_digit = phone_number[51:48]; // 4
            4'd13: active_digit = phone_number[55:52]; // 3
            4'd14: active_digit = phone_number[59:56]; // 4
            4'd15: active_digit = phone_number[63:60]; // 2
        endcase
    end

    // Standard baseline phone pacing durations
    localparam TONE_DURATION = 22'd3000000; // ~250ms play tone
    localparam TOTAL_FRAME   = 22'd4000000; // ~333ms total space block (Creates gap)

    always @(posedge clk) begin
        frame_counter <= frame_counter + 1'b1;
        if (frame_counter >= TOTAL_FRAME) begin 
            frame_counter <= 0;
            digit_ptr     <= digit_ptr + 1'b1; // Auto-rolls over cleanly back to step 0
        end
    end

    wire is_sounding = (frame_counter < TONE_DURATION);

    // ---------------------------------------------------------------------
    // 4. FIXED: DTMF Coordinate Decoder Array Matrix (Incorporates 5 and 9)
    // Max Counts Calculation Core: 12,000,000 / (Target Freq * 2)
    // ---------------------------------------------------------------------
    always @(*) begin
        case (active_digit)
            4'd1: begin row_max = 14'd8608; col_max = 14'd4962; end // 1: 697Hz + 1209Hz
            4'd2: begin row_max = 14'd8608; col_max = 14'd4491; end // 2: 697Hz + 1336Hz
            4'd3: begin row_max = 14'd8608; col_max = 14'd4062; end // 3: 697Hz + 1477Hz
            4'd4: begin row_max = 14'd7792; col_max = 14'd4962; end // 4: 770Hz + 1209Hz
            4'd5: begin row_max = 14'd7792; col_max = 14'd4491; end // 5: 770Hz + 1336Hz  (NEWLY ADDED)
            4'd9: begin row_max = 14'd7042; col_max = 14'd4062; end // 9: 852Hz + 1477Hz  (NEWLY ADDED)
            default: begin row_max = 14'd0; col_max = 14'd0;    end // Quiet fallback
        endcase
    end

    // ---------------------------------------------------------------------
    // 5. 12MHz Interleaved Smooth Analog Mixer
    // ---------------------------------------------------------------------
    reg mix_clock_phase = 0;
    always @(posedge clk) mix_clock_phase <= ~mix_clock_phase;

    wire dtmf_output = is_sounding ? (mix_clock_phase ? row_square : col_square) : 1'b0;

    // ---------------------------------------------------------------------
    // 6. Direct Hardware Port Drive
    // ---------------------------------------------------------------------
    assign audio_l = dtmf_output;
    assign audio_r = dtmf_output;

    // LED Sync Status Check (Blinks across the 16 digit increments)
    assign led_r = ~digit_ptr[0];
    assign led_g = ~digit_ptr[1];
    assign led_b = is_sounding;

endmodule
