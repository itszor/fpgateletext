`include "config.v"

module system(
		// System clock
		system_clk,
		
		// Reset push-switch
		button_nrst,

		// Parasite CPU I/O
		pcpu_address,
		pcpu_data,
		pcpu_emulmode,
		pcpu_read,
		pcpu_clk,
		pcpu_rclk,
		pcpu_nmi,
		pcpu_irq,
		pcpu_rst,
		pcpu_nrdy,

		// SDRAM I/O
		sdram_sclkfb,
		sdram_sclk,
		sdram_cke,
		sdram_cs_n,
		sdram_ras_n,
		sdram_cas_n,
		sdram_we_n,
		sdram_ba,
		sdram_saddr,
		sdram_sdata,
		sdram_dqmh,
		sdram_dqml,
		
		// Host CPU I/O
		hcpu_address,
		hcpu_data,
		hcpu_ncs,
		hcpu_read,
		hcpu_clk,
		hcpu_nirq,
		hcpu_nrst,
		
		// Flash I/O
		flash_ce,
		flash_oe,
		flash_we,
		flash_address,  // 21 bits, [19:-1]. Bit -1 is flash_data[15].
		flash_data,
		flash_reset,
		flash_byte,
		
		// LCD I/O
		lcd_cs,
		
		// VGA out
		vga_hsync,
		vga_vsync,
		vga_red,
		vga_green,
		vga_blue
	);

	// Misc
	input system_clk;
	input button_nrst;

	// Parasite CPU I/O
	input [23:0] pcpu_address;
	inout [7:0] pcpu_data;
	input pcpu_emulmode;
	input pcpu_read;  // CPU reading from memory
	output [1:0] pcpu_clk;	// bit 0 is clock, bit 1 is negated clock for external latches
	input pcpu_rclk;	// returned clock, to account for external delays
	output pcpu_nmi;
	output pcpu_irq;
	output pcpu_rst;
	output pcpu_nrdy;  // Actually bidirectional. Does that matter?
	
	// Clock enable for parasite CPU (w.r.t. SDRAM clock)
	reg pcpu_rd_en;
	reg pcpu_wr_en;
	
	// Latch for address
	reg [23:0] pcpu_addrlatch;
	
	// FIXME: Don't tie to 0!
	assign pcpu_nmi = 0;
	assign pcpu_irq = 0;
	
	// Bank address on PHI2 rising edge
	// This is now done with external logic.
	//always @(posedge pcpu_rclk) begin
		//if (pcpu_rdy)
	//	pcpu_addrlatch <= { pcpu_data, pcpu_address };
	//end

	// Parasite CPU data latch
	reg [7:0] pcpu_writedata;
	
	//always @(negedge pcpu_rclk) begin
	//	if (!pcpu_read)
	//		pcpu_datalatch <= pcpu_data;
	//end
		
	// SDRAM I/O
	input sdram_sclkfb;
	output sdram_sclk;
	output sdram_cke;
	output sdram_cs_n;
	output sdram_ras_n;
	output sdram_cas_n;
	output sdram_we_n;
	output [1:0] sdram_ba;
	output [12:0] sdram_saddr;
	inout [15:0] sdram_sdata;
	output sdram_dqmh;
	output sdram_dqml;

	// Host CPU I/O
	input [2:0] hcpu_address;
	inout [7:0] hcpu_data;
	input hcpu_ncs;
	input hcpu_read;
	input hcpu_clk;
	output hcpu_nirq;
	input hcpu_nrst;
	
	// Flash I/O
	output flash_ce;
	output flash_oe;
	output flash_we;
	output [20:0] flash_address;
	inout [7:0] flash_data;
	output flash_reset;
	output flash_byte;
	
	// LCD I/O
	output reg lcd_cs;
	
	// VGA out
	output vga_hsync;
	output vga_vsync;
	output [2:0] vga_red;
	output [2:0] vga_green;
	output [2:0] vga_blue;
	
	// Address decoder instantiation.
	// Address decoding internal signals
	wire ram_cs;
	wire tube_cs;
	wire rom_cs;
	wire char_cs;
	wire my_lcd_cs;
	wire hwmult_cs;

	addrdecode addrdecode1(
		.address			(pcpu_address),
		.emulmode		(pcpu_emulmode),
		.ram_cs			(ram_cs),
		.tube_cs			(tube_cs),
		.rom_cs			(rom_cs),
		.char_cs			(char_cs),
		.lcd_cs			(my_lcd_cs),
		.hwmult_cs		(hwmult_cs)
	);

	// Tube instantiation.

	reg [7:0] host_data_in;
	wire [7:0] host_data_out;

	// Latch host data bus if host is writing
	/*always @(posedge hcpu_clk) begin
		if (!hcpu_read)
			host_data_in <= hcpu_data;
	end*/

	assign hcpu_data = (hcpu_read && !hcpu_ncs) ? host_data_out : 8'bz;

	//reg [7:0] par_data_in;
	wire [7:0] par_data_out;

	// Latch parasite data bus if parasite is writing
	/*always @(posedge pcpu_rclk) begin
		if (!pcpu_read)
			par_data_in <= pcpu_datalatch;
	end*/
	
	wire tube_par_nrst;
	
	wire nc_irq;
	wire nc_nmi;
	
	wire noclock = 0;

`ifdef TUBE_SUPPORT
	tube tube1(
		.host_data_in	(host_data_in),
		.host_data_out	(host_data_out),
		.host_addr		(hcpu_address),
		.par_data_in	(pcpu_writedata),
		.par_data_out	(par_data_out),
		.par_addr		(pcpu_address[2:0]),
		.host_ncs		(hcpu_ncs),
		.host_read		(hcpu_read),
		.host_clk		(noclock),  /* hcpu_clk  */
		.host_nirq		(hcpu_nirq),
		.host_nrst		(hcpu_nrst),
		.par_ncs			(!tube_cs),
		.par_read		(pcpu_read),
		.par_clk			(pcpu_rclk),
		.par_nirq		(nc_irq),
		.par_nnmi		(nc_nmi),
		.par_nrst		(tube_par_nrst)
	);
