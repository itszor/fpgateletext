`timescale 1ns / 1ps

module test();
	
	reg read_clk;
	reg read_en;
	reg write_clk;
	reg write_en;
	reg [7:0] data_in;
	wire [7:0] data_out;
	wire is_empty;
	wire is_full;
	reg reset;
	reg [1:0] limit;
	
	system mysystem(.read_clk(read_clk),
						 .read_en(read_en),
						 .write_clk(write_clk),
						 .write_en(write_en),
						 .data_in(data_in),
						 .data_out(data_out),
						 .reset(reset),
						 .is_full(is_full),
						 .is_empty(is_empty),
						 .limit(limit));

	initial begin
		reset = 1;
		limit = 1;
		read_clk = 0;
		write_clk = 0;
		#2 reset = 0;
		
		#2 data_in = 55;
		#1 write_en = 1;
		#2 write_en = 0;
		
		#2 data_in = 66;
		#1 write_en = 1;
		#2 write_en = 0;

		#2 read_en = 1;
		#2 read_en = 0;
		#2 read_en = 1;
		#2 read_en = 0;
		
		limit = 3;
		
		#2 data_in = 11;
		#1 write_en = 1;
		#2 write_en = 0;
		
		#2 data_in = 22;
		#1 write_en = 1;
		#2 write_en = 0;

		#2 data_in = 77;
		#1 write_en = 1;
		#2 write_en = 0;

		#2 data_in = 88;
		#1 write_en = 1;
		#2 write_en = 0;
		
		#2 read_en = 1;
		#2 read_en = 0;
		#2 read_en = 1;
		#2 read_en = 0;
		#2 read_en = 1;
		#2 read_en = 0;
		#2 read_en = 1;
		#2 read_en = 0;
		
		limit = 0;

		#2 data_in = 99;
		#1 write_en = 1;
		#2 write_en = 0;
		
		#2 read_en = 1;
		#2 read_en = 0;

		#15 $finish;

	end

	always begin
		#2 read_clk <= ~read_clk;
	end
	
	always begin
		#3 write_clk <= ~write_clk;
	end

endmodule
