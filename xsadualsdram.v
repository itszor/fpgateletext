`include "config.v"

`define REALLY_DUAL 1

module xsadualsdram
	#(parameter
		FREQ						= 1000000,
		CLK_DIV					= 2,
		PIPE_EN					= 0,
		MAX_NOP					= 10000,
		MULTIPLE_ACTIVE_ROWS	= 0,
		DATA_WIDTH				= 16,
		NROWS						= 8192,
		NCOLS						= 512,
		HADDR_WIDTH				= 24,
		SADDR_WIDTH				= 13,
		PORT_TIME_SLOTS		= 16'b1111000011110000)
	(
		input clk,
		output bufclk,
		output clk1x,
		output clk2x,
		output lock,
		
		/* Port 0.  */
		input rst0,
		input rd0,
		input wr0,
		output earlyOpBegun0,
		output opBegun0,
		output rdPending0,
		output done0,
		output rdDone0,
		input [HADDR_WIDTH-1:0] hAddr0,
		input [DATA_WIDTH-1:0] hDIn0,
		output [DATA_WIDTH-1:0] hDOut0,
		output [3:0] status0,
		
		/* Port 1.  */
		input rst1,
		input rd1,
		input wr1,
		output earlyOpBegun1,
		output opBegun1,
		output rdPending1,
		output done1,
		output rdDone1,
		input [HADDR_WIDTH-1:0] hAddr1,
		input [DATA_WIDTH-1:0] hDIn1,
		output [DATA_WIDTH-1:0] hDOut1,
		output [3:0] status1,
		
		/* SDRAM controller port.  */
		input sclkfb,
		output sclk,
		output cke,
		output cs_n,
		output ras_n,
		output cas_n,
		output we_n,
		output [1:0] ba,
		output [SADDR_WIDTH-1:0] sAddr,
		inout [DATA_WIDTH-1:0] sData,
		output dqmh,
		output dqml
	);

	wire sdram_rst;
	wire sdram_rd;
	wire sdram_wr;
	wire sdram_earlyopbegun;
	wire sdram_opbegun;
	wire sdram_rdpending;
	wire sdram_done;
	wire sdram_rddone;
	wire [HADDR_WIDTH-1:0] sdram_haddr;
	wire [DATA_WIDTH-1:0] sdram_hdin;
	wire [DATA_WIDTH-1:0] sdram_hdout;
	wire [3:0] sdram_status;

	/* Instantiate XSA SDRAM controller.  */
	XSASDRAMCntl #(.FREQ							(FREQ),
						.CLK_DIV						(CLK_DIV),
						.PIPE_EN						(PIPE_EN),
						.MAX_NOP		 				(MAX_NOP),
						.MULTIPLE_ACTIVE_ROWS	(MULTIPLE_ACTIVE_ROWS),
						.DATA_WIDTH					(DATA_WIDTH),
						.NROWS						(NROWS),
						.NCOLS						(NCOLS),
						.HADDR_WIDTH				(HADDR_WIDTH),
						.SADDR_WIDTH				(SADDR_WIDTH))
	sdram1 (
		// Host side
		.clk				(clk),
		.bufclk			(bufclk),
		.clk1x			(clk1x),
		.clk2x			(clk2x),
		.lock				(lock),
		.rst				(sdram_rst),
		.rd				(sdram_rd),
		.wr				(sdram_wr),
		.earlyOpBegun	(sdram_earlyopbegun),
		.opBegun			(sdram_opbegun),
		.rdPending		(sdram_rdpending),
		.done				(sdram_done),
		.rdDone			(sdram_rddone),
		.haddr			(sdram_haddr),
		.hDIn				(sdram_hdin),
		.hDOut			(sdram_hdout),
		.status			(sdram_status),
		
		// SDRAM side
		.sclkfb			(sclkfb),
		.sclk				(sclk),
		.cke				(cke),
		.cs_n				(cs_n),
		.ras_n			(ras_n),
		.cas_n			(cas_n),
		.we_n				(we_n),
		.ba				(ba),
		.sAddr			(sAddr),
		.sData			(sData),
		.dqmh				(dqmh),
		.dqml				(dqml)
	);
	
	`ifdef REALLY_DUAL
	/* Instantiate dual-port module.  */
	dualport #(.PIPE_EN				(PIPE_EN),
				  .PORT_TIME_SLOTS	(PORT_TIME_SLOTS),
				  .DATA_WIDTH			(DATA_WIDTH),
				  .HADDR_WIDTH			(HADDR_WIDTH))
	dp1 (
		.clk				(clk1x),

		/* Host-side port 0.  */
		.rst0				(rst0),
		.rd0				(rd0),
		.wr0				(wr0),
		.earlyOpBegun0	(earlyOpBegun0),
		.opBegun0		(opBegun0),
		.rdPending0		(rdPending0),
		.done0			(done0),
		.rdDone0			(rdDone0),
		.hAddr0			(hAddr0),
		.hDIn0			(hDIn0),
		.hDOut0			(hDOut0),
		.status0			(status0),

		/* Host-side port 1.  */
		.rst1				(rst1),
		.rd1				(rd1),
		.wr1				(wr1),
		.earlyOpBegun1	(earlyOpBegun1),
		.opBegun1		(opBegun1),
		.rdPending1		(rdPending1),
		.done1			(done1),
		.rdDone1			(rdDone1),
		.hAddr1			(hAddr1),
		.hDIn1			(hDIn1),
		.hDOut1			(hDOut1),
		.status1			(status1),

		/* SDRAM controller port.  */
		.rst				(sdram_rst),
		.rd				(sdram_rd),
		.wr				(sdram_wr),
		.earlyOpBegun	(sdram_earlyopbegun),
		.opBegun			(sdram_opbegun),
		.rdPending		(sdram_rdpending),
		.done				(sdram_done),
		.rdDone			(sdram_rddone),
		.hAddr			(sdram_haddr),
		.hDIn				(sdram_hdin),
		.hDOut			(sdram_hdout),
		.status			(sdram_status)
	);
	`else
	assign sdram_rst = rst0;
	assign sdram_rd = rd0;
	assign sdram_wr = wr0;
	assign earlyOpBegun0 = sdram_earlyopbegun;
	assign opBegun0 = sdram_opbegun;
	assign rdPending0 = sdram_rdpending;
	assign done0 = sdram_done;
	assign rdDone0 = sdram_rddone;
	assign sdram_haddr = hAddr0;
	assign sdram_hdin = hDIn0;
	assign hDOut0 = sdram_hdout;
	assign status0 = sdram_status;

	assign earlyOpBegun1 = 0;
	assign opBegun1 = 0;
	assign rdPending1 = 0;
	assign done1 = 0;
	assign rdDone1 = 0;
	assign hDOut1 = 0;
	assign status1 = 0;
	`endif
endmodule
