`include "config.v"

module addrdecode(
		address,
		emulmode,
		ram_cs,
		tube_cs,
		rom_cs,
		char_cs,
		lcd_cs,
		hwmult_cs
	);

	input [23:0] address;
	input emulmode;
	output ram_cs;
	output tube_cs;
	output rom_cs;
	output char_cs;
	output lcd_cs;
	output hwmult_cs;

	reg [2:0] chip_select;
	`define SEL_RAM		0
	`define SEL_TUBE		1
	
	/* Access SDRAM not flash if TEST is defined.  */
	`ifdef TEST
	`define SEL_ROM		`SEL_RAM
	`else
	`define SEL_ROM		2
	`endif
	
	`define SEL_CHAR		3
	`define SEL_LCD		4
	`define SEL_HWMULT	5

	assign ram_cs = chip_select == `SEL_RAM;
	assign tube_cs = chip_select == `SEL_TUBE;
	assign rom_cs = chip_select == `SEL_ROM;
	assign char_cs = chip_select == `SEL_CHAR;
	assign lcd_cs = chip_select == `SEL_LCD;
	assign hwmult_cs = chip_select == `SEL_HWMULT;

	always @(address or emulmode) begin
		if (emulmode) begin
			/* Emulation mode address map.  */
			if ((address & 24'h00f800) != 24'h00f800)
				chip_select = `SEL_RAM;
			else if ((address & 24'h00fff8) == 24'h00fef8)
				chip_select = `SEL_TUBE;
			else if ((address & 24'h00ffff) == 24'h00fef0)
				chip_select = `SEL_CHAR;
			else if ((address & 24'h00fffe) == 24'h00fef2)
				chip_select = `SEL_LCD;
			else
				chip_select = `SEL_ROM;
		end else begin
			/* Native (16-bit) mode address map.  */
			if ((address & 24'hfff800) != 24'h00f800)
				chip_select = `SEL_RAM;
			else if ((address & 24'hfffff8) == 24'h00fef8)
				chip_select = `SEL_TUBE;
			else if ((address & 24'hffffff) == 24'h00fef0)
				chip_select = `SEL_CHAR;
			else if ((address & 24'hfffffe) == 24'h00fef2)
				chip_select = `SEL_LCD;
			else if ((address & 24'hfffff0) == 24'h00fee0)
				chip_select = `SEL_HWMULT;
			else
				chip_select = `SEL_ROM;
		end
	end
endmodule
