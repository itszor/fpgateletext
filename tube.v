`include "config.v"

module tube(
		host_data_in,
		host_data_out,
		host_addr,
		par_data_in,
		par_data_out,
		par_addr,
		host_ncs,
		host_read,
		host_clk,
		host_nirq,
		host_nrst,
		par_ncs,
		par_read,
		par_clk,
		par_nirq,
		par_nnmi,
		par_nrst
	);

	input [7:0] host_data_in;
	output [7:0] host_data_out;
	input [2:0] host_addr;
	input [7:0] par_data_in;
	output [7:0] par_data_out;
	input [2:0] par_addr;
	
	/* Chip-select, host address valid (active low).  */
	input host_ncs;
	/* Data direction to/from host, high->read.  */
	input host_read;
	/* Host processor clock. High->valid address bus.  */
	input host_clk;
	/* Host IRQ. Interrupt to host processor, active low.  */
	output host_nirq;
	/* Reset from host. Active low.  */
	input host_nrst;
	
	/* Chip-select, parasite address valid (active low).  */
	input par_ncs;
	/* Data direction to/from parasite, high->read.  */
	input par_read;
	/* Parasite clock, high->valid address.  */
	input par_clk;
	/* The tube application note describes these. I'm not sure
	   what clock they activate on (host?). I'm trying a more
		symmetrical FIFO design (but it might be racey!).  */
	/* Parasite write strobe, active low.  */
	/*input par_nwrite;*/
	/* Parasite read strobe, active low.  */
	/*input par_nread;*/
	/* Parasite IRQ, active low.  */
	output par_nirq;
	/* Parasite NMI, active low.  */
	output par_nnmi;
	/* Parasite reset, active low.  */
	output par_nrst;

	/* Status bits.  */
	reg q;  // enable HIRQ from register 4
	reg i;  // enable PIRQ from register 1
	reg j;  // enable PIRQ from register 4
	reg m;  // enable PNMI from register 3
	reg v;  // two byte operation of register 3
	reg p;  // activate PRST
	/*reg t;  // clear all Tube registers
	reg s;*/  // set control flags(s) indicated by mask

	/* Tube (fifo) reset request.  */
	reg tube_reset;

	wire reg3_limit = v;

	/* Host-to-parasite read/write enables.  */
	reg [3:0] h2p_read_en;
	reg [3:0] h2p_write_en;

	/* Register 1, host-to-parasite.  */
	reg [7:0] h2p_1_in;
	wire [7:0] h2p_1_out;
	wire h2p_1_is_full;
	wire h2p_1_is_empty;
	
	fifo #(.D(1), .B(0)) fifo_h2p_1 (
		.read_clk	(par_clk),
		.read_en		(h2p_read_en[0]),
		.write_clk	(host_clk),
		.write_en	(h2p_write_en[0]),
		.reset		(tube_reset),
		.data_in		(h2p_1_in),
		.data_out	(h2p_1_out),
		.is_empty	(h2p_1_is_empty),
		.is_full		(h2p_1_is_full),
		.limit		(0)
	);
	
	/* Register 2, host-to-parasite.  */
	reg [7:0] h2p_2_in;
	wire [7:0] h2p_2_out;
	wire h2p_2_is_full;
	wire h2p_2_is_empty;
	
	fifo #(.D(1), .B(0)) fifo_h2p_2 (
		.read_clk	(par_clk),
		.read_en		(h2p_read_en[1]),
		.write_clk	(host_clk),
		.write_en	(h2p_write_en[1]),
		.reset		(tube_reset),
		.data_in		(h2p_2_in),
		.data_out	(h2p_2_out),
		.is_empty	(h2p_2_is_empty),
		.is_full		(h2p_2_is_full),
		.limit(0)
	);

	/* Register 3, host-to-parasite.  */
	reg [7:0] h2p_3_in;
	wire [7:0] h2p_3_out;
	wire h2p_3_is_full;
	wire h2p_3_is_empty;
	
	fifo #(.D(2), .B(0)) fifo_h2p_3 (
		.read_clk	(par_clk),
		.read_en		(h2p_read_en[2]),
		.write_clk	(host_clk),
		.write_en	(h2p_write_en[2]),
		.reset		(tube_reset),
		.data_in		(h2p_3_in),
		.data_out	(h2p_3_out),
		.is_empty	(h2p_3_is_empty),
		.is_full		(h2p_3_is_full),
		.limit		(reg3_limit)
	);

	/* Register 4, host-to-parasite.  */
	reg [7:0] h2p_4_in;
	wire [7:0] h2p_4_out;
	wire h2p_4_is_full;
	wire h2p_4_is_empty;
	
	fifo #(.D(1), .B(0)) fifo_h2p_4 (
		.read_clk	(par_clk),
		.read_en		(h2p_read_en[3]),
		.write_clk	(host_clk),
		.write_en	(h2p_write_en[3]),
		.reset		(tube_reset),
		.data_in		(h2p_4_in),
		.data_out	(h2p_4_out),
		.is_empty	(h2p_4_is_empty),
		.is_full		(h2p_4_is_full),
		.limit		(0)
	);

	/* Parasite-to-host read/write enables.  */
	reg [3:0] p2h_read_en;
	reg [3:0] p2h_write_en;

	/* Register 1, parasite-to-host.  */
	reg [7:0] p2h_1_in;
	wire [7:0] p2h_1_out;
	wire p2h_1_is_full;
	wire p2h_1_is_empty;
	
	fifo #(.D(24), .B(4)) fifo_p2h_1 (
		.read_clk	(host_clk),
		.read_en		(p2h_read_en[0]),
		.write_clk	(par_clk),
		.write_en	(p2h_write_en[0]),
		.reset		(tube_reset),
		.data_in		(p2h_1_in),
		.data_out	(p2h_1_out),
		.is_empty	(p2h_1_is_empty),
		.is_full		(p2h_1_is_full),
		.limit		(23)
	);

	/* Register 2, parasite-to-host.  */
	reg [7:0] p2h_2_in;
	wire [7:0] p2h_2_out;
	wire p2h_2_is_full;
	wire p2h_2_is_empty;
	
	fifo #(.D(1), .B(0)) fifo_p2h_2 (
		.read_clk	(host_clk),
		.read_en		(p2h_read_en[1]),
		.write_clk	(par_clk),
		.write_en	(p2h_write_en[1]),
		.reset		(tube_reset),
		.data_in		(p2h_2_in),
		.data_out	(p2h_2_out),
		.is_empty	(p2h_2_is_empty),
		.is_full		(p2h_2_is_full),
		.limit		(0)
	);

	/* Register 3, parasite-to-host.  */
	reg [7:0] p2h_3_in;
	wire [7:0] p2h_3_out;
	wire p2h_3_is_full;
	wire p2h_3_is_empty;
	
	/* On reset, this fifo should contain one junk byte.  */
	fifo #(.D(2), .B(0), .RST_CAP(1)) fifo_p2h_3 (
		.read_clk	(host_clk),
		.read_en		(p2h_read_en[2]),
		.write_clk	(par_clk),
		.write_en	(p2h_write_en[2]),
		.reset		(tube_reset),
		.data_in		(p2h_3_in),
		.data_out	(p2h_3_out),
		.is_empty	(p2h_3_is_empty),
		.is_full		(p2h_3_is_full),
		.limit		(reg3_limit)
	);

	/* Register 4, parasite-to-host.  */
	reg [7:0] p2h_4_in;
	wire [7:0] p2h_4_out;
	wire p2h_4_is_full;
	wire p2h_4_is_empty;
	
	fifo #(.D(1), .B(0)) fifo_p2h_4 (
		.read_clk	(host_clk),
		.read_en		(p2h_read_en[3]),
		.write_clk	(par_clk),
		.write_en	(p2h_write_en[3]),
		.reset		(tube_reset),
		.data_in		(p2h_4_in),
		.data_out	(p2h_4_out),
		.is_empty	(p2h_4_is_empty),
		.is_full		(p2h_4_is_full),
		.limit		(0)
	);

	/* Host IRQ trigger.  */
	wire reg4_hirq = q && !p2h_4_is_empty;

	/* Parasite IRQ/NMI trigger.  */
	wire reg1_pirq = i && !h2p_1_is_empty;
	wire reg4_pirq = j && !h2p_4_is_empty;
	wire reg3_pnmi_p2h = m && h2p_3_is_empty;
	wire reg3_pnmi_h2p = m && p2h_3_is_full;

	assign par_nirq = !(reg1_pirq || reg4_pirq);
	assign par_nnmi = !(reg3_pnmi_p2h || reg3_pnmi_h2p);
	assign host_nirq = !reg4_hirq;

	/* Parasite reset, active low.  */
	assign par_nrst = !p;
	
	/* HOST OPERATIONS.  */
	
	reg [7:0] host_outbuf;
	assign host_data_out = (p2h_read_en[0]) ? p2h_1_out
								: (p2h_read_en[1]) ? p2h_2_out
								: (p2h_read_en[2]) ? p2h_3_out
								: (p2h_read_en[3]) ? p2h_4_out
								: host_outbuf;
	
	always @(posedge host_clk)
	begin
		if (host_nrst == 0) begin
			{ p, v, m, j, i, q } <= 6'b0;
			tube_reset <= 1;
		end else if (tube_reset == 1)
			tube_reset <= 0;
		else begin
			if (p2h_read_en)
				p2h_read_en <= 0;
			else if (h2p_write_en)
				h2p_write_en <= 0;
			else if (host_ncs==0) begin
				if (host_read) begin
					case (host_addr)
					0: host_outbuf <=
							{ !p2h_1_is_empty, !p2h_1_is_full,
							  p, v, m, j, i, q };
					
					1: p2h_read_en <= 4'b0001;
					
					2: host_outbuf <=
							{ !p2h_2_is_empty, !p2h_2_is_full, 6'b0 };
					
					3: p2h_read_en <= 4'b0010;
					
					4: host_outbuf <=
							{ !p2h_3_is_empty, !p2h_3_is_full, 6'b0 };
					
					5: p2h_read_en <= 4'b0100;
					
					6: host_outbuf <=
							{ !p2h_4_is_empty, !p2h_4_is_full, 6'b0 };
					
					7: p2h_read_en <= 4'b1000;
					endcase
				end  /* Host read.  */
				else begin
					case (host_addr)
					0: begin
						if (host_data_in[6] == 1) begin
							/* Reset Tube registers/fifos.  */
							tube_reset <= 1;
						end
						if (host_data_in[7] == 1)
							{p, v, m, j, i, q} <=
								{p, v, m, j, i, q} | host_data_in[5:0];
						else
							{p, v, m, j, i, q} <=
								{p, v, m, j, i, q} &~ host_data_in[5:0];
					end

					1: begin
						h2p_1_in <= host_data_in;
						h2p_write_en <= 4'b0001;
					end

					3: begin
						h2p_2_in <= host_data_in;
						h2p_write_en <= 4'b0010;
					end
					
					5: begin
						h2p_3_in <= host_data_in;
						h2p_write_en <= 4'b0100;
					end
					
					7: begin
						h2p_4_in <= host_data_in;
						h2p_write_en <= 4'b1000;
					end
					
					endcase
				end  /* Host write.  */
			end  /* Host chip select.  */
		end  /* Not reset.  */
	end  /* Always.  */

	/* PARASITE OPERATIONS.  */
	
	reg [1:0] par_outbuf;
	assign par_data_out = h2p_read_en[0] ? h2p_1_out
							  : h2p_read_en[1] ? h2p_2_out
							  : h2p_read_en[2] ? h2p_3_out
							  : h2p_read_en[3] ? h2p_4_out
							  : { par_outbuf, 6'b0 };
	
	always @(posedge par_clk)
	begin
		if (h2p_read_en)
			h2p_read_en <= 0;
		else if (p2h_write_en)
			p2h_write_en <= 0;
		else if (par_ncs==0) begin
			if (par_read) begin
				case (par_addr)
				0: par_outbuf <= { !h2p_1_is_empty, !h2p_1_is_full };
				
				1: h2p_read_en <= 4'b0001;
				
				2: par_outbuf <= { !h2p_2_is_empty, !h2p_2_is_full };
				
				3: h2p_read_en <= 4'b0010;
				
				4: par_outbuf <= { !h2p_3_is_empty, !h2p_3_is_full };
				
				5: h2p_read_en <= 4'b0100;
				
				6: par_outbuf <= { !h2p_4_is_empty, !h2p_4_is_full };
				
				7: h2p_read_en <= 4'b1000;
				endcase
			end  /* Parasite read.  */
			else begin
				case (par_addr)
				1: begin
					p2h_1_in <= par_data_in;
					p2h_write_en <= 4'b0001;
				end
				
				3: begin
					p2h_2_in <= par_data_in;
					p2h_write_en <= 4'b0010;
				end
				
				5: begin
					p2h_3_in <= par_data_in;
					p2h_write_en <= 4'b0100;
				end
				
				7: begin
					p2h_4_in <= par_data_in;
					p2h_write_en <= 4'b1000;
				end
				endcase
			end  /* Parasite read.  */
		end  /* Parasite chip select.  */
	end  /* Always.  */

endmodule
