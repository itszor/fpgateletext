`timescale 1ns / 1ps

/* Defining TEST does two things at present: SDRAM is accessed instead of
   flash if ROM access is done (so program can be uploaded to SDRAM before
	starting the CPU), and the seven-segment display is mapped to 0xfef0.  */
`define TEST 1

/* If GOSLOW is defined, run the CPU clock very slowly.  */
//`define GOSLOW 1

//`define TUBE_SUPPORT 1

/* If true, enable combining of pairs of byte writes into SDRAM words.
	Necessary for VGA support.  */
`define ENABLE_COMBINING 1

/* Enable VGA support.  */
`define VGA_SUPPORT 1

/* Enable CPU cache.  */
//`undef ENABLE_CACHE