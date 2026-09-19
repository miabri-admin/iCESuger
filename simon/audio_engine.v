// =========================================================================
// UNIVERSAL ARRAY-BASED SEQUENCE AUDIO DRIVER (audio_engine.v)
// Plays a loaded 12-note sequence array block sequentially.
// FIXED: Interlocked handshake prevents single-cycle double-triggering.
// =========================================================================

module audio_engine (
    input             clk,
    input             play_trigger,      // Set High to start playing the array
    input      [3:0]  sequence_length,   // Total notes loaded into array (1 to 12)
    
    input      [167:0] shared_sequence_r, 
    input      [167:0] shared_sequence_c,

    output reg        sequence_done,     // Handshake signal sent back to Tier 1
    output            audio_l, audio_r,  // Physical audio outputs
    output     [3:0]  active_key_index,
    input             play_at_half_speed // NEW: Speed control wire from FSM
   
   
);

    // Playback Step Sequencer Registers
    reg [3:0]  play_index = 0;
    reg [23:0] note_timer = 0;
    
    // Internal Playback State Engine States
    localparam AUDIO_IDLE  = 2'd0;
    localparam AUDIO_PLAY  = 2'd1;
    localparam AUDIO_DONE  = 2'd2;
    reg [1:0]  audio_state = AUDIO_IDLE;

    reg [13:0] row_max;
    reg [13:0] col_max;



    // Dynamic timer ceiling lookup selector
    wire [23:0] current_note_duration_max = play_at_half_speed ? 24'd7_199_999 : 24'd3_599_999;

    always @(posedge clk) begin
        case (audio_state)
            AUDIO_IDLE: begin
                sequence_done <= 1'b0; play_index <= 0; note_timer <= 0;
                row_max <= 14'd0; col_max <= 14'd0;
                if (play_trigger) audio_state <= AUDIO_PLAY;
            end

            AUDIO_PLAY: begin
                note_timer <= note_timer + 1'b1;
                row_max    <= shared_sequence_r[(play_index * 14) +: 14];
                col_max    <= shared_sequence_c[(play_index * 14) +: 14];

                // FIXED: Honors the dynamic duration ceiling depending on what state called it
                if (note_timer >= current_note_duration_max) begin 
                    note_timer <= 0;
                    if (play_index >= (sequence_length - 1'b1)) begin
                        sequence_done <= 1'b1; 
                        audio_state   <= AUDIO_DONE; 
                    end else begin
                        play_index <= play_index + 1'b1;
                    end
                end
            end

            AUDIO_DONE: begin
                row_max <= 14'd0; col_max <= 14'd0;
                if (!play_trigger) begin
                    sequence_done <= 1'b0;
                    audio_state   <= AUDIO_IDLE; 
                end else begin
                    sequence_done <= 1'b1;
                end
            end
            default: audio_state <= AUDIO_IDLE;
        endcase
    end


    // ---------------------------------------------------------------------
    // 2. Continuous Running Oscillators & Passive Interleave Multiplexer
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
