`timescale 1ns / 1ps
`default_nettype wire

// rk_system with a model of the SRAM (two lanes of 2M x 8, /OE low, as core-specialist tb_boot), for sim_boot.
module tb_boot (
	input wire clk,
	input wire reset,
	input wire turbo,
	input wire color,
	input wire autorun,
	input wire [2:0] model,
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,
	input wire [7:0] img_mounted,
	input wire [63:0] img_size,
	input wire img_data_wr,
	input wire [8:0] img_data_addr,
	input wire [7:0] img_data,
	input wire img_result_wr,
	input wire [7:0] img_result,
	input wire [15:0] img_sum,
	output wire img_q_wr,
	output wire [23:0] img_q_di,
	input wire img_q_ack,
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	output wire [23:0] rgb,
	output wire hs,
	output wire vs,
	output wire de,
	output wire beep,
	output wire [15:0] audio,
	input wire [21:0] dbg_addr,
	output wire [7:0] dbg_q,
	output wire [15:0] dbg_a,
	output wire dbg_rd
);
assign dbg_a = sys.a;
assign dbg_rd = sys.mem_rd;

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

rk_system sys (
	.clk(clk), .reset(reset), .turbo(turbo), .color(color), .autorun(autorun), .model(model),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr),
	.img_mounted(img_mounted), .img_size(img_size), .img_data_wr(img_data_wr), .img_data_addr(img_data_addr),
	.img_data(img_data), .img_result_wr(img_result_wr), .img_result(img_result), .img_sum(img_sum),
	.img_q_wr(img_q_wr), .img_q_di(img_q_di), .img_q_ack(img_q_ack),
	.kb_scancode(kb_scancode), .kb_scancode_upd(kb_scancode_upd), .joy(13'd0), .tape_in(1'b1),
	.beep(beep), .tape_out(), .audio(audio),
	.rgb(rgb), .hs(hs), .vs(vs), .de(de),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

reg [7:0] lo [0:2097151];
reg [7:0] hi [0:2097151];
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_q = dbg_addr[0] ? hi[dbg_addr[21:1]] : lo[dbg_addr[21:1]];

always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
end

endmodule
