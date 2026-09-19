// =========================================================================
// ISOLATED RGB MIXER MODULE (rgb_mixer.v)
// Handles 2-bit PWM blending mapping based on input active_key_code.
// Outputs are Active-Low to match the iCE Sugar onboard RGB layout.
// =========================================================================

module rgb_mixer (
    input        clk,             // System Clock (12MHz)
    input  [4:0] active_key_code, // Target key code index (0 to 19)
    output       led_r,           // Inverted PWM output to Red LED
    output       led_g,           // Inverted PWM output to Green LED
    output       led_b            // Inverted PWM output to Blue LED
);

    // ---------------------------------------------------------------------
    // 1. Color Value Matrix Look-up (0 = Off, 3 = Full Brightness)
    // ---------------------------------------------------------------------
    reg [1:0] r_val;
    reg [1:0] g_val;
    reg [1:0] b_val;

    always @(*) begin
        case (active_key_code)
            5'd0:    begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd0; end // Key 1 Red
            5'd1:    begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd0; end // Key 2 Green
            5'd2:    begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd3; end // Key 3 Blue
            5'd3:    begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd0; end // Yellow
            5'd4:    begin r_val = 2'd0; g_val = 2'd3; b_val = 2'd3; end // Cyan
            5'd5:    begin r_val = 2'd3; g_val = 2'd0; b_val = 2'd3; end // Magenta
            5'd6:    begin r_val = 2'd3; g_val = 2'd3; b_val = 2'd3; end // White
            5'd7:    begin r_val = 2'd1; g_val = 2'd1; b_val = 2'd1; end // Dim Grey
            5'd8:    begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd0; end // Orange
            5'd9:    begin r_val = 2'd1; g_val = 2'd3; b_val = 2'd0; end // Lime Green
            5'd10:   begin r_val = 2'd3; g_val = 2'd1; b_val = 2'd1; end // Soft Pink
            5'd11:   begin r_val = 2'd1; g_val = 2'd0; b_val = 2'd3; end // Deep Violet
            5'd12:   begin r_val = 2'd0; g_val = 2'd1; b_val = 2'd3; end // Sky Blue
            5'd13:   begin r_val = 2'd0; g_val = 2'd2; b_val = 2'd1; end // Dark Teal
            5'd14:   begin r_val = 2'd3; g_val = 2'd2; b_val = 2'd0; end // Amber / Gold
            5'd15:   begin r_val = 2'd2; g_val = 2'd0; b_val = 2'd2; end // Plum
            
            // Wah-Wah Failure Visual Codes (Dull Red warnings pulsing down)
            5'd17:   begin r_val = 2'd2; g_val = 2'd0; b_val = 2'd0; end 
            5'd18:   begin r_val = 2'd1; g_val = 2'd0; b_val = 2'd0; end 
            5'd19:   begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd0; end 
            
            default: begin r_val = 2'd0; g_val = 2'd0; b_val = 2'd0; end // Default Idle Off
        endcase
    end

    // ---------------------------------------------------------------------
    // 2. High-Speed 2-Bit PWM Engine
    // ---------------------------------------------------------------------
    reg [7:0] pwm_counter = 0;
    always @(posedge clk) begin
        pwm_counter <= pwm_counter + 1'b1;
    end
    
    wire [1:0] pwm_frame = pwm_counter[7:6];

    // Structural Active-Low output conversions (~)
    assign led_r = ~(r_val > pwm_frame);
    assign led_g = ~(g_val > pwm_frame);
    assign led_b = ~(b_val > pwm_frame);

endmodule
