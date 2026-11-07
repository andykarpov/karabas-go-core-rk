`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_system.v

 The Radio-86RK family on one clock of 40 MHz: the processor, the memory map, the ports, the VG75 CRT
 controller with its DMA, the frame buffer and the SRAM. docs/HARDWARE.md has the maps. Phase 0: the
 Radio-86RK without keyboard and video output (the frame buffer is written; rk_video in phase 1).

 The VG75 (k580vg75) and the VT57 (k580vt57) come from Apogee_MiSTer and run at the native timing: the
 points at 8 MHz (40 / 5), the DMA on the F2 enable of the CPU, which it holds (HOLD / HLDA) while it reads
 the character rows. The DMA reads the SRAM at its address: the VT57 puts the address out at least a
 state (22 clocks) before DACK, and the SRAM answers within nine, so no wait is needed.

 The frame buffer: the points of the VG75 (point, highlight, the two colour bits of the Apogey: 4 bits)
 in a window of 512 x 300 from the first active point of the first active line (the hblank / vblank of
 the VG75), two points a byte (the first in the low nibble), 256 bytes a line, in the SRAM at FB_BASE.
 rk_video reads it as 16-bit words of four points.

 SRAM (a byte address of 22 bits, rk_sram):
   000000  the main RAM, 64 KB
   100000  the Monitor of the RK86 (2 KB, F800-FFFF)
   300000  the frame buffer, 512 x 300 x 4 bits
 The font (the character generator of the VG75) is a block RAM of 2 KB, written by the ROM loader at
 1F0000, inverted: the fonts of Emu80 have a point as 0. The ROMs arrive by the ROM loader of the mcu; the machine is in reset while they load.

 After reset the Monitor answers every read (its first bytes are a jump to F836), until the first read
 at 8000-FFFF, as the startup flip-flop of Apogee_MiSTer.
*/

module rk_system (
	input wire clk,
	input wire reset,
	input wire turbo,

	// the ROM loader of the mcu
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	// the keyboard PPI (8000): A the columns out, B the rows in, C high the shift keys in
	output wire [7:0] kb_pa_o,
	input wire [7:0] kb_pb_i,
	input wire [2:0] kb_pc_i,     // PC7 RUS/LAT, PC6 US, PC5 SS: 0 = pressed
	input wire tape_in,           // PC4

	output wire beep,             // INTE of the CPU
	output wire tape_out,         // PC0

	// the video port of rk_sram (rk_video)
	input wire vid_req,
	input wire [20:0] vid_addr,
	output wire [15:0] vid_dout,
	output wire vid_valid,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

localparam [21:0] FB_BASE = 22'h300000;

wire run_reset = reset | rom_active;

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

assign beep = inte;

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

// ------------------------------------------------------------------ decoding (the Radio-86RK)
wire sel_ppi1 = a[15:13] == 3'b100;               // 8000-9FFF
wire sel_ppi2 = a[15:13] == 3'b101;               // A000-BFFF
wire sel_crt = a[15:13] == 3'b110;                // C000-DFFF
wire sel_hi = a[15:13] == 3'b111;                 // E000-FFFF: reads the ROMs, writes the DMA
wire sel_mon = a[15:11] == 5'b11111;              // F800-FFFF
wire sel_dma = sel_hi;
wire sel_rom = startup || (sel_mon && !mem_wr);
wire sel_ram = !a[15];

// ------------------------------------------------------------------ the PPIs
wire [7:0] ppi1_do, ppi2_do, ppi1_pc;

rk_ppi ppi1 (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_ppi1), .din(cpu_do), .dout(ppi1_do),
	.pa_i(8'hFF), .pb_i(kb_pb_i), .pc_i({ kb_pc_i, tape_in, 4'hF }),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(kb_pa_o), .pb_o(), .pc_o(ppi1_pc)
);
assign tape_out = ppi1_pc[0];

rk_ppi ppi2 (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_ppi2), .din(cpu_do), .dout(ppi2_do),
	.pa_i(8'hFF), .pb_i(8'hFF), .pc_i(8'hFF),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(), .pb_o(), .pc_o()
);

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

// the font: 2 KB, written by the ROM loader at 1F0000
reg [7:0] font [0:2047];
reg [7:0] font_q = 8'd0;
always @(posedge clk) begin
	if (rom_wr && rom_addr[21:11] == 11'h3E0)     // 1F0000-1F07FF
		font[rom_addr[10:0]] <= ~rom_data;   // the fonts of Emu80 are stored inverted (a point is 0)
	font_q <= font[font_addr];
end

k580vg75 crt (
	.clk_sys(clk),
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
	.charset(1'b0),
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
		if (vb_d && !vblank)
			fy <= 9'd0;
		else if (!hb_d && hblank && !vblank)
			fy <= fy + 9'd1;
		if (hb_d && !hblank)
			fx <= 10'd0;
		else if (act)
			fx <= fx + 10'd1;
		if (act && fx < 10'd512 && fy < 9'd300) begin
			if (!fx[0])
				lo_nib <= { pix, hilight, gattr };
			else begin
				fq[fq_wp] <= { fy, fx[8:1], pix, hilight, gattr, lo_nib };
				fq_push <= 1'b1;
			end
		end
	end
end

// ------------------------------------------------------------------ the memory
wire [21:0] mon_off = 22'h100000 | { 11'd0, a[10:0] };   // 100000 + (a - F800), and 0000.. at startup
wire [21:0] sram_addr = hlda ? { 6'd0, dma_addr } : sel_rom ? mon_off : { 6'd0, a };
wire sram_we = mem_wr && sel_ram && !hlda;

always @* begin
	cpu_di = 8'hFF;
	if (sel_rom) cpu_di = sram_do;
	else if (sel_ram) cpu_di = sram_do;
	else if (sel_ppi1) cpu_di = ppi1_do;
	else if (sel_ppi2) cpu_di = ppi2_do;
	else if (sel_crt) cpu_di = crt_do;
end

// the aux port of the SRAM: the ROM loader, else the frame buffer
reg ld_req = 1'b0;
reg [21:0] ld_addr = 22'd0;
reg [7:0] ld_din = 8'd0;
wire aux_ack;
reg own_fb = 1'b0;
always @(posedge clk) begin
	if (rom_wr) begin
		ld_req <= 1'b1;
		ld_addr <= rom_addr;
		ld_din <= rom_data;
	end
	else if (aux_ack && !own_fb)
		ld_req <= 1'b0;
	if (aux_ack)
		own_fb <= 1'b0;
	else if (!ld_req && fb_pend)
		own_fb <= 1'b1;
end
assign fb_ack = aux_ack && own_fb;
wire aux_req = own_fb ? fb_pend : ld_req;

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