`else
	assign hcpu_nirq = 1;
`endif

	reg manual_reset;
`ifdef GOSLOW
	reg [7:0] reset_ctr;
`else
	reg [7:0] reset_ctr;
`endif

	wire sdram_lock;
	wire auto_reset;
	wire sdram_bufclk;

	/* Hold reset high for a bit.  */
	/*SRL16 #(.INIT (16'hffff))
	shift1 (
		.Q					(auto_reset),
		.A0				(1),
		.A1				(1),
		.A2				(1),
		.A3				(1),
		.CLK				(sdram_bufclk),
		.D					(!sdram_lock)
	);*/
	/* Hold reset high until sdram stabilises (??).  */
	assign auto_reset = !sdram_lock;

	assign pcpu_rst = auto_reset || manual_reset;

	// SDRAM Instantiation.

	// Write-combining 16 bit accesses
	reg write_combine;
	reg [15:0] combine_data;
	
	wire sdram_clk1x;
	wire sdram_clk2x;
	wire sdram_rst = pcpu_rst;
`ifdef ENABLE_CACHE
	wire sdram_rd;
	wire sdram_wr;
`else
	reg sdram_rd;
	reg sdram_wr;
`endif
	wire sdram_earlyopbegun;
	wire sdram_opbegun;
	wire sdram_rdpending;
	wire sdram_done;
	wire sdram_rddone;
`ifdef ENABLE_CACHE
	wire [15:0] sdram_hdin;
`else
	`ifdef ENABLE_COMBINING
	wire [15:0] sdram_hdin = write_combine ? combine_data
									 : { pcpu_writedata, pcpu_writedata };
	`else
	wire [15:0] sdram_hdin = { pcpu_writedata, pcpu_writedata };
	`endif
`endif
	wire [15:0] sdram_hdout;
	wire [3:0] sdram_status;
`ifdef ENABLE_CACHE
	wire [7:0] sdram_outlatch;
	wire [23:0] sdram_haddr;
`else
	reg [7:0] sdram_outlatch;
