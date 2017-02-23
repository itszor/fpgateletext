`include "config.v"

//`define RES_800_600	1

module vga(
		input					clock,
		output				hsync,
		output				vsync,
		output reg [2:0]	red,
		output reg [2:0]	green,
		output reg [2:0]	blue,
		input					reset,
		/*output reg			rd,
		output reg			wr,
		input					opbegun,
		input					rddone,
		output reg [23:0]	haddr,
		input [15:0]		hdout*/
		input					tt_write_clock,
		input [9:0]			tt_address,
		input					tt_write,
		input [7:0]			tt_data,
		
		output reg [9:0]	tt_fetch_addr,
		input [7:0]			tt_fetch_data
	);

`ifdef RES_640_480
	/* Horizontal timings. For a 25.175MHz pixel clock, these should sum
	   to 800, but our clock is only 25MHz. The values have been
	   adjusted so that they sum to only 794, by reducing the front
	   border and back border a little.
		FIXME: These values are unadjusted, and cause weird
		distortion.  */
	`define HT_LEFTBORDER	8
	`define HT_VIDEO			640
	`define HT_RIGHTBORDER	8
	`define HT_FRONTPORCH	8
	`define HT_SYNCPULSE		64
	`define HT_BACKPORCH		88
	
	// Vertical timings
	`define VT_TOPBORDER		1
	`define VT_VIDEO			480
	`define VT_BOTTOMBORDER	1
	`define VT_FRONTPORCH	1
	`define VT_SYNCPULSE		3
	`define VT_BACKPORCH		30
	
	`define VSYNC_POS			1
`elsif RES_800_600
	/* Horizontal timings, 800x600 (no clkdiv).  */
	`define HT_VIDEO			800
	`define HT_FRONTPORCH	56
	`define HT_SYNCPULSE		120
	`define HT_BACKPORCH		64
	
	// Vertical timings
	`define VT_VIDEO			600
	`define VT_FRONTPORCH	40
	`define VT_SYNCPULSE		6
	`define VT_BACKPORCH		20
	
	`define HSYNC_POS			1
	`define VSYNC_POS			1
`else
	// Horizontal timings, 533x600
	// This is basically the 800x600 mode but with the dot clock running
	// 1.5x slower!
	`define HT_VIDEO			533
	`define HT_FRONTPORCH	32
	`define HT_SYNCPULSE		80
	`define HT_BACKPORCH		48
	
	// Vertical timings
	`define VT_VIDEO			600
	`define VT_FRONTPORCH	40
	`define VT_SYNCPULSE		6
	`define VT_BACKPORCH		20
	
	`define HSYNC_POS			1
	`define VSYNC_POS			1
