// =========================================================================
// ISOLATED HIGH-FIDELITY AUDIO GENERATION ENGINE (audio_engine.v)
// Decodes active_key_code into precise DTMF frequencies and custom chimes.
// Includes dual clock-divider square-wave oscillators and a 6MHz interleave mixer.
// =========================================================================

module audio_engine (
    input        clk,             // Master system hardware clock source (12MHz)
    input  [4:0] active_key_code, // Key index pointer passed from arbitration routing
    output       audio_l,         // Balanced output trace left channel
    output       audio_r          // Balanced output trace right channel
);

    // ---------------------------------------------------------------------
    // 1. DTMF Tone Frequency Selector Lookup Table Constants
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
            // --- ROW 1 Matrix Mappings ---
            5'd0:    begin row_max = ROW1_FREQ_697; col_max = COL1_FREQ_1209; end // Key '1'
            5'd1:    begin row_max = ROW1_FREQ_697; col_max = COL2_FREQ_1336; end // Key '2'
            5'd2:    begin row_max = ROW1_FREQ_697; col_max = COL3_FREQ_1477; end // Key '3'
            5'd3:    begin row_max = ROW1_FREQ_697; col_max = COL4_FREQ_1633; end // Key 'A'
            
            // --- ROW 2 Matrix Mappings ---
            5'd4:    begin row_max = ROW2_FREQ_770; col_max = COL1_FREQ_1209; end // Key '4'
            5'd5:    begin row_max = ROW2_FREQ_770; col_max = COL2_FREQ_1336; end // Key '5'
            5'd6:    begin row_max = ROW2_FREQ_770; col_max = COL3_FREQ_1477; end // Key '6'
            5'd7:    begin row_max = ROW2_FREQ_770; col_max = COL4_FREQ_1633; end // Key 'B'
            
            // --- ROW 3 Matrix Mappings ---
            5'd8:    begin row_max = ROW3_FREQ_852; col_max = COL1_FREQ_1209; end // Key '7'
            5'd9:    begin row_max = ROW3_FREQ_852; col_max = COL2_FREQ_1336; end // Key '8'
            5'd10:   begin row_max = ROW3_FREQ_852; col_max = COL3_FREQ_1477; end // Key '9'
            5'd11:   begin row_max = ROW3_FREQ_852; col_max = COL4_FREQ_1633; end // Key 'C'
            
            // --- ROW 4 Matrix Mappings ---
            5'd12:   begin row_max = ROW4_FREQ_941; col_max = COL1_FREQ_1209; end // Key '*'
            5'd13:   begin row_max = ROW4_FREQ_941; col_max = COL2_FREQ_1336; end // Key '0'
            5'd14:   begin row_max = ROW4_FREQ_941; col_max = COL3_FREQ_1477; end // Key '#'
            5'd15:   begin row_max = ROW4_FREQ_941; col_max = COL4_FREQ_1633; end // Key 'D'
            
            // Descending "Wah-Wah-Wah" single failure frequencies
            5'd17:   begin row_max = ROW4_FREQ_941; col_max = 14'd0;         end // Fail Note 1
            5'd18:   begin row_max = ROW3_FREQ_852; col_max = 14'd0;         end // Fail Note 2
            5'd19:   begin row_max = ROW2_FREQ_770; col_max = 14'd0;         end // Fail Note 3
            
            // Triumphant Rising "Ta-Da!" high clean frequencies
            5'd20:   begin row_max = 14'd3000;      col_max = 14'd0;         end // High Pitch 1
            5'd21:   begin row_max = 14'd2000;      col_max = 14'd0;         end // Extreme High Pitch 2
            
            default: begin row_max = 14'd0;         col_max = 14'd0;         end // Silence
        endcase
    end

    // ---------------------------------------------------------------------
    // 2. High-Speed 12MHz Dual Oscillators
    // ---------------------------------------------------------------------
    reg [13:0] row_counter = 0;
    reg [13:0] col_counter = 0;
    reg        row_square = 0;
    reg        col_square = 0;

    always @(posedge clk) begin
        // Row Channel Divider Loop
        if (row_max == 14'd0) begin
            row_counter <= 0;
            row_square  <= 0;
        end else if (row_counter >= row_max) begin
            row_counter <= 0;
            row_square  <= ~row_square;
        end else begin
            row_counter <= row_counter + 1'b1;
        end

        // Column Channel Divider Loop
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
    // 3. Passive Audio Interleaving Multiplexer
    // ---------------------------------------------------------------------
    reg mix_toggle = 0;
    always @(posedge clk) begin
        mix_toggle <= ~mix_toggle;
    end

    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
