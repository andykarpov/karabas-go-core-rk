`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_system.v

 The Radio-86RK family on one clock of 40 MHz: the processor, the memory map, the ports, the VG75 CRT
 controller with its DMA, the frame buffer, the video output and the SRAM. docs/HARDWARE.md has the maps.
 model: 0 the Radio-86RK, 1 the Mikrosha, 2 the Apogey BK-01 (3 and 4, the Partner and the Mikro-80, are
 the RK86 for now). Change it only during reset.

 The Mikrosha: the keyboard PPI at C000 with ports A and B swapped (rk_kbd mikrosha), the second PPI
 at C800 (PB7 the second font), the VG75 at D000, the 8253 at D800 (channel 2 the sound, gated by PC1
 of the keyboard PPI, its GATE is PC2), the Monitor at F800. The Apogey: RAM to EBFF, the 8253 at EC00
 (the three channels the sound), the keyboard PPI at ED00 (as the RK86), the PPI of the ROM disk at
 EE00, the VG75 at EF00, the ROM of 4 KB at F000 (writes there go to the DMA); its font set is INTE,
 its colour the attributes of the VG75. The ROM disk (Emu80 ApogeyRomDisk, Apogee_MiSTer EXTROM):
 port A reads byte { bank, PC[6:0], PB } of the disk, the bank is PB[3:0] at the rising edge of PC7.
 The 8253 is KF8253 (kitune-san, MIT) on 1.78 MHz, not on turbo.

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
   200000  the ROM disk of the Apogey (512 KB, FL slot 2)
   300000  the frame buffer, 512 x 300 x 4 bits
 The fonts (the character generators of the VG75, 2 KB each: the RK86, the Mikrosha, the Apogey) are
 a block RAM of 8 KB, written by the ROM loader at 1F0000, 1F0800, 1F1000, inverted: the fonts of
 Emu80 have a point as 0. The ROMs arrive by the ROM loader of the mcu; the machine is in reset while they load.

 After reset the Monitor answers every read (its first bytes are a jump to F836), until the first read
 at 8000-FFFF, as the startup flip-flop of Apogee_MiSTer.

 A tape file starts as Emu80 runs it: after the load the machine leaves reset, its Monitor runs for
 200 ms (it sets up the PPI, the VG75 and its variables), then the next opcode fetch reads JMP start
 instead of the memory (autorun; core-specialist does the same).
*/

module rk_system (
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
wire mem_rd, mem_wr, fetch, inte, ce_f2;
wire hrq, hlda;

rk_cpu cpu (
	.clk(clk),
	.reset(run_reset),
	.fast(1'b0),
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
	.inte(inte),
	.ce_f2(ce_f2)
);

wire m_mk = model == 3'd1;
wire m_ap = model == 3'd2;
wire m_rk = !m_mk && !m_ap;

assign beep = m_rk & inte;

reg wr_d = 1'b0;
always @(posedge clk)
	wr_d <= mem_wr;
wire wr_p = mem_wr & ~wr_d;

// the Monitor everywhere after reset
reg startup = 1'b1;
always @(posedge clk)
	if (run_reset)
		startup <= 1'b1;
	else if (mem_rd && a[15])
		startup <= 1'b0;

// ------------------------------------------------------------------ decoding
wire f800 = a[15:11] == 5'b11111;
wire ap_io = a[15:10] == 6'b111011;               // EC00-EFFF of the Apogey
// the RK86: 8000 PPI 1, A000 PPI 2, C000 VG75, E000-FFFF writes the DMA, F800 the Monitor
// the Mikrosha: C000 PPI 1, C800 PPI 2, D000 VG75, D800 8253, F800 the Monitor and the DMA
// the Apogey: EC00 8253, ED00 PPI 1, EE00 PPI 2, EF00 VG75, F000 the ROM and the DMA
wire sel_ppi1 = m_mk ? a[15:11] == 5'b11000 : m_ap ? ap_io && a[9:8] == 2'd1 : a[15:13] == 3'b100;
wire sel_ppi2 = m_mk ? a[15:11] == 5'b11001 : m_ap ? ap_io && a[9:8] == 2'd2 : a[15:13] == 3'b101;
wire sel_crt = m_mk ? a[15:11] == 5'b11010 : m_ap ? ap_io && a[9:8] == 2'd3 : a[15:13] == 3'b110;
wire sel_pit = m_mk ? a[15:11] == 5'b11011 : m_ap ? ap_io && a[9:8] == 2'd0 : 1'b0;
wire sel_mon = m_ap ? a[15:12] == 4'hF : f800;
wire sel_dma = m_rk ? a[15:13] == 3'b111 : sel_mon;
wire sel_rom = startup || (sel_mon && !mem_wr);
wire sel_ram = m_ap ? a[15:12] != 4'hF && !ap_io : !a[15];
wire sel_rdisk = m_ap && sel_ppi2 && a[1:0] == 2'd0;   // port A: the ROM disk

// ------------------------------------------------------------------ the PPIs
wire [7:0] ppi1_do, ppi2_do, ppi1_pc, ppi1_pa, ppi1_pb, ppi2_pb, ppi2_pc;
wire ppi2_pb_in;

wire [7:0] kb_scan, kb_ret;
wire [3:0] kb_pc_hi;

rk_ppi ppi1 (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_ppi1), .din(cpu_do), .dout(ppi1_do),
	.pa_i(m_mk ? kb_ret : 8'hFF), .pb_i(m_mk ? 8'hFF : kb_ret), .pc_i({ kb_pc_hi[3:1], tape_in, 4'hF }),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(ppi1_pa), .pb_o(ppi1_pb), .pc_o(ppi1_pc)
);
assign kb_scan = m_mk ? ppi1_pb : ppi1_pa;

rk_kbd kbd (
	.clk(clk), .reset(reset), .ms7007(1'b0), .mikrosha(m_mk),
	.scancode(kb_scancode), .scancode_upd(kb_scancode_upd), .joy(joy),
	.scan(kb_scan), .ret(kb_ret), .pc_hi(kb_pc_hi)
);
assign tape_out = ppi1_pc[0];

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
wire [18:0] rd_addr = { rd_bank, ppi2_pc[6:0], ppi2_pb };

// the font set: PB7 of PPI 2 of the Mikrosha (0 while the port is an input), INTE of the Apogey
wire charset = m_mk ? !ppi2_pb_in && ppi2_pb[7] : m_ap ? inte : 1'b0;

// ------------------------------------------------------------------ the 8253 and the sound
reg [5:0] pit_acc = 6'd0;      // 40 MHz * 2 / 45 = 1.78 MHz
always @(posedge clk)
	pit_acc <= pit_acc >= 6'd43 ? pit_acc - 6'd43 : pit_acc + 6'd2;
wire pit_clk = pit_acc < 6'd23;
wire [7:0] pit_do;
wire pit_out0, pit_out1, pit_out2;

KF8253 pit (
	.clock(clk),
	.reset(run_reset),
	.chip_select_n(~sel_pit),
	.read_enable_n(~mem_rd),
	.write_enable_n(~mem_wr),
	.address(a[1:0]),
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
wire [15:0] snd_pit = m_ap ? v0 + v1 + v2 : m_mk ? (ppi1_pc[1] ? v2 : 16'h0000) : 16'h0000;
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
reg [2:0] pix_div = 3'd0;
reg ce_pix = 1'b0;
always @(posedge clk) begin
	pix_div <= pix_div == 3'd4 ? 3'd0 : pix_div + 3'd1;
	ce_pix <= pix_div == 3'd4;
end

wire [15:0] dma_addr;
wire vid_drq, vid_dack;
wire [3:0] dack;
wire [7:0] crt_do;
wire pix, hilight, hblank, vblank, hrtc, vrtc;
wire [1:0] gattr;
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
reg [7:0] font [0:8191];
reg [7:0] font_q = 8'd0;
wire [1:0] font_sel = m_mk ? 2'd1 : m_ap ? 2'd2 : 2'd0;
always @(posedge clk) begin
	if (rom_wr && rom_addr[21:13] == 9'h0F8)     // 1F0000-1F1FFF
		font[rom_addr[12:0]] <= ~rom_data;   // the fonts of Emu80 are stored inverted (a point is 0)
	font_q <= font[{ font_sel, font_addr }];
end

k580vg75 crt (
	.clk_sys(clk),
	.reset(run_reset),
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
	.vblank(vblank),
	.hblank(hblank),
	.pix(pix),
	.hilight(hilight),
	.gattr(gattr),
	.charset(charset),
	.scr_shift(5'd0),
	.font_addr(font_addr),
	.font_data(font_q)
);

// ------------------------------------------------------------------ the frame buffer (write side)
reg hb_d = 1'b1, vb_d = 1'b1;
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
				lo_nib <= act ? { pix, hilight, gattr } : 4'd0;
			else begin
				fq[fq_wp] <= { fy, fx[8:1], act ? { pix, hilight, gattr } : 4'd0, lo_nib };
				fq_push <= 1'b1;
			end
		end
	end
end

// ------------------------------------------------------------------ the memory
// the ROM: 100000 + (a - F800) of the RK86, 100800 + .. of the Mikrosha, 101000 + (a - F000) of the
// Apogey; at startup its upper 2 KB
wire [21:0] mon_off = m_ap ? 22'h101000 | { 10'd0, a[11] | startup, a[10:0] } :
                      m_mk ? 22'h100800 | { 11'd0, a[10:0] } : 22'h100000 | { 11'd0, a[10:0] };
wire [21:0] sram_addr = hlda ? { 6'd0, dma_addr } : sel_rom ? mon_off :
                        sel_rdisk ? 22'h200000 | { 3'd0, rd_addr } : { 6'd0, a };
wire sram_we = mem_wr && sel_ram && !hlda;

// ------------------------------------------------------------------ autorun of a tape file
wire [15:0] rk_start;
wire rk_ok;
reg file_d = 1'b0, rd_d = 1'b0;
reg [22:0] run_wait = 23'd0;   // 200 ms of the Monitor
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
		run_wait <= 23'd7999999;
	end
	else if (run_pend) begin
		if (run_wait == 23'd0) begin
			run_pend <= 1'b0;
			run_arm <= 1'b1;
		end
		else
			run_wait <= run_wait - 23'd1;
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
	if (inj == 2'd1) cpu_di = 8'hC3;
	else if (inj == 2'd2) cpu_di = rk_start[7:0];
	else if (inj == 2'd3) cpu_di = rk_start[15:8];
	else if (sel_rom) cpu_di = sram_do;
	else if (sel_ram) cpu_di = sram_do;
	else if (sel_rdisk) cpu_di = sram_do;
	else if (sel_pit) cpu_di = pit_do;
	else if (sel_ppi1) cpu_di = ppi1_do;
	else if (sel_ppi2) cpu_di = ppi2_do;
	else if (sel_crt) cpu_di = crt_do;
end

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
