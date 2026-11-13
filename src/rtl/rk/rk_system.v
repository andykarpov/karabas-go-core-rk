`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_system.v

 The Radio-86RK family on one clock of 40 MHz: the processor, the memory map, the ports, the VG75 CRT
 controller with its DMA, the frame buffer, the video output and the SRAM. docs/HARDWARE.md has the maps.
 model: 0 the Radio-86RK, 1 the Mikrosha, 2 the Apogey BK-01, 3 the Partner 01.01, 4 the
 Mikro-80 with its own Monitor, 5 the Mikro-80 with the Monitor of the RK type (Emu80 mikro80rk.conf,
 the ROM disk shell wants it). Change it only during reset.

 The Mikrosha: the keyboard PPI at C000 with ports A and B swapped (rk_kbd mikrosha), the second PPI
 at C800 (PB7 the second font), the VG75 at D000, the 8253 at D800 (channel 2 the sound, gated by PC1
 of the keyboard PPI, its GATE is PC2), the Monitor at F800. The Apogey: RAM to EBFF, the 8253 at EC00
 (the three channels the sound), the keyboard PPI at ED00 (as the RK86), the PPI of the ROM disk at
 EE00, the VG75 at EF00, the ROM of 4 KB at F000 (writes there go to the DMA); its font set is INTE,
 its colour the attributes of the VG75. The ROM disk (Emu80 ApogeyRomDisk, Apogee_MiSTer EXTROM):
 port A reads byte { bank, PC[6:0], PB } of the disk, the bank is PB[3:0] at the rising edge of PC7.
 The 8253 is KF8253 (kitune-san, MIT) on 1.78 MHz (the Partner 2 MHz), not on turbo.

 The Mikro-80 (Emu80 mikro80.inc): 2 MHz, no VG75 and no DMA. RAM to F7FF, the screen at E000-EFFF
 (rk_m80video draws it into the frame buffer from a copy in block RAM), the Monitor at F800. Its devices
 are I/O ports (IN / OUT; the RK models keep taking those cycles as memory at { n, n }, as the real
 ones): 01 the tape (D0 out and in, the only sound), 04-07 the keyboard PPI with its address inverted
 (07 is port A), 40-4F the page of the RAM disk (the first 0 bit of the byte: page 1..8, FF the main
 memory), A0-A3 the PPI of the ROM disk (port A reads byte { PC, PB }). The RAM disk (Emu80
 Ut88AddrSpaceMapper) takes the cycles of the stack (D2 of the status): 8 pages of 64 KB.

 The Partner 01.01 (Emu80 partner.conf, Partner.cpp): 2 MHz, the VG75 at 1.5 MHz (points at 9 MHz).
 Its map is one of 16, chosen by a write to the slot + 200 (D7..4), read from the PROM D14: for each
 2 KB of the address a block 0..8 (the number of the low 1 bits of its byte; 5 with D6 = 0 is 6):
 0 the ROM window of the module, 2 its RAM window, 3 ROM 2, 4 ROM 1 (8 KB each), 5 RAM 1, 6 RAM 2
 (32 KB each), 7 the slot, else nothing (FF). The DMA goes through the same map. The slot (2 KB): +000
 the VG75, +100 the keyboard PPI, +200 the map, +300 the VT57, +400 / +500 the devices of the module,
 +600 the module (the first 0 bit of D3..0: 0 the SD card, 1 the floppy, 2 the colour module MCPG).
 The MCPG (Emu80 PartnerMcpgRenderer): its ROM in the ROM window, its RAM (4 KB, also copied in block
 RAM for the picture) in the RAM window, at +400 its switch (D7 = 0 shows its picture), at +500 an 8253
 (A3..2, three channels of sound). Its picture covers the text: 4 points a character of 3-bit colours
 from the RAM at { RVV, code, line } (the points 1, 0 in D2..0, D5..3; 3, 2 at + 800), the bits
 inverted (0 lights R, G, B); 7, or a blanked place, is the background of the field attribute
 (GPA0 R, GPA1 G, HGLT B); with GPA0 = GPA1 = 1, HGLT = 0 the text shows through.
 Its font is one of 8 sets of 1 KB, picked by GPA0, GPA1, HGLT of the field attribute; the beeper is
 bit 2 of the line counter of the VG75 at the end of HRTC, on while PC1 is 0; VRTC asks the interrupt
 RST 6. Port C of its keyboard PPI: PC4 RUS/LAT, PC5 SS, PC6 US, PC7 the tape input.

 The VG75 (k580vg75) and the VT57 (k580vt57) come from Apogee_MiSTer and run at the native timing: the
 points at 8 MHz (40 / 5), the DMA on the F2 enable of the CPU, which it holds (HOLD / HLDA) while it reads
 the character rows. The DMA reads the SRAM at its address: the VT57 puts the address out at least a
 state (22 clocks) before DACK, and the SRAM answers within nine, so no wait is needed.

 The frame buffer: the points of the VG75 (point, highlight, the two colour bits of the Apogey: 4 bits)
 in a window of 512 x 300 from the first active point of the first active line (the hblank / vblank of
 the VG75; the retraces inside the window are written black), two points a byte (the first in the low nibble), 256 bytes a line, in the SRAM at FB_BASE.
 rk_video reads it as 16-bit words of four points.

 SRAM (a byte address of 22 bits, rk_sram):
   000000  the main RAM, 64 KB
   100000  the Monitor of the RK86 (2 KB, F800-FFFF)
   100800  the Monitor of the Mikrosha (2 KB, F800-FFFF)
   101000  the ROM of the Apogey (4 KB, F000-FFFF)
   102000  the Monitor of the Mikro-80 (2 KB, F800-FFFF)
   102800  the Monitor of the RK type of the Mikro-80
   104000  the Partner: ROM 1 (8 KB), 106000 ROM 2, 108000 / 108800 / 109000 the ROMs of its SD card,
           floppy and MCPG modules (2 KB each), 10A000 the PROM D14 (512 bytes, kept decoded in rk_system)
   10B000  SDOS of the RK86 (4 KB, read at E000-EFFF), 10C000 the RAM of the MCPG (4 KB)
   200000  the ROM disk (FL slot 2): the Apogey up to 512 KB, the Mikro-80 64 KB
   280000  the RAM disk of the Mikro-80, 8 x 64 KB
   300000  the frame buffer, 512 x 300 x 4 bits
 The fonts (the character generators, 2 KB each: the RK86, the Mikrosha, the Apogey, the Mikro-80; 8 KB
 of the Partner) are a block RAM of 16 KB, written by the ROM loader at 1F0000, 1F0800, 1F1000, 1F1800,
 1F2000, inverted: the fonts of Emu80 have a point as 0. The ROMs arrive by the ROM loader of the mcu; the machine is in reset while they load.

 After reset the Monitor answers every read (its first bytes are a jump to F836), until the first read
 at 8000-FFFF, as the startup flip-flop of Apogee_MiSTer.

 A tape file starts as Emu80 runs it: after the load the machine leaves reset, its Monitor runs for
 2 000 000 ticks of the CPU (3.5 s on the Mikro-80; it sets up the PPI, the VG75 and its variables),
 then the next opcode fetch reads JMP start instead of the memory (autorun; core-specialist does the
 same).
*/

module rk_system #(
	// the MCU link: 1 = v1 (kg_mcu: the img_* stream, img_sdc in here), 2 = v2 (kg_mcu2: its mounter has
	// the sector interface of img_sdc, the sdc_* ports below; img_* unused)
	parameter LINK = 1
) (
	input wire clk,
	input wire reset,
	input wire turbo,
	input wire color,
	input wire autorun,
	input wire [2:0] model,

	// the ROM loader of the mcu
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	// the images of the F items (img_sdc of kg_mcu): slot 3, the SD card of SDOS
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
	// LINK 2: the sector interface of the mounter of kg_mcu2 (img_sdc names)
	input wire [7:0] sdc_img_mounted_i,
	input wire [63:0] sdc_img_size_i,
	output wire [7:0] sdc_rd_o,
	output wire [7:0] sdc_wr_o,
	output wire [31:0] sdc_sector_o,
	input wire sdc_busy_i,
	input wire sdc_done_i,
	input wire sdc_error_i,
	input wire [2:0] sdc_slot_i,
	input wire sdc_byte_in_strobe_i,
	input wire [8:0] sdc_byte_addr_i,
	input wire [7:0] sdc_byte_in_data_i,
	output wire [7:0] sdc_byte_out_data_o,

	// the keyboard (rk_kbd on the keyboard PPI at 8000)
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	input wire [12:0] joy,
	input wire tape_in,           // PC4

	output wire beep,             // INTE of the CPU (the RK86)
	output wire tape_out,         // PC0
	output wire [15:0] audio,     // the beep, the 8253 and the tape output

	// 800 x 600 at 60 Hz (rk_video)
	output wire [23:0] rgb,
	output wire hs,
	output wire vs,
	output wire de,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

localparam [21:0] FB_BASE = 22'h300000;

wire run_reset = reset | rom_active | file_active;

// ------------------------------------------------------------------ the CPU
wire [15:0] a;
wire [7:0] cpu_do;
reg [7:0] cpu_di;
wire mem_rd, mem_wr, fetch, inte, ce_f2, io, stack;
wire sram_we;
wire hrq, hlda;

wire m_mk = model == 3'd1;
wire m_ap = model == 3'd2;
wire m_80 = model == 3'd4 || model == 3'd5;
wire m_pt = model == 3'd3;
wire m_rk = !m_mk && !m_ap && !m_80 && !m_pt;
wire pt_int, inta;

rk_cpu cpu (
	.clk(clk),
	.reset(run_reset),
	.fast(m_80 | m_pt),
	.turbo(turbo),
	.hold(hrq),
	.hlda(hlda),
	.ready(1'b1),
	.addr(a),
	.dout(cpu_do),
	.din(cpu_di),
	.mem_rd(mem_rd),
	.mem_wr(mem_wr),
	.fetch(fetch),
	.io(io),
	.stack(stack),
	.intr(pt_int),
	.inta(inta),
	.inte(inte),
	.ce_f2(ce_f2)
);

reg tape01 = 1'b0;            // the tape register of the Mikro-80 (port 01)
reg pt_beep = 1'b0;           // the beeper of the Partner (bit 2 of the line counter of the VG75)
wire [7:0] ppi1_pc;
assign beep = m_rk & inte | m_80 & tape01 | m_pt & pt_beep & !ppi1_pc[1];

reg wr_d = 1'b0;
always @(posedge clk)
	wr_d <= mem_wr;
wire wr_p = mem_wr & ~wr_d;

// the Monitor everywhere after reset
reg startup = 1'b1;
always @(posedge clk)
	if (run_reset)
		startup <= !m_pt;            // the Partner has its ROM at 0000 in map 0
	else if (mem_rd && a[15])
		startup <= 1'b0;

// ------------------------------------------------------------------ the map of the Partner
// D14 decoded at its load: the block of each 2 KB of each map
reg [3:0] d14 [0:511];
always @(posedge clk)
	if (rom_wr && rom_addr[21:9] == 13'h0850)     // 10A000-10A1FF
		d14[rom_addr[8:0]] <= !rom_data[0] ? 4'd0 : !rom_data[1] ? 4'd1 : !rom_data[2] ? 4'd2 :
		                      !rom_data[3] ? 4'd3 : !rom_data[4] ? 4'd4 :
		                      !rom_data[5] ? (rom_data[6] ? 4'd5 : 4'd6) : !rom_data[6] ? 4'd6 :
		                      !rom_data[7] ? 4'd7 : 4'd8;
reg [3:0] pmap = 4'd0;        // the map
reg mc_en = 1'b0;             // the picture of the MCPG is on
reg [2:0] pmod = 3'd0;        // the module: 0 SD card, 1 floppy, 2 MCPG, 4 none
reg [3:0] pblk = 4'd8, pblk_dma = 4'd8;
wire [15:0] dma_addr;
always @(posedge clk) begin
	pblk <= d14[{ pmap, a[15:11] }];
	pblk_dma <= d14[{ pmap, dma_addr[15:11] }];
end
// the SRAM address of a block (the ROMs, the RAMs), and its kind
function [21:0] pt_sram;
	input [3:0] blk;
	input [15:0] ad;
	case (blk)
		4'd0: pt_sram = 22'h108000 | { 9'd0, pmod[1:0], ad[10:0] };
		4'd2: pt_sram = 22'h10C000 | { 10'd0, ad[11:0] };   // the RAM of the MCPG
		4'd3: pt_sram = 22'h106000 | { 9'd0, ad[12:0] };
		4'd4: pt_sram = 22'h104000 | { 9'd0, ad[12:0] };
		default: pt_sram = { 6'd0, blk == 4'd6, ad[14:0] };   // RAM 1, RAM 2
	endcase
endfunction
wire pt_rom = m_pt && (pblk == 4'd3 || pblk == 4'd4 || (pblk == 4'd0 && pmod < 3'd3));
wire pt_mcram = m_pt && pblk == 4'd2 && pmod == 3'd2;
wire pt_ram = m_pt && (pblk == 4'd5 || pblk == 4'd6) || pt_mcram;
wire pt_slot = m_pt && pblk == 4'd7;
wire [2:0] pt_sub = a[10:8];
wire sel_pmap = pt_slot && pt_sub == 3'd2;
wire sel_pmod = pt_slot && pt_sub[2:1] == 2'b11;
wire pt_dev = pt_slot && pt_sub[2:1] == 2'b10;      // the devices of the module
wire sel_mcsw = pt_dev && !pt_sub[0] && pmod == 3'd2;

// ------------------------------------------------------------------ decoding
wire f800 = a[15:11] == 5'b11111;
wire ap_io = a[15:10] == 6'b111011;               // EC00-EFFF of the Apogey
// the RK86: 8000 PPI 1, A000 PPI 2, C000 VG75, E000-FFFF writes the DMA, F800 the Monitor
// the Mikrosha: C000 PPI 1, C800 PPI 2, D000 VG75, D800 8253, F800 the Monitor and the DMA
// the Apogey: EC00 8253, ED00 PPI 1, EE00 PPI 2, EF00 VG75, F000 the ROM and the DMA
// the Mikro-80: ports 01 the tape, 04-07 PPI 1, 40-4F the RAM disk page, A0-A3 PPI 2; memory otherwise
wire m80_io = m_80 && io;
wire m80_mem = m_80 && !io;
reg [3:0] rpage = 4'd0;       // the RAM disk of the Mikro-80: 0 the main memory, 1..8 its pages
wire sel_rpg = m80_mem && stack && rpage != 4'd0;
wire sel_tape = m80_io && a[7:0] == 8'h01;
wire sel_page = m80_io && a[7:4] == 4'h4;
wire sel_ppi1 = m_pt ? pt_slot && pt_sub == 3'd1 : m_80 ? m80_io && a[7:2] == 6'b000001 : m_mk ? a[15:11] == 5'b11000 :
                m_ap ? ap_io && a[9:8] == 2'd1 : a[15:13] == 3'b100;
wire sel_ppi2 = m_pt ? 1'b0 : m_80 ? m80_io && a[7:2] == 6'b101000 : m_mk ? a[15:11] == 5'b11001 :
                m_ap ? ap_io && a[9:8] == 2'd2 : a[15:13] == 3'b101;
// the RK86 with an SD card image (F slot 3): SDOS, the adapter at D000-DFFF, the VG75 at C000-CFFF
reg sd_on = 1'b0;
wire [7:0] sd_do;
wire sel_sd = m_rk && sd_on && a[15:12] == 4'hD;
wire sel_crt = m_pt ? pt_slot && pt_sub == 3'd0 : m_80 ? 1'b0 : m_mk ? a[15:11] == 5'b11010 : m_ap ? ap_io && a[9:8] == 2'd3 :
               a[15:13] == 3'b110 && !sel_sd;
wire sel_pit = m_pt ? pt_dev && pt_sub[0] && pmod == 3'd2 :
               m_mk ? a[15:11] == 5'b11011 : m_ap ? ap_io && a[9:8] == 2'd0 : 1'b0;
wire sel_mon = m_pt ? pt_rom : m_80 ? m80_mem && f800 : m_ap ? a[15:12] == 4'hF : m_rk ? f800 || a[15:12] == 4'hE : f800;
wire sel_dma = m_pt ? pt_slot && pt_sub == 3'd3 : m_80 ? 1'b0 : m_rk ? a[15:13] == 3'b111 : sel_mon;
wire sel_rom = !sel_rpg && (startup || (sel_mon && !mem_wr));
wire sel_ram = m_pt ? pt_ram : m_80 ? m80_mem && !f800 : m_ap ? a[15:12] != 4'hF && !ap_io : !a[15];
wire sel_rdisk = (m_ap || m_80) && sel_ppi2 && a[1:0] == 2'd0;   // port A: the ROM disk

// ------------------------------------------------------------------ the PPIs
wire [7:0] ppi1_do, ppi2_do, ppi1_pa, ppi1_pb, ppi2_pb, ppi2_pc;
wire ppi2_pb_in;

wire [7:0] kb_scan, kb_ret;
wire [3:0] kb_pc_hi, kb_pc_lo;

rk_ppi ppi1 (
	.clk(clk), .reset(run_reset), .a(m_80 ? ~a[1:0] : a[1:0]), .wr(wr_p & sel_ppi1), .din(cpu_do), .dout(ppi1_do),
	.pa_i(m_mk ? kb_ret : 8'hFF), .pb_i(m_mk ? 8'hFF : kb_ret),
	.pc_i(m_pt ? { tape_in, kb_pc_lo[1], kb_pc_lo[2], kb_pc_lo[0], 4'hF } :
	      m_80 ? { 3'b111, tape_in, kb_pc_lo } : { kb_pc_hi[3:1], tape_in, 4'hF }),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(ppi1_pa), .pb_o(ppi1_pb), .pc_o(ppi1_pc)
);
assign kb_scan = m_mk ? ppi1_pb : ppi1_pa;

rk_kbd kbd (
	.clk(clk), .reset(reset), .ms7007(1'b0), .mikrosha(m_mk), .mikro80(m_80),
	.scancode(kb_scancode), .scancode_upd(kb_scancode_upd), .joy(joy),
	.scan(kb_scan), .ret(kb_ret), .pc_hi(kb_pc_hi), .pc_lo(kb_pc_lo)
);
assign tape_out = m_80 ? tape01 : ppi1_pc[0];

// the tape register and the RAM disk page of the Mikro-80, the map and the module of the Partner
always @(posedge clk)
	if (run_reset) begin
		tape01 <= 1'b0;
		rpage <= 4'd0;
		pmap <= 4'd0;
		pmod <= 3'd0;
		mc_en <= 1'b0;
	end
	else if (wr_p && sel_mcsw)
		mc_en <= !cpu_do[7];
	else if (wr_p && sel_pmap)
		pmap <= cpu_do[7:4];
	else if (wr_p && sel_pmod)
		pmod <= !cpu_do[0] ? 3'd0 : !cpu_do[1] ? 3'd1 : !cpu_do[2] ? 3'd2 : !cpu_do[3] ? 3'd3 : 3'd4;
	else if (wr_p && sel_tape)
		tape01 <= cpu_do[0];
	else if (wr_p && sel_page)
		rpage <= cpu_do == 8'hFF ? 4'd0 : !cpu_do[0] ? 4'd1 : !cpu_do[1] ? 4'd2 : !cpu_do[2] ? 4'd3 :
		         !cpu_do[3] ? 4'd4 : !cpu_do[4] ? 4'd5 : !cpu_do[5] ? 4'd6 : !cpu_do[6] ? 4'd7 : 4'd8;

rk_ppi ppi2 (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_ppi2), .din(cpu_do), .dout(ppi2_do),
	.pa_i(8'hFF), .pb_i(8'hFF), .pc_i(8'hFF),
	.pa_in(), .pb_in(ppi2_pb_in), .pcl_in(),
	.pa_o(), .pb_o(ppi2_pb), .pc_o(ppi2_pc)
);

// the ROM disk of the Apogey
reg [3:0] rd_bank = 4'd0;
reg pc7_d = 1'b0;
always @(posedge clk) begin
	pc7_d <= ppi2_pc[7];
	if (run_reset)
		rd_bank <= 4'd0;
	else if (ppi2_pc[7] && !pc7_d)
		rd_bank <= ppi2_pb[3:0];
end
// the Mikro-80: { PC, PB }
wire [18:0] rd_addr = m_80 ? { 3'd0, ppi2_pc, ppi2_pb } : { rd_bank, ppi2_pc[6:0], ppi2_pb };

// the font set: PB7 of PPI 2 of the Mikrosha (0 while the port is an input), INTE of the Apogey
wire charset = m_mk ? !ppi2_pb_in && ppi2_pb[7] : m_ap ? inte : 1'b0;

// ------------------------------------------------------------------ the 8253 and the sound
reg [5:0] pit_acc = 6'd0;      // 40 MHz * 2 / 45 = 1.78 MHz
always @(posedge clk)
	pit_acc <= pit_acc >= 6'd43 ? pit_acc - 6'd43 : pit_acc + 6'd2;
reg [4:0] pit_div = 5'd0;      // the Partner: 2 MHz (40 / 20), the clock of its CPU
always @(posedge clk)
	pit_div <= pit_div == 5'd19 ? 5'd0 : pit_div + 5'd1;
wire pit_clk = m_pt ? pit_div < 5'd10 : pit_acc < 6'd23;
wire [7:0] pit_do;
wire pit_out0, pit_out1, pit_out2;

KF8253 pit (
	.clock(clk),
	.reset(run_reset),
	.chip_select_n(~sel_pit),
	.read_enable_n(~mem_rd),
	.write_enable_n(~mem_wr),
	.address(m_pt ? a[3:2] : a[1:0]),
	.data_bus_in(cpu_do),
	.data_bus_out(pit_do),
	.counter_0_clock(pit_clk),
	.counter_0_gate(1'b1),
	.counter_0_out(pit_out0),
	.counter_1_clock(pit_clk),
	.counter_1_gate(1'b1),
	.counter_1_out(pit_out1),
	.counter_2_clock(pit_clk),
	.counter_2_gate(m_mk ? ppi1_pc[2] : 1'b1),
	.counter_2_out(pit_out2)
);

wire [15:0] v0 = pit_out0 ? 16'h1000 : 16'h0000;
wire [15:0] v1 = pit_out1 ? 16'h1000 : 16'h0000;
wire [15:0] v2 = pit_out2 ? 16'h1000 : 16'h0000;
wire [15:0] snd_pit = m_ap || m_pt ? v0 + v1 + v2 : m_mk ? (ppi1_pc[1] ? v2 : 16'h0000) : 16'h0000;
wire [15:0] mix = (beep ? 16'h1800 : 16'h0000) + (tape_out ? 16'h0400 : 16'h0000) + snd_pit;

// a low-pass of two first-order stages of about 12 kHz (40 MHz / (2 pi 512)) before the 48 kHz samples:
// programs of the Apogey drive channels of the 8253 at hundreds of kHz (a count of 2, for silence or a
// level), which sampled bare folds into a squeal; Emu80 averages the output of the 8253 the same way
reg [24:0] lp1 = 25'd0, lp2 = 25'd0;
always @(posedge clk) begin
	lp1 <= lp1 + { 9'd0, mix } - { 9'd0, lp1[24:9] };
	lp2 <= lp2 + { 9'd0, lp1[24:9] } - { 9'd0, lp2[24:9] };
end
assign audio = lp2[24:9];

// ------------------------------------------------------------------ the VG75 and its DMA
// 8 MHz = 40 / 5; the Partner 9 MHz (its characters at 1.5 MHz): + 9 modulo 40
reg [2:0] pix_div = 3'd0;
reg [5:0] pix_acc = 6'd0;
reg ce_pix = 1'b0;
always @(posedge clk) begin
	pix_div <= pix_div == 3'd4 ? 3'd0 : pix_div + 3'd1;
	pix_acc <= pix_acc >= 6'd31 ? pix_acc - 6'd31 : pix_acc + 6'd9;
	ce_pix <= m_pt ? pix_acc >= 6'd31 : pix_div == 3'd4;
end

wire vid_drq, vid_dack;
wire [3:0] dack;
wire [7:0] crt_do;
wire vg_pix, vg_hilight, vg_hblank, vg_vblank, hrtc, vrtc;
wire [1:0] vg_gattr;
wire [10:0] font_addr;
wire [7:0] sram_do;

k580vt57 dma (
	.clk(clk),
	.ce_dma(ce_f2),
	.reset(run_reset),
	.iaddr(a[3:0]),
	.idata(cpu_do),
	.drq({ 1'b0, vid_drq, 2'b00 }),
	.iwe_n(~(sel_dma & mem_wr)),
	.ird_n(1'b1),
	.hlda(hlda),
	.hrq(hrq),
	.dack(dack),
	.odata(),
	.oaddr(dma_addr),
	.owe_n(),
	.ord_n(),
	.oiowe_n(),
	.oiord_n()
);
assign vid_dack = dack[2];

// the fonts: 2 KB of each model, written by the ROM loader at 1F0000
reg [7:0] font [0:16383];
reg [7:0] font_q = 8'd0;
wire [1:0] font_sel = m_80 ? 2'd3 : m_mk ? 2'd1 : m_ap ? 2'd2 : 2'd0;
wire [9:0] m80_font_addr;
wire [5:0] vg_attr;
wire [3:0] vg_line;
// the Partner: the set GPA0 + 2 GPA1 + 4 HGLT of the field attribute
wire [2:0] pt_set = { vg_attr[0], vg_attr[3], vg_attr[2] };
always @(posedge clk) begin
	if (rom_wr && rom_addr[21:14] == 8'h7C)      // 1F0000-1F3FFF
		font[rom_addr[13:0]] <= ~rom_data;   // the fonts of Emu80 are stored inverted (a point is 0)
	font_q <= font[m_pt ? { 1'b1, pt_set, font_addr[9:0] } :
	               { 1'b0, font_sel, m_80 ? { 1'b0, m80_font_addr } : font_addr }];
end

// the Mikro-80: its text screen as the stream of points
wire m80_pix, m80_hb, m80_vb;
rk_m80video m80video (
	.clk(clk),
	.ce_pix(ce_pix),
	.vram_we(sram_we && m80_mem && !sel_rpg && a[15:12] == 4'hE),
	.vram_a(a[11:0]),
	.vram_d(cpu_do),
	.font_addr(m80_font_addr),
	.font_q(font_q),
	.pix(m80_pix),
	.hblank(m80_hb),
	.vblank(m80_vb)
);

// the character of the point for the MCPG of the Partner
wire [10:0] mc_addr;
wire [2:0] mc_attr, mc_pt;
wire mc_bg, mc_gfx, mc_on;

k580vg75 crt (
	.clk_sys(clk),
	.reset(run_reset | m_80),
	.ce_pix(ce_pix),
	.iaddr(a[0]),
	.idata(hlda ? sram_do : cpu_do),
	.odata(crt_do),
	.iwe_n(~(sel_crt & mem_wr)),
	.ird_n(~(sel_crt & mem_rd)),
	.drq(vid_drq),
	.dack(vid_dack),
	.irq(),
	.vrtc(vrtc),
	.hrtc(hrtc),
	.vblank(vg_vblank),
	.hblank(vg_hblank),
	.pix(vg_pix),
	.hilight(vg_hilight),
	.gattr(vg_gattr),
	.charset(charset),
	.scr_shift(5'd0),
	.font_addr(font_addr),
	.font_data(font_q),
	.cur_attr(vg_attr),
	.cur_line(vg_line),
	.mc_addr(mc_addr),
	.mc_attr(mc_attr),
	.mc_bg(mc_bg),
	.mc_gfx(mc_gfx),
	.mc_pt(mc_pt),
	.mc_on(mc_on)
);

// the picture of the MCPG: its RAM in two halves of 2 KB (the points 0, 1 and 2, 3 of a character)
reg [7:0] mc_lo [0:2047];
reg [7:0] mc_hi [0:2047];
reg [7:0] mc_lq = 8'd0, mc_hq = 8'd0;
always @(posedge clk) begin
	if (sram_we && pt_mcram && !a[11])
		mc_lo[a[10:0]] <= cpu_do;
	mc_lq <= mc_lo[mc_addr];
end
always @(posedge clk) begin
	if (sram_we && pt_mcram && a[11])
		mc_hi[a[10:0]] <= cpu_do;
	mc_hq <= mc_hi[mc_addr];
end
// 4 points over the 6 of the character: 0 0 1 2 2 3
wire [2:0] mc_c = mc_pt < 3'd2 ? mc_lq[5:3] : mc_pt == 3'd2 ? mc_lq[2:0] : mc_pt < 3'd5 ? mc_hq[5:3] : mc_hq[2:0];
// R G B: of the colour, its bits inverted; of the background, GPA0 GPA1 HGLT
wire [2:0] mc_rgb = mc_c == 3'd7 || mc_bg ? { mc_attr[0], mc_attr[1], mc_attr[2] } : ~{ mc_c[0], mc_c[1], mc_c[2] };
wire mc_show = m_pt && mc_en && mc_on && !(mc_attr == 3'b011 && !mc_gfx);

// the beeper and the interrupt of the Partner
reg hrtc_d = 1'b0, vrtc_d = 1'b0, pt_req = 1'b0;
always @(posedge clk) begin
	hrtc_d <= hrtc;
	vrtc_d <= vrtc;
	if (hrtc_d && !hrtc)
		pt_beep <= !vg_line[2];
	if (run_reset)
		pt_req <= 1'b0;
	else if (vrtc && !vrtc_d)
		pt_req <= 1'b1;
	else if (inta && mem_rd)
		pt_req <= 1'b0;
end
assign pt_int = m_pt && pt_req;

// ------------------------------------------------------------------ the frame buffer (write side)
// the points: of the VG75, or of the screen of the Mikro-80
wire pix = m_80 ? m80_pix : vg_pix;
wire hilight = m_80 || m_pt ? 1'b0 : vg_hilight;   // the attributes of the Partner pick its font
wire [1:0] gattr = m_80 || m_pt ? 2'b00 : vg_gattr;
// the point in the buffer: { pix, hilight, gattr }; of the Partner { 0, pix, pix, pix } or the colour
// of the MCPG { 1, R, G, B } (rk_video, partner)
wire [3:0] fb_pt = m_pt ? (mc_show ? { 1'b1, mc_rgb } : { 1'b0, pix, pix, pix }) : { pix, hilight, gattr };
// the Partner: the window from the end of the retraces (its Monitor puts the text left of the hblank
// of this VG75, which is tuned to the RK raster), as Emu80 shows the whole raster
wire hblank = m_80 ? m80_hb : m_pt ? hrtc : vg_hblank;
wire vblank = m_80 ? m80_vb : m_pt ? vrtc : vg_vblank;
reg hb_d = 1'b1, vb_d = 1'b1;
// the size of the raster: the points of the last active line, the active lines of the last frame
reg [9:0] w_cnt = 10'd0, fb_w = 10'd0;
reg [8:0] h_cnt = 9'd0, fb_h = 9'd0;
// the picture in the middle of the window: where rk_video puts it, in cells of 4 points and lines of the
// buffer, from a raster that has stayed the same for 8 frames (a reset or a program in the middle of
// setting the VG75 moves nothing)
wire [9:0] w_lim = fb_w > 10'd512 ? 10'd512 : fb_w;
wire [8:0] h_lim = h_cnt > 9'd300 ? 9'd300 : h_cnt;
wire [9:0] w_free = 10'd512 - w_lim;
wire [8:0] h_free = 9'd300 - h_lim;
reg [9:0] w_p = 10'd0;
reg [8:0] h_p = 9'd0;
reg [2:0] same = 3'd0;
reg [6:0] center_x = 7'd0;
reg [7:0] center_y = 8'd0;
always @(posedge clk)
	if (ce_pix) begin
		if (hb_d && !hblank)
			w_cnt <= 10'd0;
		else if (!hblank && w_cnt != 10'd1023)
			w_cnt <= w_cnt + 10'd1;
		if (!hb_d && hblank && !vblank) begin
			fb_w <= w_cnt;
			h_cnt <= h_cnt + 9'd1;
		end
		if (!vb_d && vblank) begin
			fb_h <= h_cnt;
			h_cnt <= 9'd0;
			w_p <= fb_w;
			h_p <= h_cnt;
			if (fb_w != w_p || h_cnt != h_p)
				same <= 3'd0;
			else if (same != 3'd7)
				same <= same + 3'd1;
			else begin
				center_x <= w_free[9:3];
				center_y <= h_free[8:1];
			end
		end
	end
reg [9:0] fx = 10'd0;
reg [8:0] fy = 9'd0;
reg [3:0] lo_nib = 4'd0;
// a fifo of four writes {address in the buffer, byte}: a pair of points comes every 10 clocks
reg [24:0] fq [0:3];
reg [1:0] fq_wp = 2'd0, fq_rp = 2'd0;
reg [2:0] fq_n = 3'd0;
wire fb_pend = fq_n != 3'd0;
wire [21:0] fb_addr = FB_BASE + { 5'd0, fq[fq_rp][24:8] };
wire [7:0] fb_data = fq[fq_rp][7:0];
wire fb_ack;
wire act = !hblank && !vblank;
reg fq_push = 1'b0;
always @(posedge clk) begin
	fq_push <= 1'b0;
	if (fb_ack)
		fq_rp <= fq_rp + 2'd1;
	if (fq_push && fq_n != 3'd4)
		fq_wp <= fq_wp + 2'd1;
	fq_n <= fq_n + ((fq_push && fq_n != 3'd4) ? 3'd1 : 3'd0) - (fb_ack ? 3'd1 : 3'd0);
	if (ce_pix) begin
		hb_d <= hblank;
		vb_d <= vblank;
		// the whole window every frame: the points out of the raster of the VG75 (its retraces) are
		// black, so a smaller raster (another model, other parameters) leaves nothing of the old one
		if (vb_d && !vblank)
			fy <= 9'd0;
		else if (!hb_d && hblank && fy != 9'd511)
			fy <= fy + 9'd1;
		if (hb_d && !hblank)
			fx <= 10'd0;
		else if (fx != 10'd1023)
			fx <= fx + 10'd1;
		if (fx < 10'd512 && fy < 9'd300) begin
			if (!fx[0])
				lo_nib <= act ? fb_pt : 4'd0;
			else begin
				fq[fq_wp] <= { fy, fx[8:1], act ? fb_pt : 4'd0, lo_nib };
				fq_push <= 1'b1;
			end
		end
	end
end

// ------------------------------------------------------------------ the memory
// the ROM: 100000 + (a - F800) of the RK86, 100800 + .. of the Mikrosha, 101000 + (a - F000) of the
// Apogey; at startup its upper 2 KB
wire [21:0] mon_off = m_ap ? 22'h101000 | { 10'd0, a[11] | startup, a[10:0] } :
                      model == 3'd5 ? 22'h102800 | { 11'd0, a[10:0] } : m_80 ? 22'h102000 | { 11'd0, a[10:0] } :
                      m_mk ? 22'h100800 | { 11'd0, a[10:0] } : a[15:12] == 4'hE ? 22'h10B000 | { 10'd0, a[11:0] } :
                      22'h100000 | { 11'd0, a[10:0] };
wire [2:0] rpage_n = rpage[2:0] - 3'd1;   // pages 1..8 as 0..7
wire [21:0] sram_addr = hlda ? (m_pt ? pt_sram(pblk_dma, dma_addr) : { 6'd0, dma_addr }) :
                        m_pt ? pt_sram(pblk, a) : sel_rpg ? { 3'b101, rpage_n, a } : sel_rom ? mon_off :
                        sel_rdisk ? 22'h200000 | { 3'd0, rd_addr } : { 6'd0, a };
assign sram_we = mem_wr && (sel_ram || sel_rpg) && !hlda;

// ------------------------------------------------------------------ autorun of a tape file
wire [15:0] rk_start;
wire rk_ok;
reg file_d = 1'b0, rd_d = 1'b0;
reg [27:0] run_wait = 28'd0;   // the Monitor runs first, as the skipTicks of Emu80
reg run_pend = 1'b0, run_arm = 1'b0;
reg [1:0] inj = 2'd0;          // 1 the opcode, 2 / 3 the address bytes
wire rd_end = rd_d & ~mem_rd;
always @(posedge clk) begin
	file_d <= file_active;
	rd_d <= mem_rd;
	if (reset) begin
		run_pend <= 1'b0;
		run_arm <= 1'b0;
		inj <= 2'd0;
	end
	else if (file_d && !file_active) begin
		run_pend <= autorun && rk_ok && file_slot == 8'd1;
		run_arm <= 1'b0;
		inj <= 2'd0;
		// 2 000 000 ticks of the CPU (Emu80: 1.125 s at 1.78 MHz, 1 s at 2 MHz; the Monitor of the Partner
		// sets its variables only after 0.4 s), the Mikro-80 7 000 000 (3.5 s: its RK type Monitor checks
		// the memory for 3 s)
		run_wait <= m_80 ? 28'd139999999 : m_pt ? 28'd39999999 : 28'd44999999;
	end
	else if (run_pend) begin
		if (run_wait == 28'd0) begin
			run_pend <= 1'b0;
			run_arm <= 1'b1;
		end
		else
			run_wait <= run_wait - 28'd1;
	end
	else if (run_arm && mem_rd && fetch) begin
		run_arm <= 1'b0;
		inj <= 2'd1;
	end
	else if (inj != 2'd0 && rd_end)
		inj <= inj == 2'd3 ? 2'd0 : inj + 2'd1;
end

always @* begin
	cpu_di = 8'hFF;
	if (inta) cpu_di = 8'hF7;            // RST 6 (the interrupt of the Partner)
	else if (inj == 2'd1) cpu_di = 8'hC3;
	else if (inj == 2'd2) cpu_di = rk_start[7:0];
	else if (inj == 2'd3) cpu_di = rk_start[15:8];
	else if (sel_rpg) cpu_di = sram_do;
	else if (sel_rom) cpu_di = sram_do;
	else if (sel_ram) cpu_di = sram_do;
	else if (sel_tape) cpu_di = { 7'd0, tape_in };
	else if (sel_rdisk) cpu_di = sram_do;
	else if (sel_pit) cpu_di = pit_do;
	else if (sel_ppi1) cpu_di = ppi1_do;
	else if (sel_ppi2) cpu_di = ppi2_do;
	else if (sel_crt) cpu_di = crt_do;
	else if (sel_sd) cpu_di = a[0] ? 8'h00 : sd_do;
end

// ------------------------------------------------------------------ the SD card of SDOS
wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;
always @(posedge clk)
	if (sdc_img_mounted[3])
		sd_on <= |sdc_img_size[31:0];
wire mmc_rd, mmc_wr;
wire [31:0] mmc_lba;
wire [7:0] mmc_byte_out;
wire sdc_busy, sdc_done, sdc_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_in_data;

wire [7:0] sdc_rd_v = { 4'd0, mmc_rd, 3'd0 };
wire [7:0] sdc_wr_v = { 4'd0, mmc_wr, 3'd0 };
wire [31:0] sdc_sector_v = mmc_lba;
wire [7:0] sdc_byte_out_data_v = mmc_byte_out;

generate if (LINK == 1) begin : link1
// no reset: a reset of the machine during a request leaves img_sdc to finish it
img_sdc #(
	.OUT_LATENCY(3),
	.TIMEOUT(24'd8000000)     // 200 ms at 40 MHz
) sdc (
	.clk(clk),
	.reset(1'b0),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd(sdc_rd_v),
	.sdc_wr(sdc_wr_v),
	.sdc_sector(sdc_sector_v),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(),
	.sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_in_data),
	.sdc_byte_out_data(sdc_byte_out_data_v),
	.active()
);
	assign sdc_rd_o = 8'd0;
	assign sdc_wr_o = 8'd0;
	assign sdc_sector_o = 32'd0;
	assign sdc_byte_out_data_o = 8'd0;
end else begin : link2
	assign sdc_img_mounted = sdc_img_mounted_i;
	assign sdc_img_size = sdc_img_size_i;
	assign sdc_busy = sdc_busy_i;
	assign sdc_done = sdc_done_i;
	assign sdc_slot = sdc_slot_i;
	assign sdc_in_strobe = sdc_byte_in_strobe_i;
	assign sdc_byte_addr = sdc_byte_addr_i;
	assign sdc_in_data = sdc_byte_in_data_i;
	assign sdc_rd_o = sdc_rd_v;
	assign sdc_wr_o = sdc_wr_v;
	assign sdc_sector_o = sdc_sector_v;
	assign sdc_byte_out_data_o = sdc_byte_out_data_v;
	assign img_q_wr = 1'b0;
	assign img_q_di = 24'd0;
end endgenerate

rk_sd sd (
	.clk(clk),
	.reset(run_reset),
	.cs_wr(wr_p && sel_sd && a[0]),
	.d_wr(wr_p && sel_sd && !a[0]),
	.din(cpu_do),
	.dout(sd_do),
	.img_mounted(sdc_img_mounted[3]),
	.img_size(sdc_img_size[31:0]),
	.hd_rd(mmc_rd),
	.hd_wr(mmc_wr),
	.hd_lba(mmc_lba),
	.hd_busy(sdc_busy && sdc_slot == 3'd3),
	.hd_done(sdc_done && sdc_slot == 3'd3),
	.hd_byte_in_strobe(sdc_in_strobe && sdc_slot == 3'd3),
	.hd_byte_addr(sdc_byte_addr),
	.hd_byte_in_data(sdc_in_data),
	.hd_byte_out_data(mmc_byte_out)
);

// the aux port of the SRAM: the loaders, else the frame buffer
wire ld_req, aux_ack;
wire [21:0] ld_addr;
wire [7:0] ld_din;
reg own_fb = 1'b0;
always @(posedge clk)
	if (aux_ack)
		own_fb <= 1'b0;
	else if (!ld_req && fb_pend)
		own_fb <= 1'b1;
assign fb_ack = aux_ack && own_fb;
wire aux_req = own_fb ? fb_pend : ld_req;

rk_loader loader (
	.clk(clk),
	.rom_active(rom_active),
	.rom_addr(rom_addr),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.rk_start(rk_start),
	.rk_ok(rk_ok),
	.aux_req(ld_req),
	.aux_addr(ld_addr),
	.aux_din(ld_din),
	.aux_ack(aux_ack && !own_fb)
);

wire vid_req, vid_valid;
wire [20:0] vid_addr;
wire [15:0] vid_dout;

rk_video video (
	.clk(clk),
	.color(color && m_ap),
	.partner(m_pt),
	.center_x(center_x),
	.center_y(center_y),
	.vid_req(vid_req),
	.vid_addr(vid_addr),
	.vid_dout(vid_dout),
	.vid_valid(vid_valid),
	.rgb(rgb),
	.hs(hs),
	.vs(vs),
	.de(de)
);

rk_sram sram (
	.clk(clk),
	.addr(sram_addr),
	.we(sram_we),
	.din(cpu_do),
	.din_hi(8'h00),
	.wr16(1'b0),
	.dout(sram_do),
	.rd_ok(),
	.aux_req(aux_req),
	.aux_we(1'b1),
	.aux_addr(own_fb ? fb_addr : ld_addr),
	.aux_din(own_fb ? fb_data : ld_din),
	.aux_ack(aux_ack),
	.aux_dout(),
	.vid_req(vid_req),
	.vid_addr(vid_addr),
	.vid_dout(vid_dout),
	.vid_valid(vid_valid),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

endmodule
