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

    wire [4:0]   matrix_key_code;   
    wire         final_key_released;
    wire         input_lockout;     
    
    wire         play_trigger;      
    wire [3:0]   playback_length;   
    wire         sequence_done;     
    
    wire [167:0] shared_bus_r;
    wire [167:0] shared_bus_c;
    
    wire [3:0]   audio_play_step;   
    wire [4:0]   simon_active_key;  
    reg  [4:0]   target_light_code; 

    wire         play_in_simon_mode;
    wire         any_key_pressed;

    // 1. Instantiation: Hardware Matrix Peripheral Scanner
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

    // 2. Instantiation: Data-Driven Master Simon Says Engine (FSM)
    simon_fsm u_simon_fsm (
        .clk                 (clk),
        .reset               (1'b0), 
        .matrix_key_code     (matrix_key_code),
        .any_key_pressed     (any_key_pressed & ~input_lockout), 
        .play_trigger        (play_trigger),
        .playback_length     (playback_length),
        .simon_seq_r         (shared_bus_r),
        .simon_seq_c         (shared_bus_c),
        .sequence_done       (sequence_done),
        .input_lockout       (input_lockout),
        .audio_play_step     (audio_play_step),
        .simon_active_key    (simon_active_key),
        .play_in_simon_mode  (play_in_simon_mode),
        .final_key_released  (final_key_released)
    );

    // 3. Instantiation: Universal Array-Based Audio Generation Engine
    audio_engine u_audio_engine (
        .clk                 (clk),
        .play_trigger        (play_trigger),
        .sequence_length     (playback_length), 
        .shared_sequence_r   (shared_bus_r),
        .shared_sequence_c   (shared_bus_c),
        .sequence_done       (sequence_done),
        .active_key_index    (audio_play_step), 
        .audio_l             (audio_l),
        .audio_r             (audio_r),
        .play_in_simon_mode  (play_in_simon_mode)
    );

    // 4. Fixed Combinatorial Light Arbitration
    always @(*) begin
        if (input_lockout) begin
            target_light_code = simon_active_key;
        end else begin
            target_light_code = matrix_key_code;
        end
    end

    // 5. Instantiation: PWM Visual Light Module Look-up
    rgb_mixer u_rgb_mixer (
        .clk             (clk),
        .active_key_code (target_light_code), 
        .led_r           (led_r),
        .led_g           (led_g),
        .led_b           (led_b)
    );

    // ---------------------------------------------------------------------
    // 6. HARDENED STRUCTURAL PACKED SERIAL MONITOR PIPELINE
    // ---------------------------------------------------------------------
    localparam CLK_PER_BIT = 104; 
    
    reg [63:0] tx_string = 64'd0;
    reg [31:0] clk_counter = 0;
    reg [3:0]  bit_index = 0;
    reg [3:0]  char_index = 0;
    reg [7:0]  tx_data = 0;
    
    reg [1:0]  tx_state = 2'd0; 
    reg [23:0] delay_counter = 0;
    reg        delay_done = 0;
    
    reg [3:0]  last_simon_step  = 4'hF;
    reg [3:0]  last_player_step = 4'hF;
    reg        last_input_mode  = 1'b0;

    reg [3:0]  audio_play_step_d1     = 4'hF;
    reg [3:0]  player_step_counter_d1 = 4'hF;

    always @(posedge clk) begin
        audio_play_step_d1     <= audio_play_step;
        player_step_counter_d1 <= u_simon_fsm.player_step_counter;
    end

    function [7:0] to_hex;
        input [3:0] val;
        begin
            to_hex = (val < 10) ? (val + 8'h30) : (val + 8'h37);
        end
    endfunction

    always @(posedge clk) begin
        if (!delay_done) begin
            tx_pin <= 1'b1; 
            if (delay_counter < 2000000) begin
                delay_counter <= delay_counter + 1;
            end else begin
                delay_done    <= 1'b1;
                tx_state      <= 2'd1;
            end
        end else if (tx_state == 2'd1) begin
            tx_pin     <= 1'b1;
            char_index <= 0;
            
            if (input_lockout) begin
                if ((audio_play_step_d1 != last_simon_step) && (target_light_code != 5'h10)) begin
                    last_simon_step  <= audio_play_step_d1;
                    last_input_mode  <= 1'b1;
                    
                    tx_string[63:56] <= "s";
                    tx_string[55:48] <= "i";
                    tx_string[47:40] <= "m";
                    tx_string[39:32] <= ":";
                    tx_string[31:24] <= to_hex({2'b00, target_light_code[3:2]}); // Dynamic clean bit decoding
                    tx_string[23:16] <= to_hex(target_light_code[1:0]);         
                    tx_string[15:8]  <= "\r";
                    tx_string[7:0]   <= "\n";
                    
                    tx_data     <= "s"; 
                    bit_index   <= 0;
                    clk_counter <= 0;
                    tx_state    <= 2'd2; 
                end
            end else begin
                if (last_input_mode == 1'b1) begin
                    last_simon_step <= 4'hF;
                    last_input_mode <= 1'b0;
                end

                if ((player_step_counter_d1 != last_player_step) && (matrix_key_code != 5'h10)) begin
                    last_player_step <= player_step_counter_d1;
                    
                    tx_string[63:56] <= "u";
                    tx_string[55:48] <= "s";
                    tx_string[47:40] <= "r";
                    tx_string[39:32] <= ":";
                    tx_string[31:24] <= to_hex({2'b00, matrix_key_code[3:2]}); 
                    tx_string[23:16] <= to_hex(matrix_key_code[1:0]);        
                    tx_string[15:8]  <= "\r";
                    tx_string[7:0]   <= "\n";
                    
                    tx_data     <= "u"; 
                    bit_index   <= 0;
                    clk_counter <= 0;
                    tx_state    <= 2'd2;
                end
                
                if (matrix_key_code == 5'h10) begin
                    last_player_step <= 4'hF;
                end
            end
            
        end else begin
            if (clk_counter < CLK_PER_BIT - 1) begin
                clk_counter <= clk_counter + 1;
            end else begin
                clk_counter <= 0;
                
                if (bit_index == 0) begin
                    tx_pin    <= 1'b0; 
                    bit_index <= bit_index + 1;
                end else if (bit_index >= 1 && bit_index <= 8) begin
                    tx_pin    <= tx_data[bit_index - 1]; 
                    bit_index <= bit_index + 1;
                end else if (bit_index == 9) begin
                    tx_pin    <= 1'b1; 
                    bit_index <= bit_index + 1;
                end else begin
                    if (char_index < 7) begin
                        char_index <= char_index + 1;
                        case (char_index + 1)
                            3'd1: tx_data <= tx_string[55:48]; 
                            3'd2: tx_data <= tx_string[47:40]; 
                            3'd3: tx_data <= tx_string[39:32]; 
                            3'd4: tx_data <= tx_string[31:24]; 
                            3'd5: tx_data <= tx_string[23:16]; 
                            3'd6: tx_data <= tx_string[15:8];  
                            3'd7: tx_data <= tx_string[7:0];   
                            default: tx_data <= "\n";
                        endcase
                        bit_index <= 0;
                    end else begin
                        tx_state  <= 2'd1; 
                    end
                end
            end
        end
    end

endmodule
