// =========================================================================
// CLEAN MASTER TOP-LEVEL SUPERVISOR LAYER (top.v) - DYNAMIC USB OUTPUT
// Indexes Simon's memory array live to light up matching button positions.
// Dynamically streams active key code tracking updates via USB CDC.
// =========================================================================

module top (
    input  clk,
    
    // Physical IO Matrix Keypad Bus Pins
    output test_out0, test_out1, test_out2, test_out3,
    input  test_in0,  test_in1,  test_in2,  test_in3,

    // Physical Onboard Signaling Outputs
    output led_r, led_g, led_b,
    output audio_l, audio_r,
  
    // USB UART Tx Pin (Hardwired to FPGA Pin 6)
    output reg tx_pin 
);
    // ---------------------------------------------------------------------
    // Interconnecting Wire Routing Links (Internal System Buses)
    // ---------------------------------------------------------------------
    wire [4:0]   matrix_key_code;   // Raw parsed index coming from keyboard
    wire         final_key_released;
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

    wire         play_in_simon_mode;
    wire         any_key_pressed;

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
        .final_key_released(final_key_released)
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
        .simon_seq_r         (shared_bus_r),
        .simon_seq_c         (shared_bus_c),
        .sequence_done       (sequence_done),
        
        .input_lockout       (input_lockout),
        
        // NEW OUTPUT PORT: Exposes Simon's current target key code to top level
        .audio_play_step     (audio_play_step),
        .simon_active_key    (simon_active_key),
        .play_in_simon_mode  (play_in_simon_mode),
        .final_key_released  (final_key_released)
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
        .play_in_simon_mode  (play_in_simon_mode)
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

    // ---------------------------------------------------------------------
    // 6. DYNAMIC USB UART PACKET CONTROLLER
    // ---------------------------------------------------------------------
    localparam CLK_PER_BIT = 104; // 115200 Baud @ 12MHz Clock
    
    // Packet configuration: "KEY:XX\r\n" (Total 8 bytes long)
    reg [7:0] message [0:7];
    
    reg [31:0] clk_counter = 0;
    reg [3:0]  bit_index = 0;
    reg [3:0]  char_index = 0;
    reg [7:0]  tx_data = 0;
    
    // States: 0=Startup delay, 1=Dynamic detection loop, 2=UART stream execution
    reg [1:0]  tx_state = 2'd0; 
    reg [23:0] delay_counter = 0;
    reg        delay_done = 0;
    
    // Variable tracking to identify immediate value transitions
    reg [4:0]  last_target_code = 5'h1F; 

    // Pure helper function: Transforms binary value to Hexadecimal character code
    function [7:0] to_hex;
        input [3:0] val;
        begin
            to_hex = (val < 10) ? (val + 8'h30) : (val + 8'h37);
        end
    endfunction

    always @(posedge clk) begin
        if (!delay_done) begin
            // State 0: Wait for hardware/USB CDC lines to stabilize
            tx_pin <= 1'b1; 
            if (delay_counter < 2000000) begin
                delay_counter <= delay_counter + 1;
            end else begin
                delay_done    <= 1'b1;
                tx_state      <= 2'd1;
            end
        end else if (tx_state == 2'd1) begin
            // State 1: Active checking loop for physical target change
            tx_pin     <= 1'b1;
            char_index <= 0;
            
            // Check if code changed AND make sure it isn't the unpressed/release idle code (5'h10)
            if ((target_light_code != last_target_code) && (target_light_code != 5'h10)) begin
                last_target_code <= target_light_code;
                
                // Dynamically format the live state buffer with explicit indices
                message[0] <= "K"; 
                message[1] <= "E"; 
                message[2] <= "Y"; 
                message[3] <= ":";
                message[4] <= to_hex({3'b000, target_light_code[4]}); // Hex digit 1
                message[5] <= to_hex(target_light_code[3:0]);         // Hex digit 2
                message[6] <= "\r"; 
                message[7] <= "\n";
                
                // Latch immediate first block character to start cleanly
                tx_data     <= "K"; 
                bit_index   <= 0;
                clk_counter <= 0;
                tx_state    <= 2'd2; // Pass to UART pipeline
            end else if (target_light_code == 5'h10) begin
                // Update tracking register on release so the next press triggers correctly,
                // but do not start a UART transmission.
                last_target_code <= 5'h10;
            end
        end else begin
            // State 2: Bitstream Serialization Engine
            if (clk_counter < CLK_PER_BIT - 1) begin
                clk_counter <= clk_counter + 1;
            end else begin
                clk_counter <= 0;
                
                if (bit_index == 0) begin
                    tx_pin    <= 1'b0; // Start Bit
                    bit_index <= bit_index + 1;
                end else if (bit_index >= 1 && bit_index <= 8) begin
                    tx_pin    <= tx_data[bit_index - 1]; // Serial data payload (LSB first)
                    bit_index <= bit_index + 1;
                end else if (bit_index == 9) begin
                    tx_pin    <= 1'b1; // Stop Bit
                    bit_index <= bit_index + 1;
                end else begin
                    // Move sequentially to next element in the array
                    if (char_index < 7) begin
                        char_index <= char_index + 1;
                        tx_data    <= message[char_index + 1]; // Pre-load next character byte
                        bit_index  <= 0;
                    end else begin
                        tx_state   <= 2'd1; // Stream complete, return to evaluation state
                    end
                end
            end
        end
    end


endmodule
