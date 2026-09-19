// =========================================================================
// UNIVERSAL ARRAY-BASED SEQUENCE AUDIO DRIVER (audio_engine.v)
// Plays a custom loaded matrix block array up to 12 notes sequentially.
// =========================================================================

module audio_engine (
    input             clk,
    input             play_trigger,      // Set High to start playing the array
    input      [3:0]  sequence_length,   // Total notes loaded into array (1 to 12)
    
    // Flat-mapped input busses to accept the loaded 12-note sequence array blocks
    // 12 notes * 14-bits per frequency channel = 168 bits total width
    input      [167:0] shared_sequence_r, 
    input      [167:0] shared_sequence_c,

    output reg        sequence_done,     // Handshake signal sent back to Tier 1
    output            audio_l, audio_r,  // Physical audio outputs
    output reg [4:0]  active_key_index   // Kept for lighting synchronization
);

    // ---------------------------------------------------------------------
    // 1. Playback Step Sequencer State Machine
    // ---------------------------------------------------------------------
    reg [3:0]  play_index = 0;
    reg [23:0] note_timer = 0;
    reg        is_playing = 0;

    // Slices out the active 14-bit frequency windows from the combined input array buses
    reg [13:0] row_max;
    reg [13:0] col_max;

    always @(posedge clk) begin
        if (play_trigger && !is_playing) begin
            is_playing    <= 1'b1;
            play_index    <= 0;
            note_timer    <= 0;
            sequence_done <= 1'b0;
        end else if (is_playing) begin
            note_timer <= note_timer + 1'b1;
            
            // Extract the targeted note frequency from our shared array bus blocks
            row_max <= shared_sequence_r[(play_index * 14) +: 14];
            col_max <= shared_sequence_c[(play_index * 14) +: 14];

            if (note_timer >= 24'd3_599_999) begin // ~300ms note duration
                note_timer <= 0;
                if (play_index >= (sequence_length - 1'b1)) begin
                    is_playing    <= 1'b0;
                    sequence_done <= 1'b1; // Trigger jump back up in state hierarchy
                end else begin
                    play_index <= play_index + 1'b1;
                end
            end
        end else begin
            row_max       <= 14'd0;
            col_max       <= 14'd0;
            sequence_done <= 1'b0;
        end
    end

    // ---------------------------------------------------------------------
    // 2. Continuous Running Oscillators & Passive Interleave Multi-plexer
    // ---------------------------------------------------------------------
    reg [13:0] row_counter = 0; reg [13:0] col_counter = 0;
    reg        row_square = 0;  reg        col_square = 0;

    always @(posedge clk) begin
        if (row_max == 14'd0) begin row_counter <= 0; row_square <= 0; end
        else if (row_counter >= row_max) begin row_counter <= 0; row_square <= ~row_square; end
        else row_counter <= row_counter + 1'b1;

        if (col_max == 14'd0) begin col_counter <= 0; col_square <= 0; end
        else if (col_counter >= col_max) begin col_counter <= 0; col_square <= ~col_square; end
        else col_counter <= col_counter + 1'b1;
    end

    reg mix_toggle = 0;
    always @(posedge clk) mix_toggle <= ~mix_toggle;
    wire blended_audio = mix_toggle ? row_square : col_square;

    assign audio_l = blended_audio;
    assign audio_r = blended_audio;

endmodule
