`include "config.v"

module fifo(read_clk, read_en, write_clk, write_en, reset,
				data_in, data_out, is_full, is_empty, limit);
	
	/* Depth of fifo.  */
	parameter D = 24;
	/* Max. index.  */
	parameter M = D-1;
	/* Number of bytes in FIFO after reset.  */
	parameter RST_CAP = 0;
	/* Number of bits needed for an index (-1).  */
	parameter B = 4;
	
	input read_clk;
	input write_clk;
	input read_en;
	input write_en;
	input reset;
	input [7:0] data_in;
	output [7:0] data_out;
	reg fifo_is_full;
	reg fifo_is_empty;
	output is_full;
	output is_empty;
	input [B:0] limit;
	
	assign is_full = fifo_is_full;
	assign is_empty = fifo_is_empty;
	
	reg [7:0] buffer [0:M];
	reg [M:0] occupy;
	reg [M:0] shadow;
	reg [B:0] read_ptr;
	reg [B:0] write_ptr;

	assign data_out = buffer[read_ptr];
		
	always @(posedge read_clk or posedge reset)
	begin
		if (reset) begin
			read_ptr = 0;
			shadow = 0;
		end else begin
			if (read_en) begin
				if (read_ptr == limit)
					read_ptr = 0;
				else
					read_ptr = read_ptr + 1;
				shadow[read_ptr] = occupy[read_ptr];
			end
		end
	end

	always @(posedge write_clk or posedge reset)
	begin
		if (reset) begin
			write_ptr = RST_CAP;
			occupy = 0;
		end else begin
			if (write_en) begin
				buffer[write_ptr] = data_in;
				if (write_ptr == limit)
					write_ptr = 0;
				else
					write_ptr = write_ptr + 1;
				occupy[write_ptr] = !shadow[write_ptr];
			end
			/* Update the is_full and is_empty conditions. This may lag slightly;
				it does not update whilst reads are in progress. Hopefully this
				won't break anything.  */
			if (!read_en) begin
				fifo_is_full <= read_ptr == write_ptr
									 && occupy[write_ptr] != shadow[write_ptr];
				fifo_is_empty <= read_ptr == write_ptr
									  && occupy[write_ptr] == shadow[write_ptr];
			end
		end
	end
	
endmodule

