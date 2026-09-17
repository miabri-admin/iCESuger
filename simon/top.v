// =========================================================================
// CUSTOM RE-MAPPED DEBOUNCED DTMF KEYPAD DIALER FOR ICESUGAR V1.5
// Forces physical silicon pull-up track activation using SB_IO primitives.
// =========================================================================

module top (
    input clk,                    // Onboard 12MHz master clock line from Pin 35
    output led_r, led_g, led_b,
    
    // PMOD2: Audio Output Interface Links
    output audio_l,               // PMOD2 Pin 1 (iCE40 Pin 43)
    output audio_r,               // PMOD2 Pin 2 (iCE40 Pin 38)
    output amp_power,             // PMOD2 Pin 4 (iCE40 Pin 28)

    // PMOD1: Custom 4x4 Keypad Interface Matrix Bus Ports
    output reg [3:0] kp_rows,    // PMOD1 Pins 1,2,3,4 (Outputs)
    input      [3:0] kp_cols     // PMOD1 Pins 10,9,8,7 (Raw Silicon Pins)
);

    // Keep the external amplifier chip on PMOD2 awake continuously
    assign amp_power = 1'b1;

    // ---------------------------------------------------------------------
    // 1. Stable Matrix Scan Clock Divider (12MHz / 12000 = 1 kHz Scan Rate)
    // ---------------------------------------------------------------------
    reg [13:0] scan_divider = 0;
    wire scan_tick = (scan_divider == 14'd11999);

    always @(posedge clk) begin
        if (scan_divider >= 14'd11999)
            scan_divider <= 0;
        else
            scan_divider <= scan_divider + 1'b1;
    end

    // ---------------------------------------------------------------------
    // 2. Active Low Sequential Row Shifter State Machine
    // ---------------------------------------------------------------------
    reg [1:0] scan_row_ptr = 0;

    always @(posedge clk) begin
        if (scan_tick) begin
            scan_row_ptr <= scan_row_ptr + 1'b1; // Steps 0 -> 1 -> 2 -> 3
        end
    end

    // Combinatorial 1-hot row masking decoder loop
    always @(*) begin
        case (scan_row_ptr)
            2'd0:    kp_rows = 4'b1110; // Drive Row 1 low
            2'd1:    kp_rows = 4'b1101; // Drive Row 2 low
            2'd2:    kp_rows = 4'b1011; // Drive Row 3 low
            2'd3:    kp_rows = 4'b0111; // Drive Row 4 low
            default: kp_rows = 4'b1111;
        endcase
    end

    // ---------------------------------------------------------------------
    // 3. HARDWARE INDUSTRIAL PULL-UP ELEMENT MATRIX
    // Bypasses NextPNR PCF bugs by declaring explicit silicon cells.
    // Maps raw kp_cols input lines to stable internal kp_cols_buffered buses.
    // ---------------------------------------------------------------------
    wire [3:0] kp_cols_buffered;

    SB_IO #(.PIN_TYPE(6'b000001), .PULLUP(1'b1)) u_col0_pullup (.PACKAGE_PIN(kp_cols[0]), .D_IN_0(kp_cols_buffered[0]));
    SB_IO #(.PIN_TYPE(6'b000001), .PULLUP(1'b1)) u_col1_pullup (.PACKAGE_PIN(kp_cols[1]), .D_IN_0(kp_cols_buffered[1]));
    SB_IO #(.PIN_TYPE(6'b000001), .PULLUP(1'b1)) u_col2_pullup (.PACKAGE_PIN(kp_cols[2]), .D_IN_0(kp_cols_buffered[2]));
    SB_IO #(.PIN_TYPE(6'b000001), .PULLUP(1'b1)) u_col3_pullup (.PACKAGE_PIN(kp_cols[3]), .D_IN_0(kp_cols_buffered[3]));

    // ---------------------------------------------------------------------
    // 4. Matrix Decode Interceptor Index Bus (Uses the buffered lines)
    // ---------------------------------------------------------------------
    reg [3:0] raw_key_code;
    reg       key_is_pressed;

    always @(*) begin
        raw_key_code   = 4'd0;
        key_is_pressed = 1'b0;

        case (kp_rows)
            4'b1110: begin // Row 1 Active (Green Wire)
                if (!kp_cols_buffered[0]) begin raw_key_code = 4'd1;  key_is_pressed = 1'b1; end // Key '1' (White Wire)
                if (!kp_cols_buffered[1]) begin raw_key_code = 4'd2;  key_is_pressed = 1'b1; end // Key '2' (Black Wire)
                if (!kp_cols_buffered[2]) begin raw_key_code = 4'd3;  key_is_pressed = 1'b1; end // Key '3' (Brown Wire)
                if (!kp_cols_buffered[3]) begin raw_key_code = 4'd12; key_is_pressed = 1'b1; end // Key 'A' (Red Wire)
            end
            4'b1101: begin // Row 2 Active (Blue Wire)
                if (!kp_cols_buffered[0]) begin raw_key_code = 4'd4;  key_is_pressed = 1'b1; end // Key '4' (White Wire)
                if (!kp_cols_buffered[1]) begin raw_key_code = 4'd5;  key_is_pressed = 1'b1; end // Key '5' (Black Wire)
                if (!kp_cols_buffered[2]) begin raw_key_code = 4'd6;  key_is_pressed = 1'b1; end // Key '6' (Brown Wire)
                if (!kp_cols_buffered[3]) begin raw_key_code = 4'd13; key_is_pressed = 1'b1; end // Key 'B' (Red Wire)
            end
            4'b1011: begin // Row 3 Active (Purple Wire)
                if (!kp_cols_buffered[0]) begin raw_key_code = 4'd7;  key_is_pressed = 1'b1; end // Key '7' (White Wire)
                if (!kp_cols_buffered[1]) begin raw_key_code = 4'd8;  key_is_pressed = 1'b1; end // Key '8' (Black Wire)
                if (!kp_cols_buffered[2]) begin raw_key_code = 4'd9;  key_is_pressed = 1'b1; end // Key '9' (Brown Wire)
                if (!kp_cols_buffered[3]) begin raw_key_code = 4'd14; key_is_pressed = 1'b1; end // Key 'C' (Red Wire)
            end
            4'b0111: begin // Row 4 Active (Grey Wire)
                if (!kp_cols_buffered[0]) begin raw_key_code = 4'd10; key_is_pressed = 1'b1; end // Key '*' (White Wire)
                if (!kp_cols_buffered[1]) begin raw_key_code = 4'd0;  key_is_pressed = 1'b1; end // Key '0' (Black Wire)
                if (!kp_cols_buffered[2]) begin raw_key_code = 4'd11; key_is_pressed = 1'b1; end // Key '#' (Brown Wire)
                if (!kp_cols_buffered[3]) begin raw_key_code = 4'd15; key_is_pressed = 1'b1; end // Key 'D' (Red Wire)
            end
            default: begin raw_key_code = 4'd0; key_is_pressed = 1'b0; end
        endcase
    end

    // ---------------------------------------------------------------------
    // 5. Glitch Filter Debounce Tracking Array Window
    // ---------------------------------------------------------------------
    reg [3:0] debounced_key_code = 4'd0;
    reg       debounced_sounding = 1'b0;
    reg [3:0] debounce_counter = 0;

    always @(posedge clk) begin
        if (scan_tick) begin
            if (key_is_pressed) begin
                if (debounce_counter < 4'd15) begin
                    debounce_counter <= debounce_counter + 1'b1;
                end else begin
                    debounced_key_code <= raw_key_code;
                    debounced_sounding <= 1'b1;
                end
            end else begin
                if (debounce_counter > 0) begin
                    debounce_counter <= debounce_counter - 1'b1;
                end else begin
                    debounced_sounding <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 6. DTMF Target Coordinate Matrix Router
    // ---------------------------------------------------------------------
    reg [13:0] row_max;
    reg [13:0] col_max;

    always @(*) begin
        case (debounced_key_code)
            4'd1:  begin row_max = 14'd8608; col_max = 14'd4962; end // 1: 697Hz + 1209Hz
            4'd2:  begin row_max = 14'd8608; col_max = 14'd4491; end // 2: 697Hz + 1336Hz
            4'd3:  begin row_max = 14'd8608; col_max = 14'd4062; end // 3: 697Hz + 1477Hz
            4'd4:  begin row_max = 14'd7792; col_max = 14'd4962; end // 4: 770Hz + 1209Hz
            4'd5:  begin row_max = 14'd7792; col_max = 14'd4491; end // 5: 770Hz + 1336Hz
            4'd6:  begin row_max = 14'd7792; col_max = 14'd4062; end // 6: 770Hz + 1477Hz
            4'd7:  begin row_max = 14'd7042; col_max = 14'd4962; end // 7: 852Hz + 1209Hz
            4'd8:  begin row_max = 14'd7042; col_max = 14'd4491; end // 8: 852Hz + 1336Hz
            4'd9:  begin row_max = 14'd7042; col_max = 14'd4062; end // 9: 852Hz + 1477Hz
            4'd0:  begin row_max = 14'd6362; col_max = 14'd4491; end // 0: 941Hz + 1336Hz
            4'd10: begin row_max = 14'd6362; col_max = 14'd4962; end // *: 941Hz + 1209Hz
            4'd11: begin row_max = 14'd6362; col_max = 14'd4062; end // #: 941Hz + 1477Hz
            4'd12: begin row_max = 14'd8608; col_max = 14'd3674; end // A: 697Hz + 1633Hz
            4'd13: begin row_max = 14'd7792; col_max = 14'd3674; end // B: 770Hz + 1633Hz
            4'd14: begin row_max = 14'd7042; col_max = 14'd3674; end // C: 852Hz + 1633Hz
            4'd15: begin row_max = 14'd6362; col_max = 14'd3674; end // D: 941Hz + 1633Hz
            default: begin row_max = 14'd0; col_max = 14'd0;    end
        endcase
    end

    // ---------------------------------------------------------------------
    // 7. High-Speed Audio Oscillators
    // ---------------------------------------------------------------------
    reg [13:0] row_counter = 0;
    reg [13:0] col_counter = 0;
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
    // 8. Time-Interleaved Mixer and Direct Output Drive
    // ---------------------------------------------------------------------
    reg mix_clock_phase = 0;
    always @(posedge clk) mix_clock_phase <= ~mix_clock_phase;

    wire dtmf_output = debounced_sounding ? (mix_clock_phase ? row_square : col_square) : 1'b0;

    assign audio_l = dtmf_output;
    assign audio_r = dtmf_output;

    // Diagnostic indicators
    assign led_r = ~debounced_sounding;
    assign led_g = ~key_is_pressed;


endmodule
