`timescale 1ns / 1ps

module bbc2(
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

	reg [7:0] char_val;

	// Reset handling
	wire locked;
	wire reset_button = !button_nrst;

	wire reset = reset_button || !locked;
	wire clkdv_reset = !button_nrst;

	wire clk1x;
	wire clkdv;

	// Flash pins
	//assign flash_data = char_val;
	assign flash_ce = 0;
	assign flash_oe = 0;
	assign flash_we = 1;
	assign flash_reset = 1;
	assign flash_byte = 0;
	//assign flash_address = 0;
		
	// Host CPU
	// Parasite CPU
	
	assign pcpu_nmi = 0;
	assign pcpu_irq = 0;
	assign pcpu_rst = reset;
	
	reg ready_now;

	// SDRAM
	wire sdram_outen;
	wire [15:0] data_to_sdram;
	wire [15:0] data_from_sdram;

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

	reg ram_active;

	wire [4:0] sdram_state;
	wire sdram_read_requested;
	wire sdram_write_requested;

	wire cpu_clk;

	wire [23:0] cpu_address;

	sdramburst #(
		.HADDR_WIDTH	(24),
		.DATA_WIDTH		(16),
		.SADDR_WIDTH	(13)
	) sdramburst1 (
		// Host connections
		.clk				(system_clk),
		.rst				(reset),
		.sdram_clkfb	(sdram_sclkfb),
		.lock				(locked),
		.clk1x			(clk1x),
		.clkdv			(clkdv),
		.cpu_clk			(cpu_clk),
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
		.dqml				(sdram_dqml),
		
		// Internal state
		.o_state			(sdram_state),
		.read_requested	(sdram_read_requested),
		.write_requested	(sdram_write_requested)
	);

	/*wire [7:0] cpu_din;
	wire [7:0] cpu_dout;*/
   wire tt_en;
	wire cpu_reading;
	reg [1:0] cpu_phase;

	wire [7:0] ttdata;
	wire [9:0] ttaddr;

	reg [8:0] pagenum;
	reg [31:0] timecounter;

	always @(posedge clk1x) begin
		if (reset) begin
			//pagenum <= 153;
			pagenum <= 0;
			timecounter <= 0;
		end else begin
			if (timecounter == 32'hfffffff) begin
				timecounter <= 0;
				if (pagenum < 485)
					pagenum <= pagenum + 1;
				else
					pagenum <= 0;
			end else begin
				timecounter <= timecounter + 1;
			end
		end
	end

	assign flash_address = { 2'b0, pagenum, ttaddr };
	assign ttdata = flash_data;

	`define PHI1 2
	`define PHI2 0

	vga vga1 (
		.clock				(clkdv),
		.hsync				(vga_hsync),
		.vsync				(vga_vsync),
		.red					(vga_red),
		.green				(vga_green),
		.blue					(vga_blue),
		.reset				(clkdv_reset),
		.tt_write_clock	(cpu_clk),
		.tt_address			(cpu_address[9:0]),
		.tt_write			(cpu_phase == `PHI1 && tt_en && !cpu_reading && 0),
		.tt_data				(cpu_dout),
		.tt_fetch_addr		(ttaddr),
		.tt_fetch_data		(ttdata)
	);
	
	always @(posedge clk1x) begin
		pcpu_clk[0] <= 0;
		pcpu_clk[1] <= 1;
	end

	assign pcpu_data = 8'bzzzzzzzz;
	assign pcpu_nrdy = 0;

	/* 0xfd00/0xfd01.  */
	wire lcd_addr = pcpu_address[15:1] == 15'b111111010000000;
	assign lcd_cs = lcd_addr && !ram_active;
	
	wire cpu_sync;

	reg [31:0] cacheline_dirty;
	reg [31:0] cacheline_valid;
	reg [14:0] cached_address [0:31];
	reg wait_for_fill;
	reg wait_for_spill;

	wire [4:0] cache_line_select = cpu_address[8:4];

   wire [1:0] addr_select;

	/*T65 cpu1 (
		.Mode (2'b00),
		.Res_n (!reset),
		.Enable (cpu_phase == `PHI2),
		.Clk (cpu_clk),
		.Rdy (1'b1),
		.Abort_n (1'b1),
		.IRQ_n (1'b1),
		.NMI_n (1'b1),
		.SO_n (1'b1),
		.R_W_n (cpu_reading),
		.Sync (cpu_sync),
		.EF (),
		.MF (),
		.XF (),
		.ML_n (),
		.VP_n (),
		.VDA (),
		.VPA (),
		.A (cpu_address),
		.DI (cpu_din),
		.DO (cpu_dout)
	);*/

	assign addr_select = cpu_address[15:9] == 7'b0000000 ? 0
							 : cpu_address[15:9] == 7'b0000001 ? 1
							 : cpu_address[15:10] == 6'b011111 ? 2
							 : cpu_address[15:9] == 7'b1111111 ? 1
							 : 3;

	assign tt_en = (addr_select == 2);

	wire ram0_en = (addr_select == 0);
	wire [7:0] ram0_do;

	/*wire ram0_rden = cpu_reading;
	wire ram0_wren = ram0_en && !cpu_reading;

	RAMB4_S8 ram0 (
		.DO			(ram0_do),
		.DI			(cpu_dout),
		.ADDR			(cpu_address[8:0]),
		.CLK			(cpu_clk),
		.EN			(ram0_rden || ram0_wren),
		.WE			(cpu_phase == `PHI1 && ram0_wren)
	);

	wire ram1_en = (addr_select == 1);
	wire [7:0] ram1_do;

	wire ram1_rden = cpu_reading;
	wire ram1_wren = ram1_en && !cpu_reading;

	RAMB4_S8 #(
		`include "soft/filltest.inc"
	) ram1 (
		.DO			(ram1_do),
		.DI			(cpu_dout),
		.ADDR			(cpu_address[8:0]),
		.CLK			(cpu_clk),
		.EN			(ram1_rden || ram1_wren),
		.WE			(cpu_phase == `PHI1 && ram1_wren)
	);

	wire [7:0] ram2_do;
	wire ram2_en = (addr_select == 3);
	wire ram2_rden = ram2_en && cpu_reading;
	wire ram2_wren = 1'b0;

	wire fill_en = wait_for_fill && sdram_data_ready;
	wire spill_or_refill = wait_for_spill || fill_en;*/

	/* 512 glorious bytes of cache!  The dullest kind, direct-mapped.  */
	/*RAMB4_S8_S16 cache (*/
		/* A port.  */
		/*.DOA			(ram2_do),
		.ADDRA		(cpu_address[8:0]),
		.CLKA			(cpu_clk),
		.DIA			(cpu_dout),
		.ENA			(ram2_en),
		.RSTA			(reset),
		.WEA			(1'b0),*/

		/* B port.  */
		/*.DOB			(sdram_in),
		.ADDRB		({ cache_line_select, sdram_burst_offset }),
		.CLKB			(clk1x),
		.DIB			(sdram_out),
		.ENB			(spill_or_refill),
		.RSTB			(reset),
		.WEB			(fill_en)*/
	//);

	/*always @(posedge clk1x) begin
		if (reset) begin
			sdram_rd <= 0;
			sdram_wr <= 0;
			sdram_addr <= 0;
			wait_for_fill <= 0;
			wait_for_spill <= 0;
			cacheline_dirty <= 0;
			cacheline_valid <= 0;
		end else if (cpu_phase == `PHI1) begin
			if (ram2_en || wait_for_fill) begin
				if (wait_for_fill) begin
					sdram_rd <= 0;
					if (sdram_data_ready && sdram_burst_offset == 7) begin
						wait_for_fill <= 0;
						cacheline_dirty[cache_line_select] <= 0;
						cacheline_valid[cache_line_select] <= 1;
						cached_address[cache_line_select] <= cpu_address[23:9];
					end
				end else if (cacheline_valid[cache_line_select]
								 && cpu_address[23:9] == cached_address[cache_line_select]) begin
					if (!cpu_reading)
						cacheline_dirty[cache_line_select] <= 1;
					cpu_phase <= cpu_phase + 1;
				end else begin
					sdram_rd <= 1;
					sdram_addr <= { cpu_address[23:4], 4'b0000 };
					wait_for_fill <= 1;
				end
			end else
				cpu_phase <= cpu_phase + 1;
		end else
			cpu_phase <= cpu_phase + 1;
	end

	assign cpu_din = ram0_en ? ram0_do
						  : ram1_en ? ram1_do
						  : ram2_en ? ram2_do
						  : 8'b00000000;

	reg [3:0] address_watcher;

	always @(posedge clk1x) begin
		if (reset) begin
			address_watcher <= 0;
		end else begin
			case (sdram_data_ready)
			0:
				if (address_watcher == 0)
					address_watcher <= 1;
			1:
				if (address_watcher == 1)
					address_watcher <= 2;
			2:
				if (address_watcher == 2)
					address_watcher <= 3;
			3:
				if (address_watcher == 3)
					address_watcher <= 4;
			4:
				if (address_watcher == 4)
					address_watcher <= 5;
			5:
				if (address_watcher == 5)
					address_watcher <= 6;
			6:
				if (address_watcher == 6)
					address_watcher <= 7;
			7:
				if (address_watcher == 7)
					address_watcher <= 8;

			endcase
		end
	end

	always @(posedge clk1x) begin
		if (reset) begin
			char_val <= 0;
		end else begin
			case (address_watcher)
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
	end*/

endmodule
