`include "config.v"

/* Burst-capable SDRAM controller. No pipelining so far!
	
	Use 8-word bursts (with 16 bit words) to fill or spill 16 bytes of cache line in one go.
*/

module sdramburst #(parameter HADDR_WIDTH=24,
										DATA_WIDTH=16,
										SADDR_WIDTH=13) (
		/* Host side.  */
		input clk,
		output lock,
		output clk1x,
		output clkdv,
		output cpu_clk,
		output held_in_reset,
		input rst,
		input [HADDR_WIDTH-1:0] hAddr,
		input [DATA_WIDTH-1:0] hDIn,
		output [DATA_WIDTH-1:0] hDOut,
		input rd,
		input wr,
		output reg ready,
		output reg [2:0] burst_offset,
		output reg collision,
		
		/* VGA access (read only!).  */
		input [HADDR_WIDTH-1:0] vgaAddr,
		input vga_rd,
		output reg vga_ready,
		
		/* SDRAM side.  */
		output sdram_clk,		/* Clock to SDRAM.  */
		input sdram_clkfb,	/* Clock feedback from PCB (SDRAM).  */
		output reg cke,
		output ce_n,
		output ras_n,
		output cas_n,
		output we_n,
		output [1:0] ba,
		output [SADDR_WIDTH-1:0] sAddr,
		output [DATA_WIDTH-1:0] sDIn,
		input [DATA_WIDTH-1:0] sDOut,
		output reg sDOutEn,
		output dqmh,
		output dqml,
		
		/* Internal state */
		output [4:0] o_state,
		output reg read_requested,
		output reg write_requested
	);

	/* Commands are defined by:
		nCS nRAS nCAS nWE BA{1,0} A10 A{12,11,9-0}
	*/

	`define inhibit				19'b1000000000000000000
	`define nop						19'b0111000000000000000
	`define burst_terminate		19'b0110000000000000000
	`define auto_refresh			19'b0001000000000000000

	/* Mode register bits from http://en.wikipedia.org/wiki/SDRAM.  */
	/* Bits M2 M1 M0.  8 word burst.  */
	`define BURST_LEN				3'b011
	/* Bit M3: 0 = sequential burst ordering.  */
	`define BURST_TYPE			1'b0
	/* Bits M6 M5 M4: CAS latency.  011 (CL3).  */
	`define CAS_LATENCY			3'b011
	/* Bits M8 M7: Operating mode, reserved (00).  */
	`define OPERATING_MODE		2'b00
	/* Bit M9: 0 = use burst mode.  */
	`define BURST_MODE			1'b0
		
	`define load_mode_reg		{9'b000000000,\
										 `BURST_MODE, `OPERATING_MODE, `CAS_LATENCY,\
										 `BURST_TYPE, `BURST_LEN}

	`define precharge_all		19'b0010001000000000000

	function [18:0] read;
	input [1:0] bank;
	input [8:0] column;
	begin
		read = {4'b0101, bank, 1'b0, 3'b000, column};
	end
	endfunction
	
	function [18:0] read_precharge;
	input [1:0] bank;
	input [8:0] column;
	begin
		read_precharge = {4'b0101, bank, 1'b1, 3'b000, column};
	end
	endfunction

	function [18:0] write;
	input [1:0] bank;
	input [8:0] column;
	begin
		write = {4'b0100, bank, 1'b0, 3'b000, column};
	end
	endfunction
	
	function [18:0] write_precharge;
	input [1:0] bank;
	input [8:0] column;
	begin
		write_precharge = {4'b0100, bank, 1'b1, 3'b000, column};
	end
	endfunction

	function [18:0] activate;
	input [1:0] bank;
	input [12:0] row;
	begin
		activate = {4'b0011, bank, row[10], row[12:11], row[9:0]};
	end
	endfunction
	
	function [18:0] precharge;
	input [1:0] bank;
	begin
		precharge = {4'b0010, bank, 1'b0, 12'b0};
	end
	endfunction
	
	/* DLLs to handle internal and external clock skew. -- see xapp174.pdf,
	   figure 10.  */
		
	wire clk_b;
	
	/* Buffer for system clock.  */
	IBUFG sysclk_pad (
		.I (clk),
		.O (clk_b)
	);
	
	wire sdram_clkfb_b;
	
	/* Buffer for SDRAM clock feedback.  */
	IBUFG sdramclk_fb_pad (
		.I (sdram_clkfb),
		.O (sdram_clkfb_b)
	);
	
	wire extdll_locked;
	wire sdram_clk_dll;
	
	wire dllext_rst;
	
	assign held_in_reset = dllext_rst;
	
	/* Buffer for SDRAM (output) clock.  */
	OBUF sdram_clkbuf_dll (
		.I (sdram_clk_dll),
		.O (sdram_clk)
	);
	
	wire int_clk0, int_clk0_b;
	
	BUFG intclk_buf (
		.I (int_clk0),
		.O (int_clk0_b)
	);

	/*wire cpu_clk0, cpu_clk0_b;

	BUFG cpuclk_buf (
		.I (cpu_clk0),
		.O (cpu_clk0_b)
	);*/

	wire int_clkdv, int_clkdv_b;
	
	BUFG intclk_dv_buf (
		.I (int_clkdv),
		.O (int_clkdv_b)
	);
	
	/*wire cpu_clkdv, cpu_clkdv_b;
	
	BUFG cpuclk_dv_buf (
		.I (cpu_clkdv),
		.O (cpu_clkdv_b)
	);*/
	
	wire intdll_locked;
	
	/* "Internal" DLL (for driving FPGA logic), and for providing a slower
		clock for the CPU.  */
	CLKDLL #(
		.CLKDV_DIVIDE	(1.5)
	) clk_intdll (
		.CLKIN			(clk_b),
		.CLKFB			(int_clk0_b),
		.CLK0				(int_clk0),
		.CLKDV			(int_clkdv),
		.LOCKED			(intdll_locked),
		.RST				(0)
	);

	/*wire cpudll_locked;

	CLKDLL #(
		.CLKDV_DIVIDE	(5.0)
	) clk_cpudll (
		.CLKIN			(clk_b),
		.CLKFB			(cpu_clk0_b),
		.CLK0				(cpu_clk0),
		.CLKDV			(cpu_clkdv),
		.LOCKED			(cpudll_locked),
		.RST				(0)
	);*/

	//assign cpu_clk = cpu_clkdv_b;
	assign cpu_clk = int_clk0_b;

	/* "External" DLL.  */
	CLKDLL #(
		.CLKDV_DIVIDE	(2.0)
	) clk_extdll (
		.CLKIN			(clk_b),
		.CLKFB			(sdram_clkfb_b),	/* Buffered feedback from PCB.  */
		.CLK0				(sdram_clk_dll),
		.LOCKED			(extdll_locked),
		.RST				(0)
	);
	
	assign clk1x = int_clk0_b;
	assign clkdv = int_clkdv_b;
	assign lock = extdll_locked && intdll_locked /*&& cpudll_locked*/;
	assign dqml = 0;
	assign dqmh = 0;

	wire dllext_rst_n;

	/* Keep external DLL in reset until internal DLL has stabilised.  May
		be unnecessary.  */
	SRL16 #(
		.INIT		(16'h0000)
	) srl16 (
		.CLK		(clk_b),
		.A0		(1),
		.A1		(1),
		.A2		(1),
		.A3		(1),
		.D			(int_lock),
		.Q			(dllext_rst_n)
	);

	assign dllext_rst = !dllext_rst_n;

	reg [4:0] state;
	reg [4:0] next_state;
	reg [18:0] command;

   assign o_state = state;
	
	assign ce_n = command[18];
	assign ras_n = command[17];
	assign cas_n = command[16];
	assign we_n = command[15];
	assign ba = command[14:13];
	assign sAddr[10] = command[12];
	assign sAddr[12:11] = command[11:10];
	assign sAddr[9:0] = command[9:0];
	
	reg [9:0] delay;
	reg [10:0] refreshctr;
	
	reg [HADDR_WIDTH-1:0] address_b;
	reg [HADDR_WIDTH-1:0] vga_address_b;
	
	`define POWERON									0
	`define PRECHARGE									1
	`define PRECHARGE_WAIT							2
	`define AUTO_REFRESH_1							3
	`define AUTO_REFRESH_1_WAIT					4
	`define AUTO_REFRESH_2							5
	`define AUTO_REFRESH_2_WAIT					6
	`define SET_MODE									7
	`define SET_MODE_WAIT							8
	`define IDLE										9
	`define POST_PRECHARGE_ALL_TO_AUTOREFRESH	10
	`define AUTO_REFRESH								11
	`define AUTO_REFRESH_WAIT						12
	`define WAIT_FOR_PRECHARGE_ACTIVATE			13
	`define POST_PRECHARGE_TO_ACTIVATE			14
	`define WAIT_FOR_ACTIVATE						15
	`define POST_ACTIVATE							16
	`define DELAY										17
	
	`ifdef ONE_HUNDRED_MHZ
	/* Timings in cycles, for -75 part. (Clock period is 10ns at 100MHz).  */
	`define tRP			3		/* ??ns, was 2...  */
	`define tRFC		7		/* 66ns.  */
	`define tMRD		2		/* clocks.  */
	/* RAS-to-CAS delay.  20ns for -75 part.  */
	`define tRCD		2
	`else
	/* Timings in cycles, for -75 part. (Clock period is 20ns at 50MHz).  */
	`define tRP			1		/* 20ns.  */
	`define tRFC		4		/* 66ns.  */
	`define tMRD		2		/* clocks.  */
	/* RAS-to-CAS delay.  20ns for -75 part.  */
	`define tRCD		1
	`endif
	
	//reg read_requested;
	//reg write_requested;
	
	reg vga_read_requested;
	reg is_vga_access;
	
	assign hDOut = sDOut;
	assign sDIn = hDIn;

	reg [10:0] rampipe_sdouten;
	reg [10:0] rampipe_burstctr;
	reg [10:0] rampipe_inhibit_read;
	reg [10:0] rampipe_inhibit_write;
	
	/* These are bits OR'ed with the above, and control the remainder of a burst once it's
		been initiated.  */
	reg [10:0] rampipe_sdouten_bits;
	reg [10:0] rampipe_burstctr_bits;
	reg [10:0] rampipe_inhibit_read_bits;
	reg [10:0] rampipe_inhibit_write_bits;
	
	reg [12:0] active_row_for_bank[0:3];
	reg [3:0] bank_row_active;
	
	wire [1:0] haddr_bank = { 1'b0, hAddr[23] };
	wire [1:0] addr_b_bank = { 1'b0, address_b[23] };

	always @(posedge int_clk0_b) begin
		if (rst) begin
			state <= `POWERON;
			next_state <= `POWERON;
			delay <= 0;
			refreshctr <= 0;
			cke <= 1;
			read_requested <= 0;
			write_requested <= 0;
			command <= `nop;
			address_b <= 0;
			collision <= 0;
			rampipe_sdouten_bits <= 0;
			rampipe_burstctr_bits <= 0;
			rampipe_inhibit_read_bits <= 0;
			rampipe_inhibit_write_bits <= 0;
			bank_row_active <= 0;
			active_row_for_bank[0] <= 0;
			active_row_for_bank[1] <= 0;
			active_row_for_bank[2] <= 0;
			active_row_for_bank[3] <= 0;
		end else begin
			if (state != `IDLE) begin
				/*if (vga_rd) begin
					vga_read_requested <= 1;
				end*/
				if (rd) begin
					if (read_requested || write_requested)
						collision <= 1;
					read_requested <= 1;
				end
				if (wr) begin
					if (read_requested || write_requested)
						collision <= 1;
					write_requested <= 1;
				end

				rampipe_sdouten_bits <= 0;
				rampipe_burstctr_bits <= 0;
				rampipe_inhibit_read_bits <= 0;
				rampipe_inhibit_write_bits <= 0;
			end
			
			if (rd || wr)
				address_b <= hAddr;

			/*if (vga_rd)
				vga_address_b <= vgaAddr;*/

			case (state)
			`DELAY: begin
				if (delay == 0)
					state <= next_state;
				else
					delay <= delay - 1;
			end

			`POWERON: begin
				command <= `nop;
				/* Should wait for 100uS.  */
				delay <= 1000;
				state <= `DELAY;
				next_state <= `PRECHARGE;
			end
			
			`PRECHARGE: begin
				command <= `precharge_all;
				state <= `PRECHARGE_WAIT;
			end
			
			`PRECHARGE_WAIT: begin
				command <= `nop;
				/* Wait for tRP.  */
				delay <= `tRP - 1;
				state <= `DELAY;
				next_state <= `AUTO_REFRESH_1;
			end
			
			`AUTO_REFRESH_1: begin
				command <= `auto_refresh;
				state <= `AUTO_REFRESH_1_WAIT;
			end
			
			`AUTO_REFRESH_1_WAIT: begin
				command <= `nop;
				/* Wait for tRFC.  */
				delay <= `tRFC - 1;
				state <= `DELAY;
				next_state <= `AUTO_REFRESH_2;
			end

			`AUTO_REFRESH_2: begin
				command <= `auto_refresh;
				state <= `AUTO_REFRESH_2_WAIT;
			end
			
			`AUTO_REFRESH_2_WAIT: begin
				command <= `nop;
				/* Wait for tRFC.  */
				delay <= `tRFC - 1;
				state <= `DELAY;
				next_state <= `SET_MODE;
			end

			`SET_MODE: begin
				command <= `load_mode_reg;
				state <= `SET_MODE_WAIT;
			end
			
			`SET_MODE_WAIT: begin
				command <= `nop;
				delay <= `tMRD - 1;
				state <= `DELAY;
				next_state <= `IDLE;
			end
			
			/* Cycles for a read go:
			   0. (idle) Activate		** bus = activate command
				1. (activate_to_read) delay=tRCD (2)
				2. (delay) delay=1
				3. (delay) delay=0
				4. (read)					** bus = read command
				5. (read_burst_prepare)
				6. (delay) delay=0
				7. (read_burst_prepare_2) (enable sDOutEn)
				8. (read_bursting) (burst_offset=0, data output starts)
				9. (read_bursting) (burst_offset=1)
				10. (read_bursting) (burst_offset=2)
				11. (read_bursting) (burst_offset=3)
				12. (read_bursting) (burst_offset=4)
				13. (read_bursting) (burst_offset=5)
				14. (read_bursting) (burst_offset=6)
				15. (read_bursting) (burst_offset=7, disable sDOutEn)
				16. (delay) delay=tRP (3)
				17. (delay) delay=2
				18. (delay) delay=1
				19. (delay) delay=0
				20. (idle) ready for next command
				
				We could start a new request on the 8th cycle -- to a different
				bank. Or we could not use auto-precharge, and keep rows open for
				multiple reads.
				Maybe different state machines for different banks, with
				arbitration logic?
				On cycle 5, the state could return to idle, and a secondary
				process could take over handling the rest of the burst. Then
				(subject to conditions) new requests can be accepted.
				Precharge should be handled manually: for back-to-back reads
				on a given bank, we know by cycle 12 whether the current read
				will need to finish with a precharge, or another read to the
				same row can proceed. If the second read needs to be on a
				different row, we will need to precharge then activate the new
				row.
				We could issue a precharge if we return to idle state with no
				outstanding read/write requests on a particular bank (maybe after
				a little delay) -- or just when we auto-refresh, when all banks
				need to be precharged anyway.
				
				Cycles for a write (used to) go:
				
				0. (idle) Activate				** bus = activate command
				1. (activate_to_write) delay=rRCD (2)
				2. (delay) delay=1
				3. (delay) delay=0, writing=1, burst_offset=0
				4. (write), burst_offset=1		** bus = write_precharge
				5. (write_burst_continue), burst_offset=2
				6. (write_burst_continue), burst_offset=3
				7. (write_burst_continue), burst_offset=4
				8. (write_burst_continue), burst_offset=5
				9. (write_burst_continue), burst_offset=6
				10. (write_burst_continue), burst_offset=7, delay=tRP (3)
				11. (delay), delay=2
				12. (delay), delay=1
				13. (delay), delay=0
				14. (idle), ready for next command.
			*/
			
			`IDLE: begin
				if (rd || read_requested) begin
					if (rampipe_inhibit_read[0]) begin
						command <= `nop;
						if (rd)
							read_requested <= 1;
						rampipe_sdouten_bits <= 0;
						rampipe_burstctr_bits <= 0;
						rampipe_inhibit_read_bits <= 0;
						rampipe_inhibit_write_bits <= 0;
					end else if (rd) begin
						if (bank_row_active[haddr_bank]
							 && active_row_for_bank[haddr_bank] == hAddr[22:10]) begin
							/* We have a read to the currently-active bank.  */
							command <= read (haddr_bank, hAddr[9:1]);
							rampipe_sdouten_bits			<= 11'b11111111000;
							rampipe_burstctr_bits		<= 11'b11111111000;
							rampipe_inhibit_read_bits	<= 11'b00001111111;
							rampipe_inhibit_write_bits <= 11'b11111111111;
						end else begin
							command <= `nop;
							if (bank_row_active[haddr_bank])
								state <= `WAIT_FOR_PRECHARGE_ACTIVATE;
							else
								state <= `WAIT_FOR_ACTIVATE;
							active_row_for_bank[haddr_bank] <= hAddr[22:10];
							bank_row_active[haddr_bank] <= 1;
							/* Do the actual read when we're back in idle state, but with an
								active row in the bank of the access.  */
							read_requested <= 1;
							rampipe_sdouten_bits 		<= 0;
							rampipe_burstctr_bits 		<= 0;
							rampipe_inhibit_read_bits	<= 0;
							rampipe_inhibit_write_bits	<= 0;
						end
					end else begin /* read_requested.  */
						if (bank_row_active[addr_b_bank]
							 && active_row_for_bank[addr_b_bank] == address_b[22:10]) begin
							/* We had a read request and the row is open: do it.  */
							command <= read (addr_b_bank, address_b[9:1]);
							read_requested <= 0;
							rampipe_sdouten_bits			<= 11'b11111111000;
							rampipe_burstctr_bits		<= 11'b11111111000;
							rampipe_inhibit_read_bits	<= 11'b00001111111;
							rampipe_inhibit_write_bits	<= 11'b11111111111;
						end else begin
							command <= `nop;
							if (bank_row_active[addr_b_bank])
								state <= `WAIT_FOR_PRECHARGE_ACTIVATE;
							else
								state <= `WAIT_FOR_ACTIVATE;
							active_row_for_bank[addr_b_bank] <= address_b[22:10];
							bank_row_active[addr_b_bank] <= 1;
							rampipe_sdouten_bits			<= 0;
							rampipe_burstctr_bits		<= 0;
							rampipe_inhibit_read_bits	<= 0;
							rampipe_inhibit_write_bits	<= 0;
						end /* bank_row_active etc.  */
					end /* read_requested.  */
				end /* rd || read_requested */ else if (0 && (wr || write_requested)) begin
					if (rampipe_inhibit_write[0]) begin
						command <= `nop;
						if (wr)
							write_requested <= 1;
						rampipe_sdouten_bits <= 0;
						rampipe_burstctr_bits <= 0;
						rampipe_inhibit_read_bits <= 0;
						rampipe_inhibit_write_bits <= 0;
					end else if (wr) begin
						if (bank_row_active[haddr_bank]
							 && active_row_for_bank[haddr_bank] == hAddr[22:10]) begin
							command <= `nop;
							rampipe_sdouten_bits			<= 0;
							rampipe_burstctr_bits		<= 11'b00011111111;
							rampipe_inhibit_read_bits	<= 11'b00000001111;
							rampipe_inhibit_write_bits	<= 11'b00011111111;
						end else begin
							command <= `nop;
							if (bank_row_active[haddr_bank])
								state <= `WAIT_FOR_PRECHARGE_ACTIVATE;
							else
								state <= `WAIT_FOR_ACTIVATE;
							active_row_for_bank[haddr_bank] <= hAddr[22:10];
							bank_row_active[haddr_bank] <= 1;
							write_requested <= 1;
							rampipe_sdouten_bits 		<= 0;
							rampipe_burstctr_bits 		<= 0;
							rampipe_inhibit_read_bits	<= 0;
							rampipe_inhibit_write_bits	<= 0;
						end
					end else begin /* write_requested */
						if (bank_row_active[addr_b_bank]
							 && active_row_for_bank[addr_b_bank] == address_b[22:10]) begin
							command <= `nop;
							rampipe_sdouten_bits			<= 0;
							rampipe_burstctr_bits		<= 11'b00011111111;
							rampipe_inhibit_read_bits	<= 11'b00000001111;
							rampipe_inhibit_write_bits	<= 11'b00011111111;
						end else begin
							command <= `nop;
							if (bank_row_active[addr_b_bank])
								state <= `WAIT_FOR_PRECHARGE_ACTIVATE;
							else
								state <= `WAIT_FOR_ACTIVATE;
							active_row_for_bank[addr_b_bank] <= address_b[22:10];
							bank_row_active[addr_b_bank] <= 1;
							rampipe_sdouten_bits			<= 0;
							rampipe_burstctr_bits		<= 0;
							rampipe_inhibit_read_bits	<= 0;
							rampipe_inhibit_write_bits	<= 0;
						end /* bank_row_active etc. */
					end /* write_requested */
				end /* wr || write_requested */ else begin
					if (refreshctr == 1562) begin
						command <= `precharge_all;
						bank_row_active <= 0;
						state <= `POST_PRECHARGE_ALL_TO_AUTOREFRESH;
						refreshctr <= 0;
					end else begin
						command <= `nop;
						refreshctr <= refreshctr + 1;
					end
					rampipe_sdouten_bits 		<= 0;
					rampipe_burstctr_bits 		<= 0;
					rampipe_inhibit_read_bits	<= 0;
					rampipe_inhibit_write_bits	<= 0;
				end
			end
			
			`POST_PRECHARGE_ALL_TO_AUTOREFRESH: begin
				command <= `nop;
				delay <= `tRP;
				state <= `DELAY;
				next_state <= `AUTO_REFRESH;
			end
			
			`AUTO_REFRESH: begin
				command <= `auto_refresh;
				state <= `AUTO_REFRESH_WAIT;
			end
			
			`AUTO_REFRESH_WAIT: begin
				command <= `nop;
				/* Wait for tRFC.  */
				delay <= `tRFC - 1;
				state <= `DELAY;
				next_state <= `IDLE;
			end

			`WAIT_FOR_PRECHARGE_ACTIVATE: begin
				if (rampipe_sdouten || rampipe_inhibit_read || rampipe_inhibit_write)
					/* We need to wait for in-progress accesses to complete before precharging
						the row.  */
					command <= `nop;
				else begin
					command <= precharge (addr_b_bank);
					state <= `POST_PRECHARGE_TO_ACTIVATE;
				end
			end
			
			`POST_PRECHARGE_TO_ACTIVATE: begin
				command <= `nop;
				delay <= `tRP;
				state <= `DELAY;
				next_state <= `WAIT_FOR_ACTIVATE;
			end

			`WAIT_FOR_ACTIVATE: begin
				if (rampipe_sdouten || rampipe_inhibit_read || rampipe_inhibit_write)
					command <= `nop;
				else begin
					command <= activate (addr_b_bank, address_b[9:1]);
					state <= `POST_ACTIVATE;
				end
			end

			`POST_ACTIVATE: begin
				command <= `nop;
				delay <= `tRCD;
				state <= `DELAY;
				next_state <= `IDLE;
			end

			default:
				state <= `POWERON;

			endcase
		end
	end
		
	/* Handle read/write bursts after row activation.
		Do not assign to "command" here at all.  */
	
	always @(posedge int_clk0_b) begin
		if (rst) begin
			rampipe_sdouten <= 0;
			rampipe_burstctr <= 0;
			rampipe_inhibit_read <= 0;
			rampipe_inhibit_write <= 0;
			sDOutEn <= 0;
			burst_offset <= 7;
			ready <= 0;
		end else begin
			sDOutEn <= rampipe_sdouten[0];

			if (rampipe_burstctr[0]) begin
				burst_offset <= burst_offset + 1;
				ready <= 1;
			end else begin
				burst_offset <= 7;
				ready <= 0;
			end
			
			rampipe_sdouten <= (rampipe_sdouten >> 1) | rampipe_sdouten_bits;
			rampipe_burstctr <= (rampipe_burstctr >> 1) | rampipe_burstctr_bits;
			rampipe_inhibit_read <= (rampipe_inhibit_read >> 1) | rampipe_inhibit_read_bits;
			rampipe_inhibit_write <= (rampipe_inhibit_write >> 1) | rampipe_inhibit_write_bits;
		end
	end

endmodule
