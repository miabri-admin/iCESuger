// =========================================================================
// CLEAN MASTER TOP-LEVEL SUPERVISOR LAYER (top.v) - FIXED LIGHT SYNC
// Indexes Simon's memory array live to light up matching button positions.
// =========================================================================

module top (
    input  clk,
    
    // Physical IO Matrix Keypad Bus Pins
    output test_out0, test_out1, test_out2, test_out3,
    input  test_in0,  test_in1,  test_in2,  test_in3,

    // Physical Onboard Signaling Outputs
    output led_r, led_g, led_b,
    output audio_l, audio_r
);

    // ---------------------------------------------------------------------
    // Interconnecting Wire Routing Links (Internal System Buses)
    // ---------------------------------------------------------------------
    wire [4:0]   matrix_key_code;   // Raw parsed index coming from keyboard
    wire w_key_released;
    
    wire         input_lockout;     // Safety line to block accidental taps during plays
    
    // Tier-1 to Tier-2 Handshake Signals
    wire         play_trigger;      // Starts the Universal Audio Player
    wire [3:0]   playback_length;   // Active depth of the loaded sequence (1 to 12)
    wire         sequence_done;     // Completion feedback wire sent back to FSM
    
    // 168-bit Shared Parallel Frequency Data Buses (12 steps x 14 bits)
    wire [167:0] shared_bus_r;
    wire [167:0] shared_bus_c;
    
    // ---------------------------------------------------------------------
    // FIXED LIGHT INTERFACE DATA BUS ROUTING
    // ---------------------------------------------------------------------
    wire [3:0]   audio_play_step;   // Which step count index (0-11) audio is on
    wire [4:0]   simon_active_key;  // The actual key coordinate value (0-15) Simon is reading
    reg  [4:0]   target_light_code; // Final multiplexed value sent to the LEDs


    wire play_at_half_speed;


    // ---------------------------------------------------------------------
    // 1. Instantiation: Hardware Matrix Peripheral Scanner
    // ---------------------------------------------------------------------
    keypad_scanner u_keypad_scanner (
        .clk             (clk),
        .test_out0       (test_out0),
        .test_out1       (test_out1),
        .test_out2       (test_out2),
        .test_out3       (test_out3),
        .test_in0        (test_in0),
        .test_in1        (test_in1),
        .test_in2        (test_in2),
        .test_in3        (test_in3),
        .matrix_key_code (matrix_key_code),
        .any_key_pressed (any_key_pressed),
        .key_released(w_key_released)

    );

    // ---------------------------------------------------------------------
    // 2. Instantiation: Data-Driven Master Simon Says Engine (FSM)
    // ---------------------------------------------------------------------
    simon_fsm u_simon_fsm (
        .clk                 (clk),
        .reset               (1'b0), 
        .matrix_key_code     (matrix_key_code),
        .any_key_pressed     (any_key_pressed & ~input_lockout), 
        
        // Parallel Data-Bus Interfaces
        .play_trigger        (play_trigger),
        .playback_length     (playback_length),
        .out_seq_r           (shared_bus_r),
        .out_seq_c           (shared_bus_c),
        .sequence_done       (sequence_done),
        
        .input_lockout       (input_lockout),
        
        // NEW OUTPUT PORT: Exposes Simon's current target key code to top level
        .audio_play_step     (audio_play_step),
        .simon_active_key    (simon_active_key),
        .play_at_half_speed (play_at_half_speed),
        .key_released(w_key_released)

    );

    // ---------------------------------------------------------------------
    // 3. Instantiation: Universal Array-Based Audio Generation Engine
    // ---------------------------------------------------------------------
    audio_engine u_audio_engine (
        .clk                 (clk),
        .play_trigger        (play_trigger),
        .sequence_length     (playback_length), 
        .shared_sequence_r   (shared_bus_r),
        .shared_sequence_c   (shared_bus_c),
        .sequence_done       (sequence_done),
        .active_key_index    (audio_play_step), // Hands raw step index pointer up to top.v
        .audio_l             (audio_l),
        .audio_r             (audio_r),
        .play_at_half_speed (play_at_half_speed)
    );

    // ---------------------------------------------------------------------
    // 4. FIXED Combinatorial Light Arbitration (No added register delays)
    // ---------------------------------------------------------------------
    always @(*) begin
        if (input_lockout) begin
            // System playback mode: Route the rock-solid clocked code straight out
            target_light_code = simon_active_key;
        end else begin
            // User entry mode: Map live button taps directly
            target_light_code = matrix_key_code;
        end
    end



    // ---------------------------------------------------------------------
    // 5. Instantiation: PWM Visual Light Module Look-up
    // ---------------------------------------------------------------------
    rgb_mixer u_rgb_mixer (
        .clk             (clk),
        .active_key_code (target_light_code), // Receives clean arbitrated button codes
        .led_r           (led_r),
        .led_g           (led_g),
        .led_b           (led_b)
    );

endmodule