`endif

	// "VRAM" port.
	wire vram_rst = pcpu_rst;
	wire vram_rd;
	wire vram_wr;
	wire vram_earlyopbegun;
	wire vram_opbegun;
	wire vram_done;
	wire vram_rddone;
	wire [23:0] vram_haddr;
	wire [15:0] vram_hdin;
	wire [15:0] vram_hdout;
	wire [3:0] vram_status;

	xsadualsdram #(.FREQ			 				(100000),
						.CLK_DIV		 				(2),
						.PIPE_EN		 				(1),
						.MAX_NOP		 				(10000),
						.MULTIPLE_ACTIVE_ROWS	(1),
						.DATA_WIDTH	 				(16),
						.NROWS       				(8192),
						.NCOLS       				(512),
						.HADDR_WIDTH 				(24),
						.SADDR_WIDTH 				(13),
						.PORT_TIME_SLOTS			(16'b1111111111111111))
	sdram1 (
		// Host side
		.clk				(system_clk),
		.bufclk			(sdram_bufclk),
		.clk1x			(sdram_clk1x),
		.clk2x			(sdram_clk2x),
		.lock				(sdram_lock),
		
		/* Port 0.  */
		.rst0				(sdram_rst),
		.rd0				(sdram_rd),
		.wr0				(sdram_wr),
		.earlyOpBegun0	(sdram_earlyopbegun),
		.opBegun0		(sdram_opbegun),
		.rdPending0		(sdram_rdpending),
		.done0			(sdram_done),
		.rdDone0			(sdram_rddone),
`ifdef ENABLE_CACHE
		.hAddr0			(sdram_haddr),
`else
		.hAddr0			(pcpu_addrlatch),
`endif
		.hDIn0			(sdram_hdin),
		.hDOut0			(sdram_hdout),
		.status0			(sdram_status),
		
		/* Port 1.  */
		.rst1				(vram_rst),
		.rd1				(vram_rd),
		.wr1				(vram_wr),
		.earlyOpBegun1	(vram_earlyopbegun),
		.opBegun1		(vram_opbegun),
		.done1			(vram_done),
		.rdDone1			(vram_rddone),
		.hAddr1			(vram_haddr),
		.hDIn1			(vram_hdin),
		.hDOut1			(vram_hdout),
		.status1			(vram_status),
		
		// SDRAM side
		.sclkfb			(sdram_sclkfb),
		.sclk				(sdram_sclk),
		.cke				(sdram_cke),
		.cs_n				(sdram_cs_n),
		.ras_n			(sdram_ras_n),
		.cas_n			(sdram_cas_n),
		.we_n				(sdram_we_n),
		.ba				(sdram_ba),
		.sAddr			(sdram_saddr),
		.sData			(sdram_sdata),
		.dqmh				(sdram_dqmh),
		.dqml				(sdram_dqml)
	);

`ifdef VGA_SUPPORT
	vga vga1(
		.clock		(sdram_clk1x),
		.hsync		(vga_hsync),
		.vsync		(vga_vsync),
		.red			(vga_red),
		.green		(vga_green),
		.blue			(vga_blue),
		.reset		(pcpu_rst),
		.rd			(vram_rd),
		.wr			(vram_wr),
		.opbegun		(vram_opbegun),
		.rddone		(vram_rddone),
		.haddr		(vram_haddr),
		.hdout		(vram_hdout)
	);
`else
	assign vga_red = 0;
	assign vga_green = 0;
	assign vga_blue = 0;
	assign vga_hsync = 0;
	assign vga_vsync = 0;