`endif

	wire [44:0] font [0:95];
	initial begin
		$readmemb("font.txt", font);
	end

	reg rowrefresh;

	/* VGA framebuffer handling.  */
	
	reg [23:0] vga_address;
	reg [9:0] vga_rowidx;
	reg [9:0] vga_fillidx;
	
	reg vga_refreshstate;
	
	`define VGA_REFRESH_IDLE	0
	`define VGA_REFRESH_ACTIVE	1
	
	reg vga_fill_writeen;
	reg [8:0] vga_fill_data;

	wire [8:0] vga_data;

	/* Generate VGA signal.  */

	// Horizontal state
	reg [1:0] hstate;
	reg [9:0] htimer;
	`define H_FRONTPORCH		0
	`define H_SYNCPULSE		1
	`define H_BACKPORCH		2
	`define H_VIDEO			3
	
	// Vertical state
	reg [1:0] vstate;
	reg [9:0] vtimer;
	`define V_FRONTPORCH		0
	`define V_SYNCPULSE		1
	`define V_BACKPORCH		2
	`define V_VIDEO			3

	reg [3:0] hsync_delay;
	reg [3:0] vsync_delay;

	reg [3:0] char_out;
	reg [3:0] border_out;

	reg [4:0] row_num;
	reg [5:0] col_num;
	reg [3:0] char_hpos;
	reg [3:0] char_hpos_1;
	reg [3:0] char_hpos_2;
	reg [4:0] char_vpos;

	// Sync pulses
	assign hsync = hsync_delay[3];
	assign vsync = vsync_delay[3];
	
	wire show_now = hstate == `H_VIDEO && vstate == `V_VIDEO;

	//reg [7:0] frame [0:999];

	reg [6:0] frame_counter;

	integer i;

	//initial begin
	//	$readmemh ("buzby.txt", frame);
	//end

	reg [7:0] current_char;
	reg [7:0] current_char_1;

	reg current_doubleheight;
	reg sticky_doubleheight;
	reg prev_doubleheight;
	
	reg flash_display;

	reg [44:0] glyph_bits;
	wire [2:0] char_hpos_lo = char_hpos_2[3:1];
	wire [3:0] char_vpos_lo = current_doubleheight
										  ? { 1'b0, char_vpos[4:2] }
											 + (prev_doubleheight ? 5 : 0)
										  : char_vpos[4:1];
	wire [3:0] char_vpos_lo_n = current_doubleheight
										  ? (char_vpos[4:1] + (prev_doubleheight ? 10 : 0) + 1) >> 1
										  : char_vpos[4:1] + 1;
	wire [3:0] char_vpos_lo_p = current_doubleheight
										  ? (char_vpos[4:1] + (prev_doubleheight ? 10 : 0) - 1) >> 1
										  : char_vpos[4:1] - 1;
	
	reg row_next, alt_next;
	reg row_cur, alt_cur;
	reg row_prev, alt_prev;
	
	reg [8:0] foreground, foreground_1, foreground_2, next_foreground;
	reg [8:0] background, background_1, background_2;
	reg graphics_mode;
	reg graphics_char;
	reg control_char;
	reg sep_graphics;
	reg hold_graphics, next_hold_graphics;
	reg [7:0] held_char, held_char_1, next_held_char;
	reg held_sep_graphics;
	reg flash_enabled, flash_enabled_1, flash_enabled_2;

	reg [9:0] tt_prev_row_addr;
	reg [9:0] tt_cur_row_addr;

	/* 0  1  2  3  4 ... 12 13 14
	   ^--read character											--
		   ^--read glyph											--
			   ^--read first pixel ("next")					--
				   ^--read second pixel ("current" ready)	draw 0th pixel
					   ^--read third pixel ("prev" ready)	draw 1st pixel
						   ...										...
						      ^--read next character			draw 9th pixel
								   ^--read next glyph			draw 10th pixel
   */

	always @(posedge clock) begin
		if (reset) begin
			row_next <= 0;
			alt_next <= 0;
			row_prev <= 0;
			alt_prev <= 0;
			row_cur <= 0;
			alt_cur <= 0;
		end else begin
			row_prev <= row_cur;
			alt_prev <= alt_cur;
			row_cur <= row_next;
			alt_cur <= alt_next;

			if (prev_doubleheight && !current_doubleheight) begin
				row_next <= 0;
				alt_next <= 0;
			end else if (hold_graphics && control_char) begin
				if (held_sep_graphics
					 && (char_vpos_lo == 2 || char_vpos_lo == 6
						  || char_vpos_lo == 9 || char_hpos_lo == 2
						  || char_hpos_lo == 5))
					row_next <= 0;
				else begin
					if (char_vpos_lo <= 2)
						row_next <= (char_hpos_lo <= 2) ? held_char[0]
																	: held_char[1];
					else if (char_vpos_lo <= 6)
						row_next <= (char_hpos_lo <= 2) ? held_char[2]
																	: held_char[3];
					else
						row_next <= (char_hpos_lo <= 2) ? held_char[4]
																	: held_char[6];
				end
				alt_next <= 0;
			end else if (graphics_char) begin
				if (sep_graphics
					 && (char_vpos_lo == 2 || char_vpos_lo == 6
						  || char_vpos_lo == 9 || char_hpos_lo == 2
						  || char_hpos_lo == 5))
					row_next <= 0;
				else begin
					if (char_vpos_lo <= 2)
						row_next <= (char_hpos_lo <= 2) ? current_char_1[0]
																	: current_char_1[1];
					else if (char_vpos_lo <= 6)
						row_next <= (char_hpos_lo <= 2) ? current_char_1[2]
																	: current_char_1[3];
					else
						row_next <= (char_hpos_lo <= 2) ? current_char_1[4]
																	: current_char_1[6];
				end
				alt_next <= 0;
			end else begin
				row_next <= (char_vpos_lo >= 1 && char_vpos_lo <= 9
								 && char_hpos_lo <= 4)
								? glyph_bits[(char_vpos_lo - 1) * 5 + char_hpos_lo]
								: 0;

				if ((!current_doubleheight && char_vpos[0])
					 || (current_doubleheight && char_vpos[1]))
					alt_next <= (char_vpos_lo >= 1 && char_vpos_lo <= 8
									 && char_hpos_lo <= 4)
									? glyph_bits[(char_vpos_lo_n - 1) * 5 + char_hpos_lo]
									: 0;
				else
					alt_next <= (char_vpos_lo <= 9 && char_hpos_lo <= 4
									 && char_vpos_lo >= 2)
									? glyph_bits[(char_vpos_lo_p - 1) * 5 + char_hpos_lo]
									: 0;
			end
		end
	end
	
	reg [11:0] r_offset;
	reg [11:0] g_offset;
	reg [11:0] b_offset;
	
	reg new_frame;
	
	always @(posedge clock) begin
		if (reset) begin
			r_offset <= 0;
			g_offset <= 0;
			b_offset <= 0;
			new_frame <= 0;
		end else begin
			if (vstate == `V_SYNCPULSE && !new_frame) begin
				new_frame <= 1;
				r_offset <= r_offset + 1;
				g_offset <= g_offset + 2;
				b_offset <= b_offset + 3;
			end else if (vstate != `V_SYNCPULSE) begin
				new_frame <= 0;
			end
		end
	end
	
	wire [7:0] rh = htimer + r_offset[11:3];
	wire [7:0] rv = vtimer + g_offset[11:3];
	wire [7:0] gh = htimer + g_offset[11:3];
	wire [7:0] gv = vtimer - r_offset[11:3];
	wire [7:0] bh = htimer - r_offset[11:3];
	wire [7:0] bv = vtimer + b_offset[11:3];
	
	always @(posedge clock) begin
		if (reset) begin
			red <= 0;
			green <= 0;
			blue <= 0;
		end else begin
			if (char_out[3] && !flash_display && flash_enabled_2) begin
				red <= background_2[2:0];
				green <= background_2[5:3];
				blue <= background_2[8:6];
			end else if (char_out[3] && !graphics_char) begin
				if (row_cur
					 || (!row_prev && row_next && alt_prev && !alt_next)
					 || (row_prev && !row_next && !alt_prev && alt_next)) begin
					red <= foreground_2[2:0];
					green <= foreground_2[5:3];
					blue <= foreground_2[8:6];
				end else begin
					red <= background_2[2:0];
					green <= background_2[5:3];
					blue <= background_2[8:6];
				end
			end else if (char_out[3] && graphics_char) begin
				if (row_cur) begin
					red <= foreground_2[2:0];
					green <= foreground_2[5:3];
					blue <= foreground_2[8:6];
				end else begin
					red <= background_2[2:0];
					green <= background_2[5:3];
					blue <= background_2[8:6];
				end
			end else if (border_out[3]) begin
				red <= rh[5] ^ rv[5];
				green <= gh[4] ^ gv[4];
				blue <= bh[6:5] ^ bv[6:5];
			end else begin
				red <= 0;
				green <= 0;
				blue <= 0;
			end
		end
	end

	// Teletext write
	//always @(posedge tt_write_clock) begin
	//	if (tt_write) begin
	//		frame[tt_address] <= tt_data;
	//	end
	//end

	//always @(posedge clock) begin
	//	tt_fetch_addr <= (row_num - prev_doubleheight) * 40 + col_num;
	//end

	// Teletext control
	always @(posedge clock) begin
		if (reset) begin
			col_num <= 0;
			row_num <= 0;
			char_hpos <= 0;
			char_vpos <= 0;
			char_out <= 0;
			border_out <= 0;
			current_char <= 0;
			current_char_1 <= 0;
			glyph_bits <= 0;
			foreground <= 9'b111111111;
			foreground_1 <= 9'b111111111;
			foreground_2 <= 9'b111111111;
			background <= 9'b000000000;
			background_1 <= 9'b000000000;
			background_2 <= 9'b000000000;
			graphics_mode <= 0;
			graphics_char <= 0;
			control_char <= 0;
			sep_graphics <= 0;
			hold_graphics <= 0;
			next_hold_graphics <= 0;
			held_char <= 0;
			held_char_1 <= 0;
			held_sep_graphics <= 0;
			flash_display <= 0;
			flash_enabled <= 0;
			flash_enabled_1 <= 0;
			flash_enabled_2 <= 0;
			current_doubleheight <= 0;
			sticky_doubleheight <= 0;
			prev_doubleheight <= 0;
		end else begin
			char_out[3:1] <= char_out[2:0];
			border_out[3:1] <= border_out[2:0];
			current_char_1 <= current_char;
			held_char_1 <= held_char;
			foreground_1 <= foreground;
			background_1 <= background;
			foreground_2 <= foreground_1;
			background_2 <= background_1;
			flash_enabled_1 <= flash_enabled;
			flash_enabled_2 <= flash_enabled_1;
			
			if (show_now) begin
				if (htimer >= (`HT_VIDEO / 2 - 240)
					 && htimer < (`HT_VIDEO / 2 + 240)
					 && vtimer >= (`VT_VIDEO / 2 - 250)
					 && vtimer < (`VT_VIDEO / 2 + 250)) begin

					if (char_hpos == 0) begin
						current_char <= tt_fetch_data;
						//frame[row_num * 40 + col_num];
					end else if (char_hpos == 1) begin
						if (current_char[6:0] >= 32) begin
							if (!graphics_mode
								  || (current_char[6:0] >= 64
										&& current_char[6:0] < 96)) begin
								glyph_bits <= font[current_char[6:0] - 32];
								graphics_char <= 0;
							end else begin
								glyph_bits <= 0;
								graphics_char <= 1;
								//if (next_hold_graphics) begin
								next_held_char <= current_char;
								held_sep_graphics <= sep_graphics;
								//end
							end
							control_char <= 0;
						end else begin
							glyph_bits <= 0;
							graphics_char <= 0;
							control_char <= 1;
						end

						casex (current_char[6:0])
						7'b00x0000: next_foreground <= 9'b000000000;
						7'b00x0001: next_foreground <= 9'b000000111;
						7'b00x0010: next_foreground <= 9'b000111000;
						7'b00x0011: next_foreground <= 9'b000111111;
						7'b00x0100: next_foreground <= 9'b111000000;
						7'b00x0101: next_foreground <= 9'b111000111;
						7'b00x0110: next_foreground <= 9'b111111000;
						7'b00x0111: next_foreground <= 9'b111111111;
						7'b0001000: flash_enabled <= 1;
						7'b0001001: flash_enabled <= 0;
						7'b0001100: /* normal height */ begin
							next_hold_graphics <= 0;
							current_doubleheight <= 0;
						end
						7'b0001101: /* double height */ begin
							next_hold_graphics <= 0;
							if (!prev_doubleheight)
								sticky_doubleheight <= 1;
							current_doubleheight <= 1;
						end
						7'b0011001: sep_graphics <= 0;
						7'b0011010: sep_graphics <= 1;
						7'b0011100: background <= 9'b000000000;
						7'b0011101: background <= next_foreground;
						7'b0011110: next_hold_graphics <= 1;
						7'b0011111: begin
							next_hold_graphics <= 0;
							next_held_char <= 0;
						end
						endcase
						
						if (current_char[6:0] >= 0 && current_char[6:0] <= 7) begin
							graphics_mode <= 0;
							next_hold_graphics <= 0;
							next_held_char <= 0;
						end else if (current_char[6:0] >= 16 && current_char[6:0] <= 23)
							graphics_mode <= 1;

						/* Change of foreground colour affects the *next*
							character.  */
						foreground <= next_foreground;
						hold_graphics <= next_hold_graphics;
						held_char <= next_held_char;
					end

					char_out[0] <= 1;
					border_out[0] <= 0;

					char_hpos_1 <= char_hpos;
					char_hpos_2 <= char_hpos_1;

					if (char_hpos == 1) begin
						if (col_num == 39) begin
							if ((!sticky_doubleheight && char_vpos == 18)
								 || (sticky_doubleheight && char_vpos == 19)) begin
								tt_cur_row_addr <= tt_cur_row_addr + 40;
								tt_prev_row_addr <= tt_cur_row_addr;
							end

							if (prev_doubleheight) begin
								tt_fetch_addr <= tt_prev_row_addr;
							end else begin
								tt_fetch_addr <= tt_cur_row_addr;
							end
						end else begin
							tt_fetch_addr <= tt_fetch_addr + 1;
						end
					end

					if (char_hpos == 11) begin
						char_hpos <= 0;

						if (col_num == 39) begin
							col_num <= 0;

							/* all the vertical stuff. */
							if (char_vpos == 19) begin
								char_vpos <= 0;
								row_num <= row_num + 1;
								prev_doubleheight <= sticky_doubleheight;
								sticky_doubleheight <= 0;
								current_doubleheight <= 0;
							end else
								char_vpos <= char_vpos + 1;
						end else begin
							col_num <= col_num + 1;
						end
					end else begin
						char_hpos <= char_hpos + 1;
					end
				end else begin
					if (htimer >= (`HT_VIDEO / 2 + 240)
						 && vtimer >= (`VT_VIDEO / 2 + 250)) begin
						char_hpos <= 0;
						col_num <= 0;
						char_vpos <= 0;
						tt_fetch_addr <= 0;
						tt_cur_row_addr <= 0;
						row_num <= 0;
						current_doubleheight <= 0;
						sticky_doubleheight <= 0;
						prev_doubleheight <= 0;
						if (frame_counter < 72)
							flash_display <= 1;
						else
							flash_display <= 0;
					end
					border_out[0] <= 1;
					char_out[0] <= 0;
					/* We want to start a new row with white/black -- resetting
						them here works as well as anywhere.  */
					if (htimer >= (`HT_VIDEO / 2 + 240)) begin
						foreground <= 9'b111111111;
						next_foreground <= 9'b111111111;
						background <= 9'b000000000;
						graphics_mode <= 0;
						sep_graphics <= 0;
						hold_graphics <= 0;
						next_hold_graphics <= 0;
						held_char <= 0;
						next_held_char <= 0;
						held_sep_graphics <= 0;
						flash_enabled <= 0;
					end
				end
			end else begin
				border_out[0] <= 0;
				char_out[0] <= 0;
			end
		end
	end
	
	// Delayed h-sync & blanking signals
	always @(posedge clock) begin
		if (reset) begin
			hsync_delay <= 0;
			vsync_delay <= 0;
		end else begin
