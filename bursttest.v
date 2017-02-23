`timescale 1ns / 1ps

module bursttest(
		// System clock
		input				system_clk,
		
		// Reset push-switch
		input				button_nrst,
		//input				sw3,
		
		// Parasite CPU I/O
		input [23:0]	pcpu_address,
		inout [7:0]		pcpu_data,
		//input 			pcpu_emulmode,
		input				pcpu_read,
		output reg [1:0]	pcpu_clk,
		//input				pcpu_rclk,
		output			pcpu_nmi,
		output			pcpu_irq,
		output			pcpu_rst,
		output			pcpu_nrdy,
		
		// SDRAM I/O
		input				sdram_sclkfb,
		output			sdram_sclk,
		output			sdram_cke,
		output			sdram_cs_n,
		output			sdram_ras_n,
		output			sdram_cas_n,
		output			sdram_we_n,
		output [1:0]	sdram_ba,
		output [12:0]	sdram_saddr,
		inout [15:0]	sdram_sdata,
		output			sdram_dqmh,
		output			sdram_dqml,
		
		// Flash I/O
		output			flash_ce,
		output			flash_oe,
		output			flash_we,
		output [20:0]	flash_address,
		inout [7:0]		flash_data,
		output			flash_reset,
		output			flash_byte,
		
		// LCD I/O
		output			lcd_cs,
		
		// VGA out
		output			vga_hsync,
		output			vga_vsync,
		output [2:0]	vga_red,
		output [2:0]	vga_green,
		output [2:0]	vga_blue
	);

	wire clk1x;

	reg [7:0] char_val;

	// Reset handling
	wire held_in_reset;
	wire reset = !button_nrst || held_in_reset;

	wire locked;
	reg sync_reset;

	reg [5:0] reset_for_longer;

	always @(posedge clk1x) begin
		if (reset || !locked) begin
			sync_reset <= 1;
			reset_for_longer <= 63;
		end else begin
			if (reset_for_longer == 0)
				sync_reset <= 0;
			else
				reset_for_longer <= reset_for_longer - 1;
		end
	end

	// Flash pins
	assign flash_data = char_val;
	assign flash_ce = 0;
	assign flash_oe = 0;
	assign flash_we = 0;
	assign flash_reset = 0;
	assign flash_byte = 0;
	assign flash_address = 0;
		
	// Host CPU
	// Parasite CPU
	
	assign pcpu_nmi = 0;
	assign pcpu_irq = 0;
	assign pcpu_rst = reset;
	
	reg ready_now;
	
	//assign pcpu_nrdy = !ready_now;
	//assign pcpu_nrdy = 0;
	
	// VGA
	/*
	assign vga_red = 0;
	assign vga_green = 0;
	assign vga_blue = 0;
	assign vga_hsync = 0;
	assign vga_vsync = 0;
	*/

	// SDRAM
	wire sdram_outen;
	wire [15:0] data_to_sdram;
	wire [15:0] data_from_sdram;

	wire clkdv;

	reg sdram_rd;
	reg sdram_wr;
	wire sdram_data_ready;
	/*wire sdram_writing;*/
	wire [15:0] sdram_out;
	reg [23:0] sdram_addr;
	wire [2:0] sdram_burst_offset;
	wire [15:0] sdram_in;
	wire collision;

	assign sdram_sdata = sdram_outen ? 16'hzzzz : data_to_sdram;
	assign data_from_sdram = sdram_outen ? sdram_sdata : 16'h0000;

	reg [23:0] vga_addr;
	reg vga_read_req;
	wire vga_ready;

	reg [4:0] vga_getter;

	always @(posedge clk1x) begin
		if (sync_reset) begin
			vga_addr <= 0;
			vga_read_req <= 0;
			vga_getter <= 0;
		end else begin
			if (vga_getter == 0) begin
				//vga_read_req <= 1;
			end else
				vga_read_req <= 0;
			vga_getter <= vga_getter + 1;
		end
	end

	sdramburst #(
		.HADDR_WIDTH	(24),
		.DATA_WIDTH		(16),
		.SADDR_WIDTH	(13)
	) sdramburst1 (
		// Host connections
		.clk				(system_clk),
		.rst				(sync_reset),
		.sdram_clkfb	(sdram_sclkfb),
		.lock				(locked),
		.clk1x			(clk1x),
		.clkdv			(clkdv),
		.held_in_reset	(held_in_reset),
		.rd				(sdram_rd),
		.wr				(sdram_wr),
		.ready			(sdram_data_ready),
		/*.writing			(sdram_writing),*/
		.burst_offset	(sdram_burst_offset),
		.hAddr			(sdram_addr),
		.hDOut			(sdram_out),
		.hDIn				(sdram_in),
		.collision		(collision),
		
		// VGA connections
		.vgaAddr			(vga_addr),
		.vga_rd			(vga_read_req),
		.vga_ready		(vga_ready),
		
		// SDRAM connections
		.sdram_clk		(sdram_sclk),
		.cke				(sdram_cke),
		.ce_n				(sdram_cs_n),
		.ras_n			(sdram_ras_n),
		.cas_n			(sdram_cas_n),
		.we_n				(sdram_we_n),
		.ba				(sdram_ba),
		.sAddr			(sdram_saddr),
		.sDIn				(data_to_sdram),
		.sDOut			(data_from_sdram),
		.sDOutEn			(sdram_outen),
		.dqmh				(sdram_dqmh),
		.dqml				(sdram_dqml)
	);

	vga vga1 (
		.clock			(clkdv),
		.hsync			(vga_hsync),
		.vsync			(vga_vsync),
		.red				(vga_red),
		.green			(vga_green),
		.blue				(vga_blue),
		.reset			(sync_reset)
	);

`undef SLOWER_CLOCK

