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
    // =====================================================================
    // 4. FIXED Combinatorial Light Arbitration (HARDENED REPEATED NOTE FILTER)
    // =====================================================================
    always @(*) begin
        if (input_lockout) begin
            // --- SYSTEM PLAYBACK PHASE ---
            if (play_trigger && !play_in_simon_mode) begin
                // Playing normal FSM notifications (Boot, Win, Fail Chimes)
                target_light_code = simon_active_key;
            end else if (play_trigger && play_in_simon_mode) begin
                // Simon is actively playing a valid phrase note: Output the code
                target_light_code = simon_active_key;
            end else begin
                // AUDIO ENGINE IS IN THE AUDIO_GAP SILENCE WINDOW: Force idle code!
                // This breaks the text lockout for consecutive duplicate notes cleanly.
                target_light_code = 5'd16; 
            end
        end else begin
            // --- ACTIVE USER INTERACTIVE PHASE ---
            // Map live button taps directly (Suppresses release spam automatically)
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
    // 6. PIPELINED INDEX-DRIVEN USB UART PACKET CONTROLLER
    // ---------------------------------------------------------------------
    localparam CLK_PER_BIT = 104; // 115200 Baud @ 12MHz Clock
    
    // Flat 64-bit packed shift register to cleanly hold: "KEY:XX\r\n"
    reg [63:0] tx_string = 64'd0;
    
    reg [31:0] clk_counter = 0;
    reg [3:0]  bit_index = 0;
    reg [3:0]  char_index = 0;
    reg [7:0]  tx_data = 0;
    
    // States: 0=Startup delay, 1=Dynamic detection loop, 2=UART stream execution
    reg [1:0]  tx_state = 2'd0; 
    reg [23:0] delay_counter = 0;
    reg        delay_done = 0;
    
    // Step Index Tracking Registers to isolate duplicate notes cleanly
    reg [3:0]  last_simon_step  = 4'hF;
    reg [3:0]  last_player_step = 4'hF;
    reg        last_input_mode  = 1'b0;

    // HARDENED PIPELINE LAYER: Delays the step triggers by 1 cycle
    // This allows the FSM memory arrays to settle completely before the UART reads them.
    reg [3:0] audio_play_step_d1     = 4'hF;
    reg [3:0] player_step_counter_d1 = 4'hF;

    always @(posedge clk) begin
        audio_play_step_d1     <= audio_play_step;
        player_step_counter_d1 <= u_simon_fsm.player_step_counter;
    end

    // Pure helper function: Transforms a 4-bit binary nibble into a hex ASCII character byte
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
            // State 1: Active checking loop using delayed pointer steps
            tx_pin     <= 1'b1;
            char_index <= 0;
            
            if (input_lockout) begin
                // --- SIMON'S TURN: Trigger when Simon advances to a new delayed index step ---
                if ((audio_play_step_d1 != last_simon_step) && (target_light_code != 5'h10)) begin
                    last_simon_step  <= audio_play_step_d1;
                    last_input_mode  <= 1'b1;
                    
                    // Pack the full string instantly into the flat 64-bit bus register (Big Endian)
                    tx_string[63:56] <= "K";
                    tx_string[55:48] <= "E";
                    tx_string[47:40] <= "Y";
                    tx_string[39:32] <= ":";
                    tx_string[31:24] <= to_hex({2'b00, target_light_code[4:3]}); // Dynamic row identifier
                    tx_string[23:16] <= to_hex(target_light_code[3:0]);         // Dynamic column identifier
                    tx_string[15:8]  <= "\r";
                    tx_string[7:0]   <= "\n";
                    
                    tx_data     <= "K"; // Seed the first bitstream byte
                    bit_index   <= 0;
                    clk_counter <= 0;
                    tx_state    <= 2'd2; // Jump to serial transmitter engine
                end
            end else begin
                // --- PLAYER'S TURN: Reset Simon's tracking index when turn switches ---
                if (last_input_mode == 1'b1) begin
                    last_simon_step <= 4'hF;
                    last_input_mode <= 1'b0;
                end

                // Trigger exactly when the player successfully registers a delayed input step change
                if ((player_step_counter_d1 != last_player_step) && (matrix_key_code != 5'h10)) begin
                    last_player_step <= player_step_counter_d1;
                    
                    // Pack the active user keystroke coordinates instantly
                    tx_string[63:56] <= "K";
                    tx_string[55:48] <= "E";
                    tx_string[47:40] <= "Y";
                    tx_string[39:32] <= ":";
                    tx_string[31:24] <= to_hex({3'b000, matrix_key_code[4]}); 
                    tx_string[23:16] <= to_hex(matrix_key_code[3:0]);        
                    tx_string[15:8]  <= "\r";
                    tx_string[7:0]   <= "\n";
                    
                    tx_data     <= "K";
                    bit_index   <= 0;
                    clk_counter <= 0;
                    tx_state    <= 2'd2;
                end
                
                // Clear the latch on release so rapid tapping can register on same step count if needed
                if (matrix_key_code == 5'h10) begin
                    last_player_step <= 4'hF;
                end
            end
            
        end else begin
            // State 2: Bitstream Serialization Engine (Unpacking flat vector array data)
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
                    // Shift pointer sequentially across the flat 8-byte packed text register
                    if (char_index < 7) begin
                        char_index <= char_index + 1;
                        
                        // Dynamically extract the next 8-bit slice character byte out of the packed string vector
                        case (char_index + 1)
                            3'd1: tx_data <= tx_string[55:48]; // "E"
                            3'd2: tx_data <= tx_string[47:40]; // "Y"
                            3'd3: tx_data <= tx_string[39:32]; // ":"
                            3'd4: tx_data <= tx_string[31:24]; // Hex Digit 1
                            3'd5: tx_data <= tx_string[23:16]; // Hex Digit 2
                            3'd6: tx_data <= tx_string[15:8];  // "\r"
                            3'd7: tx_data <= tx_string[7:0];   // "\n"
                            default: tx_data <= "\n";
                        endcase
                        
                        bit_index <= 0;
                    end else begin
                        tx_state  <= 2'd1; // Transmission chain clear, return to scanning state
                    end
                end
            end
        end
    end

endmodule