`ifdef HSYNC_POS
			hsync_delay[0] <= hstate == `H_SYNCPULSE;
`else
			hsync_delay[0] <= hstate != `H_SYNCPULSE;
`endif

`ifdef VSYNC_POS
			vsync_delay[0] <= vstate == `V_SYNCPULSE;
`else
			vsync_delay[0] <= vstate != `V_SYNCPULSE;
`endif
			
			hsync_delay[3:1] <= hsync_delay[2:0];
			hsync_delay[3:1] <= hsync_delay[2:0];
			vsync_delay[3:1] <= vsync_delay[2:0];
		end
	end
	
	// VGA state machine
	always @(posedge clock) begin
		if (reset) begin
			hstate <= `H_BACKPORCH;
			htimer <= 100;
			vstate <= `V_BACKPORCH;
			vtimer <= 100;
			frame_counter <= 0;
		end else begin
			/* Update state machine.  */
			if (htimer == 0) begin
				/* Switch on the state we just completed.  */
				case (hstate)
				`H_VIDEO: begin
					hstate <= `H_FRONTPORCH;
					htimer <= `HT_FRONTPORCH - 1;
				end
				
				`H_FRONTPORCH: begin
					hstate <= `H_SYNCPULSE;
					htimer <= `HT_SYNCPULSE - 1;
				end
				
				`H_SYNCPULSE: begin
					hstate <= `H_BACKPORCH;
					htimer <= `HT_BACKPORCH - 1;
				end
				
				`H_BACKPORCH: begin
					hstate <= `H_VIDEO;
					htimer <= `HT_VIDEO - 1;
					if (vtimer == 0) begin
						case (vstate)
						`V_VIDEO: begin
							vstate <= `V_FRONTPORCH;
							vtimer <= `VT_FRONTPORCH - 1;
						end
						
						`V_FRONTPORCH: begin
							vstate <= `V_SYNCPULSE;
							vtimer <= `VT_SYNCPULSE - 1;
						end
						
						`V_SYNCPULSE: begin
							vstate <= `V_BACKPORCH;
							vtimer <= `VT_BACKPORCH - 1;
						end
						
						`V_BACKPORCH: begin
							vstate <= `V_VIDEO;
							vtimer <= `VT_VIDEO - 1;
							if (frame_counter == 96)
								frame_counter <= 0;
							else
								frame_counter <= frame_counter + 1;
						end
						endcase
					end else /* vtimer != 0.  */
						vtimer <= vtimer - 1;
				end
				endcase
			end else	/* htimer != 0.  */
				htimer <= htimer - 1;
		end /* !reset.  */
	end
endmodule
