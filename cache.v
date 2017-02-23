`include "config.v"

module cache(
		input clock,
		input reset,
		input [23:0] address,
		input [23:0] raw_address,
		input [7:0] data_in,
		output reg [7:0] data_out,
		input read_en,
		input write_en,
		input read,
		output reg busy,
		input enable,
		input bypass,
		input combine,		/* bypass must be enabled too.  */
		output reg sdram_rd,
		output reg sdram_wr,
		input sdram_earlyopbegun,
		input sdram_opbegun,
		input sdram_rdpending,
		input sdram_done,
		input sdram_rddone,
		output [23:0] sdram_haddr,
		output [15:0] sdram_hdin,
		input [15:0] sdram_hdout,
		output [3:0] cachestate
	);
	
	`define IDLE					0
	`define LOOKUP					1
	`define HIT						2
	`define MISS					3
	`define SPILL					4
	`define RELOAD					5
	`define RELOAD_COMPLETING	6
	`define RELOAD_HIT			7
	`define BYPASS_INITIATED	8
	`define BYPASS_WORKING		9
	
	`define PORT_A		0
	`define PORT_B		1
	
	`define READ		0
	`define WRITE		1
	
	/* These are index bits: LAST_PORT comes from the original hash entry,
		DIRTY_BIT and LINE_VALID come from the looked-up indices.  */
	`define LINE_DIRTY	0
	`define LAST_PORT		1
	`define LINE_VALID	2
	
	reg [3:0] state;
	reg port;

	reg operation;

	reg [7:0] evict_ctr;
	reg evict_port;

	//assign cachestate = state;
	assign cachestate = evict_ctr[3:0];
	
	wire [7:0] hash = address[11:4];
	reg [47:0] hash_entry;
	wire [7:0] idx_a = hash_entry[47:40];
	wire [7:0] idx_b = hash_entry[39:32];
	
	reg [23:0] line_descriptor;
	
	wire [7:0] active_blk = (port == `PORT_A) ? idx_a : idx_b;
	
	wire hash_active_same = (hash == active_blk);
	
	reg [7:0] addra;
	reg [7:0] addrb;
	
	reg wea;
	reg web;
	
	reg [2:0] ena;
	reg [2:0] enb;
	
	reg [47:0] dia;
	reg [47:0] dib;

	wire [47:0] doa;
	wire [47:0] dob;
	
	genvar idx;
	generate
	for (idx = 0; idx < 3; idx = idx + 1)
	begin: cacheidx
		RAMB4_S16_S16 index (
			.DOA		(doa[idx * 16 + 15:idx * 16]),
			.DOB		(dob[idx * 16 + 15:idx * 16]),
			.ADDRA	(addra),
			.ADDRB	(addrb),
			.CLKA		(clock),
			.CLKB		(clock),
			.DIA		(dia[idx * 16 + 15:idx * 16]),
			.DIB		(dib[idx * 16 + 15:idx * 16]),
			.ENA		(ena[idx]),
			.ENB		(enb[idx]),
			.RSTA		(reset),
			.RSTB		(reset),
			.WEA		(wea),
			.WEB		(web)
		);
	end
	endgenerate

/*

States -> ports

						|O|A|  AddrA   |   I/O A    |B|  AddrB   |    I/O B
==================+=+=+==========+============+=+==========+===============
IDLE					| |R|hash      |he          |-|-         |-
LOOKUP				|R|R|he[47:40] |line_desc*  |R|he[39:32] |line_desc*
LOOKUP			  	|W|R|he[47:40] |line_desc*  |R|he[39:32] |line_desc*
HIT					|R|W|hash      |he+lru      |-|-         |-
HIT (actv != H)	|W|W|hash      |he+lru      |W|active_blk|line_desc+dirty
HIT (actv == H)	|W|W|hash      |he+lru+dirty|-|-         |-
MISS					|R|W|hash (i2) |{evict,actv}|-|-         |-
MISS					|W|W|hash (i2) |{evict,actv}|-|-         |-
RELOAD_COMPLETING	|R|-|-         |-           |W|evict{i01}|address+valid
RELOAD_COMPLETING	|W|-|-         |-           |W|evict{i01}|address+valid
SPILL			  		|R|-|-         |-           |-|-         |-
SPILL					|W|-|-         |-           |-|-         |-
RELOAD		  		|R|-|-         |-           |-|-         |-
RELOAD				|W|-|-         |-           |-|-         |-
RELOAD_HIT			|R|-|-			|-				 |-|-			  |-
RELOAD_HIT			|W|-|-			|-				 |-|-			  |-

(*) = conditional on address A or B matching
(iN) = only activate index block N (0,1,2)
{x,y} = {x,y} or {y,x}, depending on LRU bit from hash_entry

*/


	wire [11:0] porta_fulladdr = {idx_a, address[3:0]};
	wire [11:0] portb_fulladdr = {idx_b, address[3:0]};
	wire [11:0] cache_fulladdr = (port == `PORT_A) ? porta_fulladdr : portb_fulladdr;

	wire [8:0] cache_addr = cache_fulladdr[8:0];

	wire [2:0] cache_blockaddr = cache_fulladdr[11:9];

	wire [7:0] block_enable;

	assign block_enable[0] = (cache_blockaddr == 0);
	assign block_enable[1] = (cache_blockaddr == 1);
	assign block_enable[2] = (cache_blockaddr == 2);
	assign block_enable[3] = (cache_blockaddr == 3);
	assign block_enable[4] = (cache_blockaddr == 4);
	assign block_enable[5] = (cache_blockaddr == 5);
	assign block_enable[6] = (cache_blockaddr == 6);
	assign block_enable[7] = (cache_blockaddr == 7);

	reg [7:0] cache_in;
	reg cache_wea;

	reg [11:0] xfer_idx;
	reg xfer_write;
	reg xfer_active;
	reg [7:0] xfer_in;

	wire [7:0] xfer_enable;
	
	assign xfer_enable[0] = (xfer_idx[11:9] == 0);
	assign xfer_enable[1] = (xfer_idx[11:9] == 1);
	assign xfer_enable[2] = (xfer_idx[11:9] == 2);
	assign xfer_enable[3] = (xfer_idx[11:9] == 3);
	assign xfer_enable[4] = (xfer_idx[11:9] == 4);
	assign xfer_enable[5] = (xfer_idx[11:9] == 5);
	assign xfer_enable[6] = (xfer_idx[11:9] == 6);
	assign xfer_enable[7] = (xfer_idx[11:9] == 7);

	wire [63:0] cache_blkout;
	wire [63:0] xfer_blkout;

	/* Use port A for cached reads/writes, and port B to
		spill/refill the cache from SDRAM.  */
	genvar cblk;
	generate
	for (cblk = 0; cblk < 8; cblk = cblk + 1)
	begin: block
		RAMB4_S8_S8 #(
			.INIT_00	(256'h3355779933557799335577993355779933557799335577993355779933557799)
		) cache (
			.DOA		(cache_blkout[cblk * 8 + 7:cblk * 8]),
			.DOB		(xfer_blkout[cblk * 8 + 7:cblk * 8]),
			.ADDRA	(cache_addr),
			.ADDRB	(xfer_idx[8:0]),
			.CLKA		(clock),
			.CLKB		(clock),
			.DIA		(cache_in),
			.DIB		(xfer_in),
			.ENA		(block_enable[cblk]),
			.ENB		(xfer_enable[cblk] && xfer_active),
			.RSTA		(reset),
			.RSTB		(reset),
			.WEA		(cache_wea),
			.WEB		(xfer_write)
		);
	end
	endgenerate

	reg [7:0] cache_out;
	
	always @(cache_blockaddr or cache_blkout) begin
		case (cache_blockaddr)
		0: cache_out = cache_blkout[7:0];
		1: cache_out = cache_blkout[15:8];
		2: cache_out = cache_blkout[23:16];
		3: cache_out = cache_blkout[31:24];
		4: cache_out = cache_blkout[39:32];
		5: cache_out = cache_blkout[47:40];
		6: cache_out = cache_blkout[55:48];
		7: cache_out = cache_blkout[63:56];
		endcase
	end

	reg [7:0] xfer_out;

	always @(xfer_idx[11:9] or xfer_blkout) begin
		case (xfer_idx[11:9])
		0: xfer_out = xfer_blkout[7:0];
		1: xfer_out = xfer_blkout[15:8];
		2: xfer_out = xfer_blkout[23:16];
		3: xfer_out = xfer_blkout[31:24];
		4: xfer_out = xfer_blkout[39:32];
		5: xfer_out = xfer_blkout[47:40];
		6: xfer_out = xfer_blkout[55:48];
		7: xfer_out = xfer_blkout[63:56];
		endcase
	end
	
	reg [15:0] combine_data;
	
	reg [15:0] sdram_hdin_xfer;
	reg [23:0] sdram_haddr_xfer;
	
	wire [15:0] data_in2 = {2{data_in}};
	`ifdef ENABLE_COMBINING
	wire [15:0] sdram_hdin_bypass = combine ? combine_data : data_in2;
	`else
	wire [15:0] sdram_hdin_bypass = data_in2;
	`endif

	assign sdram_hdin = (state == `IDLE
								|| state == `BYPASS_INITIATED
								|| state == `BYPASS_WORKING)
		? sdram_hdin_bypass : sdram_hdin_xfer;

	assign sdram_haddr = (state == `IDLE
								 || state == `BYPASS_INITIATED
								 || state == `BYPASS_WORKING)
		? address : sdram_haddr_xfer;

	always @(posedge clock or posedge reset) begin
		if (reset) begin
			state <= `IDLE;
			sdram_rd <= 0;
			sdram_wr <= 0;
			evict_ctr <= 0;
		end
		else begin
			case (state)
			`IDLE: begin
				if (enable) begin
					if (bypass) begin
						if (read && read_en) begin
							sdram_rd <= 1;
							state <= `BYPASS_INITIATED;
							busy <= 1;
						end
						else if (!read && write_en) begin
							if (combine) begin
								if (raw_address[0] == 0)
									combine_data[7:0] <= data_in;
								else begin
									combine_data[15:8] <= data_in;
									sdram_wr <= 1;
									state <= `BYPASS_INITIATED;
									busy <= 1;
								end
							end
							else begin	/* !combine.  */
								sdram_wr <= 1;
								state <= `BYPASS_INITIATED;
								busy <= 1;
							end
						end
					end
					else begin	/* !bypass.  */
						if (read && read_en)
							operation <= `READ;
						else if (!read && write_en)
							operation <= `WRITE;
						state <= `LOOKUP;
						hash_entry <= doa;
						busy <= 1;
					end
				end	/* enable.  */
			end	/* `IDLE.  */
			
			/* Complete a bypassed SDRAM operation.  */
			`BYPASS_INITIATED: begin
				if (sdram_done) begin
					sdram_rd <= 0;
					sdram_wr <= 0;
					data_out <= sdram_hdout[7:0];
					state <= `IDLE;
					busy <= 0;
				end
				else if (sdram_opbegun) begin
					sdram_rd <= 0;
					sdram_wr <= 0;
					state <= `BYPASS_WORKING;
				end
			end
				
			`BYPASS_WORKING: begin
				if (sdram_done || sdram_rddone) begin
					data_out <= sdram_hdout[7:0];
					state <= `IDLE;
					busy <= 0;
				end
				else if (!sdram_rdpending && !sdram_rd && !sdram_wr
							&& !sdram_earlyopbegun && !sdram_opbegun) begin
					state <= `IDLE;
					busy <= 0;
				end
			end
			
			`LOOKUP: begin
				if (doa[`LINE_VALID] && doa[23:4] == address[23:4]) begin
					port <= `PORT_A;
					state <= `HIT;
					line_descriptor <= doa[23:0];
					if (operation == `WRITE) begin
						cache_wea <= 1;
						cache_in <= data_in;
					end
				end
				else if (dob[`LINE_VALID] && dob[23:4] == address[23:4]) begin
					port <= `PORT_B;
					state <= `HIT;
					line_descriptor <= dob[23:0];
					if (operation == `WRITE) begin
						cache_wea <= 1;
						cache_in <= data_in;
					end
				end
				else begin
					state <= `MISS;
					evict_port <= !hash_entry[`LAST_PORT];
					if (hash_entry[`LAST_PORT] == `PORT_A) begin
						line_descriptor <= dob[23:0];
						if (dob[`LINE_DIRTY] == 1) begin
							xfer_idx <= {idx_b, 4'b0};
							xfer_write <= 0;
							xfer_active <= 1;
						end
					end else begin
						line_descriptor <= doa[23:0];
						if (doa[`LINE_DIRTY] == 1) begin
							xfer_idx <= {idx_a, 4'b0};
							xfer_write <= 0;
							xfer_active <= 1;
						end
					end
					busy <= 1;
				end
			end
			
			`HIT: begin
				if (operation == `READ)
					data_out <= cache_out;
				cache_wea <= 0;	/* Should have done cache write by now.  */
				state <= `IDLE;
				busy <= 0;
			end
			
			`MISS: begin
				/*if (line_descriptor[`LINE_DIRTY] == 1) begin
					state <= `SPILL;
					sdram_hdin_xfer <= {2{xfer_out}};
					sdram_rd <= 0;
					sdram_wr <= 1;
					sdram_haddr_xfer <= {line_descriptor[23:4], 4'b0};
					xfer_idx[3:0] <= xfer_idx[3:0] + 1;
				end else begin*/
					state <= `RELOAD;
					sdram_wr <= 0;
					sdram_rd <= 1;
					sdram_haddr_xfer <= {address[23:4], 4'b0};
					xfer_idx <= {evict_ctr, 4'b0};
					xfer_write <= 0;
				/*end*/
			end
			
			`SPILL: begin
				if (sdram_opbegun) begin
					sdram_hdin_xfer <= {2{xfer_out}};
					sdram_haddr_xfer <= sdram_haddr_xfer + 1;
					if (xfer_idx[3:0] != 15) begin
						xfer_idx[3:0] <= xfer_idx[3:0] + 1;
					end
					else begin
						state <= `RELOAD;
						sdram_wr <= 0;
						sdram_rd <= 1;
						sdram_haddr_xfer <= {address[23:4], 4'b0};
						xfer_idx <= {evict_ctr, 4'b0};
					end
				end
			end
			
			`RELOAD: begin
				if (sdram_opbegun) begin
					if (sdram_haddr_xfer[3:0] == 15)
						sdram_rd <= 0;
					else
						sdram_haddr_xfer <= sdram_haddr_xfer + 1;
				end

				if (xfer_write) begin
					if (xfer_idx[3:0] == 15) begin
						state <= `RELOAD_COMPLETING;
						xfer_write <= 0;
						xfer_active <= 0;
					end else
						xfer_idx[3:0] <= xfer_idx[3:0] + 1;
				end

				if (sdram_rddone) begin
					xfer_in <= sdram_hdout[7:0];
					xfer_write <= 1;
					xfer_active <= 1;
				end else
					xfer_write <= 0;
			end
	
			`RELOAD_COMPLETING: begin
				/* Initiate the write into the cache line now.  */
				if (operation == `WRITE) begin
					cache_wea <= 1;
					cache_in <= data_in;
				end
				state <= `RELOAD_HIT;
				xfer_write <= 0;
				xfer_active <= 0;
			end

			`RELOAD_HIT: begin
				if (operation == `READ)
					data_out <= cache_out;
				cache_wea <= 0;	/* Should have done cache write by now.  */
				evict_ctr <= evict_ctr + 1;
				state <= `IDLE;
				busy <= 0;
			end
			endcase
		end /* !reset.  */
	end

endmodule