`endif

	reg pcpu_clkbuf;

	always @(pcpu_address or pcpu_clkbuf) begin
		if (pcpu_clkbuf == 1) begin
`ifdef ENABLE_COMBINING
			if (pcpu_address[23:20] == 4'b1111) begin
				pcpu_addrlatch = {pcpu_address[23:20],
										1'b0,
										pcpu_address[19:1]};
				write_combine = 1;
			end
			else begin
				pcpu_addrlatch = pcpu_address;
				write_combine = 0;
			end
`else
			pcpu_addrlatch = pcpu_address;
`endif
		end
	end

`ifdef ENABLE_CACHE
	wire cache_busy;

	wire [3:0] cstate;

	wire nocache_region = (pcpu_address[23:8] != 16'h0010);

	cache cache1 (
		.clock					(sdram_clk1x),
		.reset					(pcpu_rst),
		.address					(pcpu_addrlatch),
		.raw_address			(pcpu_address),
		.data_in					(pcpu_writedata),
		.data_out				(sdram_outlatch),
		.read_en					(pcpu_rd_en),
		.write_en				(pcpu_wr_en),
		.read						(pcpu_read),
		.busy						(cache_busy),
		.enable					(ram_cs),
		.bypass					(nocache_region),
		.combine					(write_combine),
		.sdram_rd				(sdram_rd),
		.sdram_wr				(sdram_wr),
		.sdram_earlyopbegun	(sdram_earlyopbegun),
		.sdram_opbegun			(sdram_opbegun),
		.sdram_rdpending		(sdram_rdpending),
		.sdram_done				(sdram_done),
		.sdram_rddone			(sdram_rddone),
		.sdram_haddr			(sdram_haddr),
		.sdram_hdin				(sdram_hdin),
		.sdram_hdout			(sdram_hdout),
		.cachestate				(cstate)
	);
`else
	wire [3:0] cstate = 0;
	reg [1:0] sdram_fsm;
	
	`define SDRAM_IDLE		0
	`define SDRAM_INITIATE	1
	`define SDRAM_WORKING	2
	
	always @(posedge sdram_clk1x or posedge pcpu_rst) begin
		if (pcpu_rst) begin
			sdram_outlatch <= 0;
			sdram_rd <= 0;
			sdram_wr <= 0;
			sdram_fsm <= `SDRAM_IDLE;
		end
		else begin
			case (sdram_fsm)
			`SDRAM_IDLE: begin
				if (ram_cs && pcpu_rd_en && pcpu_read) begin
					sdram_rd <= 1;
					sdram_fsm <= `SDRAM_INITIATE;
				end
				else if (ram_cs && pcpu_wr_en && !pcpu_read) begin
					if (write_combine) begin
						if (pcpu_address[0] == 0)
							combine_data[7:0] <= pcpu_writedata;
						else begin
							combine_data[15:8] <= pcpu_writedata;
							sdram_wr <= 1;
							sdram_fsm <= `SDRAM_INITIATE;
						end
					end
					else begin
						sdram_wr <= 1;
						sdram_fsm <= `SDRAM_INITIATE;
					end
				end
			end
			
			`SDRAM_INITIATE: begin
				if (sdram_done) begin
					sdram_rd <= 0;
					sdram_wr <= 0;
					sdram_outlatch <= sdram_hdout[7:0];
					sdram_fsm <= `SDRAM_IDLE;
				end
				else if (sdram_opbegun) begin
					sdram_rd <= 0;
					sdram_wr <= 0;
					sdram_fsm <= `SDRAM_WORKING;
				end
			end
			
			`SDRAM_WORKING: begin
				if (sdram_done || sdram_rddone) begin
					sdram_outlatch <= sdram_hdout[7:0];
					sdram_fsm <= `SDRAM_IDLE;
				end
				else if (!sdram_rdpending && !sdram_rd && !sdram_wr
							&& !sdram_earlyopbegun && !sdram_opbegun) begin
					sdram_fsm <= `SDRAM_IDLE;
				end
			end
			endcase
		end
	end
`endif

	// Flash handling

	wire flash_enable = rom_cs && pcpu_read;

	// Use 11 bits (i.e. 2048 bytes) for Flash address.
	// Use second bank (so first can configure FPGA).
	assign flash_address = { 10'b0100000000, pcpu_address[10:0] };
	// These four are all active-low
	assign flash_we = flash_enable;
	assign flash_oe = !flash_enable;
	assign flash_ce = !flash_enable;
	assign flash_reset = 1;
	// Use byte mode for flash access
	assign flash_byte = 0;

	// LCD handling
	reg lcd_cs_buf;
	//assign lcd_cs = my_lcd_cs;
	
	// try to align LCD chip-select with read/write enable
	always @(posedge sdram_clk1x) begin
		lcd_cs <= my_lcd_cs;
	end

	// Seven-segment display handling.

`ifdef TEST

	reg [7:0] char_val;
	// The seven-seg display lives on the flash data lines.
	assign flash_data = char_val;

`ifdef _DUMMY_
	reg [3:0] seen_addr_reset;

	always @(posedge sdram_clk1x) begin
		if (pcpu_rst)
			seen_addr_reset <= 0;
		else begin
			if (seen_addr_reset == 0 && pcpu_addrlatch[15:0] == 16'hfffc)
				seen_addr_reset <= 1;
			else if (seen_addr_reset == 1 && pcpu_addrlatch[15:0] == 16'h0000)
				seen_addr_reset <= 2;
			//else if (pcpu_address[15:0] == 16'hfef0)
			else if (seen_addr_reset == 2 && sdram_outlatch == 8'ha2) // a2
				seen_addr_reset <= 3;
			else if (seen_addr_reset == 3 && sdram_outlatch == 8'hff)
				seen_addr_reset <= 4;
			else if (seen_addr_reset == 4 && sdram_outlatch == 8'h9a)
				seen_addr_reset <= 5;
			else if (seen_addr_reset == 5 && sdram_outlatch == 8'ha9)
				seen_addr_reset <= 6;
			else if (seen_addr_reset == 6 && sdram_outlatch == 8'hdd)
				seen_addr_reset <= 7;
			else if (pcpu_address[15:0] == 16'hfef0)
				seen_addr_reset <= 8;
		end
	end
`endif

	always @(posedge sdram_clk1x or posedge auto_reset) begin
		if (auto_reset) begin
			manual_reset <= 0;
		end else begin
			if (button_nrst == 0) begin
				char_val <= 248;
`ifdef GOSLOW
				reset_ctr <= 15;
`else
				reset_ctr <= 255;
`endif
				manual_reset <= 1;
			end
			else if (reset_ctr != 0) begin
`ifdef GOSLOW
				case (reset_ctr[2:0])
`else
				case (reset_ctr[7:5])
`endif
				0: char_val <= 1;
				1: char_val <= 32;
				2: char_val <= 16;
				3: char_val <= 8;
				4: char_val <= 4;
				5: char_val <= 32;
				6: char_val <= 64;
				7: char_val <= 128;
				endcase
				reset_ctr <= reset_ctr - 1;
			end else begin
				manual_reset <= 0;
				if (pcpu_wr_en && char_cs && !pcpu_read)
					char_val <= pcpu_writedata;
				/*else
					char_val <= pcpu_addrlatch[15:8];*/
				/*else begin
					case (sdram_fsm)
					`SDRAM_IDLE: char_val <= 221;
					`SDRAM_INITIATE: char_val <= 5;
					`SDRAM_WORKING: char_val <= 236;
					endcase
				end*/
				else begin
					//case (seen_addr_reset)
					case (cstate)
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
		end
	end
`endif

	reg [63:0] mult_a;
	reg [31:0] mult_b;
	reg [63:0] mult_res;
	reg mul_operation;

	reg [7:0] mult_dataout;

	/* Hardware multiplier.  */
	always @(posedge sdram_clk1x) begin
		if (mul_operation) begin
			if (mult_b == 0)
				mul_operation <= 0;
			else begin
				if (mult_b[0])
					mult_res <= mult_res + mult_a;
				mult_a <= {mult_a[62:0], 1'b0};
				mult_b <= {1'b0, mult_b[31:1]};
			end
		end
		else begin
			if (hwmult_cs) begin
				if (!pcpu_read && pcpu_wr_en) begin
					case (pcpu_address[3:0])
					0: mult_a[7:0] <= pcpu_writedata;
					1: mult_a[15:8] <= pcpu_writedata;
					2: mult_a[23:16] <= pcpu_writedata;
					3: mult_a[31:24] <= pcpu_writedata;
					4: mult_b[7:0] <= pcpu_writedata;
					5: mult_b[15:8] <= pcpu_writedata;
					6: mult_b[23:16] <= pcpu_writedata;
					7: mult_b[31:24] <= pcpu_writedata;
					15: begin
						case (pcpu_writedata)
						0: begin
							mul_operation <= 1;
							mult_a[63:32] <= 0;
							mult_res <= 0;
						end
						
						default: mul_operation <= 0;
						endcase
					end
					endcase
				end
				else if (pcpu_read && pcpu_rd_en) begin
					case (pcpu_address[3:0])
					0: mult_dataout <= mult_a[7:0];
					1: mult_dataout <= mult_a[15:8];
					2: mult_dataout <= mult_a[23:16];
					3: mult_dataout <= mult_a[31:24];
					4: mult_dataout <= mult_b[7:0];
					5: mult_dataout <= mult_b[15:8];
					6: mult_dataout <= mult_b[23:16];
					7: mult_dataout <= mult_b[31:24];
					8: mult_dataout <= mult_res[7:0];
					9: mult_dataout <= mult_res[15:8];
					10: mult_dataout <= mult_res[23:16];
					11: mult_dataout <= mult_res[31:24];
					12: mult_dataout <= mult_res[39:32];
					13: mult_dataout <= mult_res[47:40];
					14: mult_dataout <= mult_res[55:48];
					15: mult_dataout <= mult_res[63:56];
					endcase
				end
			end
		end
	end

	// Select parasite input (or float if parasite is writing)
	assign pcpu_data = (pcpu_read && ram_cs) ? sdram_outlatch :
							 (pcpu_read && tube_cs) ? par_data_out :
							 (pcpu_read && rom_cs) ? flash_data :
							 (pcpu_read && hwmult_cs) ? mult_dataout :
							 8'bz;
			
	// Parasite CPU clock generation. "system_clk" runs at 100MHz.
	// sdram_clk1x runs at 50MHz.
	// Divide by 16 to get a clock of 3.125MHz (probably good enough for testing).
	// FIXME: We can probably use the CPLD for this secondary clock generation.
	// FIXME: Currently running with divide by 256 (or 2^19).

`ifdef GOSLOW
	reg [19:0] clkdiv;
`define CYCLE 1048576
`else
	reg [9:0] clkdiv;
`define CYCLE 1024
`endif
		
	/* Note: clock is inverted by external logic.
	   bit 0 is the CPU clock (non-negated)
		bit 1 is the external latch clock (negated).  */
	assign pcpu_clk = {pcpu_clkbuf, !pcpu_clkbuf};

	/* Only change RDY when PH2 is high.  */
	/*always @(wait_for_sdram or pcpu_clkbuf) begin
		if (pcpu_clkbuf)
			pcpu_nrdy = wait_for_sdram;
		else
			pcpu_nrdy = 0;
	end*/

`ifdef ENABLE_CACHE
	wire wait_for_sdram = cache_busy;
`else
	wire wait_for_sdram = sdram_fsm != `SDRAM_IDLE;
`endif

	assign pcpu_nrdy = wait_for_sdram && pcpu_clkbuf;

	always @(posedge sdram_clk1x) begin
		if (pcpu_rst) begin
			pcpu_rd_en <= 0;
			pcpu_wr_en <= 0;
			pcpu_clkbuf <= 0;
			pcpu_writedata <= 0;
			clkdiv <= 0;
		end else begin
			if (clkdiv == 2) begin
				/* Hold in high state if SDRAM isn't ready yet.  */
				if (sdram_lock && !wait_for_sdram)
					clkdiv <= clkdiv - 1;
			end
			else if (clkdiv == 1) begin
				if (pcpu_clkbuf == 1) begin
					/* Write data on falling clock edge. Fuzzy!  */
					pcpu_wr_en <= 1;
					pcpu_clkbuf <= 0;
					pcpu_writedata <= pcpu_data;
				end
				else begin
					/* Latch address on rising clock edge, enable read.  */
					pcpu_rd_en <= 1;
					pcpu_clkbuf <= 1;
				end
				clkdiv <= clkdiv - 1;
			end
			else if (clkdiv == 0) begin
				pcpu_rd_en <= 0;
				pcpu_wr_en <= 0;
				clkdiv <= `CYCLE - 1;
			end
			else
				clkdiv <= clkdiv - 1;
		end
	end

endmodule