`ifdef SLOWER_CLOCK
	reg slower;
`endif
	
	reg [3:0] clockphase;
	
	always @(posedge clk1x) begin
		if (sync_reset) begin
			clockphase <= 0;
`ifdef SLOWER_CLOCK
			slower <= 0;
`endif
		end else begin
`ifdef SLOWER_CLOCK
			if (slower == 0)
				clockphase <= clockphase + 1;
			slower <= slower + 1;
`else
			clockphase <= clockphase + 1;
`endif
		end
	end
	
	/* The actual clock seen by the CPU is externally inverted so will be:
	
	   0   4   8   12
		x x x x x x x x 
		.       ,_______
		|       |
		|_______|
   */
	
	//wire phi2_hi = pcpu_clk[1];

	reg wait_for_cache;
	
	always @(posedge clk1x) begin
		if (sync_reset) begin
			pcpu_clk[0] <= 0;
			pcpu_clk[1] <= 1;
		end else	if (clockphase == 0) begin
			pcpu_clk[0] <= 1;
			pcpu_clk[1] <= 0;
		end else if (clockphase == 8 && !wait_for_cache) begin
			pcpu_clk[0] <= 0;
			pcpu_clk[1] <= 1;
		end
	end

	wire cpu_reading = pcpu_read && clockphase == 7;
	/* This is when the data written by the CPU is actually ready.  */
	wire cpu_writing = !pcpu_read && clockphase == 0;
	/* ...but we know that we are doing a write, and the address we are
		writing to, at this point.  Critically, this is before the CPU's
		phi2 clock input goes high.  */
	wire cpu_writing_early = !pcpu_read && clockphase == 7;
	
   reg [1:0] addr_select;
	
	always @* begin // safe_implementation yes
		case (pcpu_address[15:9])
		7'b0000000:
			addr_select = 0;
		7'b0000001:
			addr_select = 1;
		7'b0000010:
			addr_select = 2;
		7'b1111111:
			addr_select = 1;
		default:
			addr_select = 3;
		endcase
	end

	// Some little SRAMs
	
	wire ram0_en = (addr_select == 0);
	wire [7:0] ram0_do;
	
	wire ram0_rden = cpu_reading;
	wire ram0_wren = ram0_en && cpu_writing;
	
	RAMB4_S8 ram0 (
		.DO			(ram0_do),
		.DI			(pcpu_data),
		.ADDR			(pcpu_address[8:0]),
		.CLK			(clk1x),
		.EN			(ram0_rden || ram0_wren),
		.WE			(ram0_wren)
	);

	wire ram1_en = (addr_select == 1);
	wire [7:0] ram1_do;

	wire ram1_rden = cpu_reading;
	wire ram1_wren = ram1_en && cpu_writing;

	RAMB4_S8 #(
		`include "soft/tinyhello2.v"
	) ram1 (
		.DO			(ram1_do),
		.DI			(pcpu_data),
		.ADDR			(pcpu_address[8:0]),
		.CLK			(clk1x),
		.EN			(ram1_rden || ram1_wren),
		.WE			(ram1_wren)
	);

	reg [31:0] cacheline_valid;

	reg [14:0] cached_address [0:31];
	reg wait_for_fill;
	reg wait_for_spill;

	wire [4:0] cache_line_select = pcpu_address[8:4];

	reg [14:0] cache_line_addr;
	reg invalid_cache_line;
	
	always @(posedge clk1x) begin
		if (sync_reset) begin
			cache_line_addr <= 0;
			invalid_cache_line <= 0;
		end else begin
			cache_line_addr <= cached_address[cache_line_select];
			invalid_cache_line <= !cacheline_valid[cache_line_select];
		end
	end

	wire cache_miss = pcpu_address[23:9] != cache_line_addr
							|| invalid_cache_line;

	wire [7:0] ram2_do;
	wire ram2_en = (addr_select == 2);
	wire ram2_rden = ram2_en && cpu_reading;
	wire ram2_wren = !cache_miss && ram2_en && cpu_writing;

	wire fill_en = wait_for_fill && sdram_data_ready;
	wire spill_or_refill = wait_for_spill || fill_en;

	/* 512 glorious bytes of cache!  The dullest kind, direct-mapped.  */
	RAMB4_S8_S16 cache (
		/* A port.  */
		.DOA			(ram2_do),
		.ADDRA		(pcpu_address[8:0]),
		.CLKA			(clk1x),
		.DIA			(pcpu_data),
		.ENA			(ram2_en && !wait_for_cache),
		.RSTA			(sync_reset),
		.WEA			(ram2_wren && !wait_for_cache),

		/* B port.  */
		.DOB			(sdram_in),
		.ADDRB		({ cache_line_select, sdram_burst_offset}),
		.CLKB			(clk1x),
		.DIB			(sdram_out),
		.ENB			(spill_or_refill),
		.RSTB			(sync_reset),
		.WEB			(fill_en)
	);

	reg [31:0] read_buf_dirty;

	reg [7:0] data_from_ram;
	reg ram_active;
	
	always @* begin
		if (ram0_en) begin
			data_from_ram = ram0_do;
			ram_active = 1;
		end else if (ram1_en) begin
			data_from_ram = ram1_do;
			ram_active = 1;
		end else if (ram2_en) begin
			data_from_ram = ram2_do;
			ram_active = 1;
		end else begin
			data_from_ram = 0;
			ram_active = 0;
		end
	end

	assign pcpu_data = (pcpu_read && ram_active) ? data_from_ram : 8'bzzzzzzzz;

	/* 0xfd00/0xfd01.  */
	wire lcd_addr = pcpu_address[15:1] == 15'b111111010000000;
	assign lcd_cs = lcd_addr && !ram_active;

	reg [4:0] cacheline_init;
	
	always @(posedge clk1x) begin
		if (sync_reset) begin
			sdram_rd <= 0;
			sdram_wr <= 0;
			sdram_addr <= 0;
			wait_for_fill <= 0;
			wait_for_spill <= 0;
			wait_for_cache <= 0;
			read_buf_dirty <= 0;
			cacheline_valid <= 0;
		end else begin
			if (wait_for_cache) begin
				if (sdram_wr)
					sdram_wr <= 0;

				if (wait_for_spill) begin
					if (/*sdram_writing &&*/ sdram_burst_offset == 7) begin
						wait_for_spill <= 0;
						wait_for_fill <= 1;
						sdram_rd <= 1;
						sdram_addr <= { pcpu_address[23:4], 4'b0000 };
					end
				end else if (wait_for_fill) begin
					if (sdram_rd)
						sdram_rd <= 0;

					if (sdram_data_ready && sdram_burst_offset == 7) begin
						wait_for_fill <= 0;
						wait_for_cache <= 0;
						read_buf_dirty[cache_line_select] <= 0;
						cacheline_valid[cache_line_select] <= 1;
					end
				end
			end else if (ram2_en) begin
				if (cpu_reading || cpu_writing_early) begin
					if (cpu_writing_early && !cache_miss)
						read_buf_dirty[cache_line_select] <= 1;
					
					if (cache_miss) begin
						if (read_buf_dirty[cache_line_select]) begin
							sdram_wr <= 1;
							sdram_addr <= { cached_address[cache_line_select],
												 cache_line_select, 4'b0000 };
							wait_for_spill <= 1;
						end else begin
							sdram_rd <= 1;
							sdram_addr <= { pcpu_address[23:4], 4'b0000 };
							wait_for_fill <= 1;
							cached_address[cache_line_select] <= pcpu_address[23:9];
						end
						wait_for_cache <= 1;
					end
				end
			end // ram2_en
		end // not resetting
	end
	
/*
	reg stop_a_while;
	
	always @(posedge clk1x) begin
		if (sync_reset)
			stop_a_while <= 0;
		else begin
			if (pcpu_address[15:0] == 16'hfd03 && clockphase == 7) begin
				stop_a_while <= 1;
			end else if (stop_a_while == 1) begin
				if (sw3 == 0)
					stop_a_while <= 0;
			end
		end
	end
*/

/*
	always @(posedge clk1x) begin
		if (sync_reset)
			lcd_cs <= 0;
		else begin
			if (lcd_addr) begin
				if (pcpu_read) begin
					lcd_cs <= 1;
				end else begin
					if (clockphase == 15)
						lcd_cs <= 1;
					else if (clockphase == 7)
						lcd_cs <= 0;
				end
			end else
				lcd_cs <= 0;
		end
	end
*/

	/* This control basically doesn't work: slow down the sythesized CPU clock
		instead when we have to wait for an access.  */
	assign pcpu_nrdy = 0; // wait_for_cache;

	reg [3:0] address_looker;

	/*always @(posedge clk1x) begin
		address_looker <= pcpu_address[23:20];
	end*/

`ifdef NOTTHIS
	always @(posedge clk1x) begin
		if (sync_reset)
			address_looker <= 0;
		else begin
			if (cpu_reading || cpu_writing) begin
				case (pcpu_address[15:0])
				16'hfffc:
					if (address_looker == 0)
						address_looker <= 1;
				16'h0200:
					if (address_looker == 1)
						address_looker <= 2;
				/*16'h0101:
					if (address_looker == 1)
						address_looker <= 4;
				16'h2222:
					if (address_looker == 1)
						address_looker <= 7;
				16'h0000:
					if (address_looker == 1)
						address_looker <= 8;*/
				16'h0202:
					if (address_looker == 2)
						address_looker <= 3;
				16'hfd00:
					if (address_looker == 3)
						address_looker <= 4;
				16'h0070:
					if (address_looker == 4)
						address_looker <= 6;
				16'h0071:
					if (address_looker == 6)
						address_looker <= 7;
				16'hfd01:
					//if (address_looker == 4)
						address_looker <= 5;
				endcase
			end
		end
	end
`endif
	always @(posedge clk1x) begin
		address_looker <= cacheline_valid[3:0];
	end

	always @(posedge clk1x) begin
		if (sync_reset) begin
			char_val <= 0;
		end else begin
			case (address_looker)
			0: char_val <= 221;
			1: char_val <= 5;
			2: char_val <= 236;
			3: char_val <= 173;
			4: char_val <= 53;
			5: char_val <= 185;
			6: char_val <= 249;
			7: char_val <= 13;
			8: char_val <= 253;
			9: char_val <= 189;
			10: char_val <= 125;
			11: char_val <= 241;
			12: char_val <= 216;
			13: char_val <= 229;
			14: char_val <= 248;
			15: char_val <= 120;
			endcase
		end
	end
		
endmodule
