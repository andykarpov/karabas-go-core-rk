`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_loader.v (spec_loader.v of karabas-go-core-specialist)

 What the firmware loads, one master on the aux port of rk_sram. The ROM loader writes at rom_addr.
 An FL item writes by the slot of file_slot (the mcu writes a byte in ten clocks or less often; the
 machine is in reset meanwhile):
   slot 1  a tape file (.rk, .rkr, .gam, .rkm, .rka, ...) into the main RAM
   slot 2  the ROM disk of the Apogey (up to 512 KB) at 200000

 A tape file of the RK family, as Emu80 RkFileLoader reads it: an optional E6, the start and end
 addresses (HIGH byte first), the bytes from start to end, a checksum (ignored). At the end of the
 file rk_ok tells that all the bytes came, rk_start is the start address.
*/

module rk_loader (
	input wire clk,

	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	output reg [15:0] rk_start = 16'd0,
	output reg rk_ok = 1'b0,

	output reg aux_req = 1'b0,
	output reg [21:0] aux_addr = 22'd0,
	output reg [7:0] aux_din = 8'd0,
	input wire aux_ack
);

reg pend = 1'b0;
reg [21:0] pend_addr = 22'd0;
reg [7:0] pend_data = 8'd0;

localparam R_FIRST = 3'd0, R_S1 = 3'd1, R_E0 = 3'd2, R_E1 = 3'd3, R_DATA = 3'd4, R_END = 3'd5;
reg [2:0] rs = R_FIRST;
reg [15:0] cur = 16'd0;
reg [15:0] last = 16'd0;

always @(posedge clk) begin
	if (rom_wr) begin
		pend <= 1'b1;
		pend_addr <= rom_addr;
		pend_data <= rom_data;
	end
	else if (file_wr && file_slot == 8'd2) begin
		pend <= 1'b1;
		pend_addr <= 22'h200000 | { 3'd0, file_addr[18:0] };
		pend_data <= file_data;
	end
	else if (file_wr && file_slot == 8'd1) begin
		if (file_addr == 32'd0)
			rk_ok <= 1'b0;
		case (file_addr == 32'd0 ? R_FIRST : rs)
			R_FIRST:
				if (file_data == 8'hE6 && file_addr == 32'd0)
					rs <= R_FIRST;
				else begin
					rk_start[15:8] <= file_data;
					rs <= R_S1;
				end
			R_S1: begin
				rk_start[7:0] <= file_data;
				rs <= R_E0;
			end
			R_E0: begin
				last[15:8] <= file_data;
				rs <= R_E1;
			end
			R_E1: begin
				last[7:0] <= file_data;
				cur <= rk_start;
				rs <= R_DATA;
			end
			R_DATA: begin
				pend <= 1'b1;
				pend_addr <= { 6'd0, cur };
				pend_data <= file_data;
				cur <= cur + 16'd1;
				if (cur == last) begin
					rk_ok <= 1'b1;
					rs <= R_END;
				end
			end
			default: ;
		endcase
	end

	if (aux_ack)
		aux_req <= 1'b0;
	else if (!aux_req && pend) begin
		aux_req <= 1'b1;
		aux_addr <= pend_addr;
		aux_din <= pend_data;
		if (!rom_wr && !file_wr)
			pend <= 1'b0;
	end
end

endmodule
