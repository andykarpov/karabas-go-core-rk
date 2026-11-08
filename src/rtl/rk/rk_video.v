`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_video.v

 The frame buffer of rk_system as VESA 800 x 600 at 60 Hz (40.0 MHz, 1056 x 628, positive syncs): the
 output never follows the timing the program gives the VG75, so the monitor of the user always gets a
 standard mode.

 The buffer: 512 x 300 points of 4 bits (point, highlight, the two colour bits of the Apogey), at word
 FB_WORD of the SRAM, 128 words a line, four points a word (the first in the low nibble). On the screen
 a line of the buffer is two lines (600), and two points are three pixels (768, x 16..783). center_x / center_y
 move the picture to the middle of that area.

 A line of the buffer is fetched into one half of a line buffer (block RAM) during the output line
 before its first one (128 words through the video port of rk_sram, some 800 clocks of 1056), the
 other half shows.

 Colours: mono (a point grey, a highlighted point white) or the colours of the Apogey (Apogee_MiSTer:
 R = point and not highlight, G = point and not gattr1, B = point and not gattr0). The Partner: { 0, p, p, p }
 its text (grey), { 1, R, G, B } a point of its colour module MCPG.
*/

module rk_video #(
	parameter [20:0] FB_WORD = 21'h180000
) (
	input wire clk,
	input wire color,
	input wire partner,   // the points of the Partner: { 0, p, p, p } the text, { 1, R, G, B } the MCPG
	input wire [6:0] center_x,  // the picture moves right by cells of 4 points (6 pixels), down by lines of
	input wire [7:0] center_y,  // the buffer (2 lines), to sit in the middle; what leaves the 768 x 600 is dark

	output reg vid_req = 1'b0,
	output reg [20:0] vid_addr = 21'd0,
	input wire [15:0] vid_dout,
	input wire vid_valid,

	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0
);

localparam H_TOTAL = 1056, H_VISIBLE = 800, H_SYNC = 840, H_SYNC_END = 968;
localparam V_TOTAL = 628, V_VISIBLE = 600, V_SYNC = 601, V_SYNC_END = 605;
localparam X0 = 16;          // the first pixel of the picture

reg [10:0] hcnt = 11'd0;
reg [9:0] vcnt = 10'd0;
reg [6:0] xs = 7'd0;          // center_x / center_y, taken between two frames
reg [7:0] ys = 8'd0;
always @(posedge clk)
	if (hcnt == H_TOTAL - 1) begin
		hcnt <= 11'd0;
		vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
		if (vcnt == V_VISIBLE) begin
			xs <= center_x;
			ys <= center_y;
		end
	end
	else
		hcnt <= hcnt + 11'd1;

// ------------------------------------------------------------------ the fetch
// at the start of an output line whose next line is the first of a buffer line n, fetch n into half n[0]
wire [9:0] vnext = (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
reg busy = 1'b0, waiting = 1'b0;
reg [7:0] fcol = 8'd0;
reg [8:0] fline = 9'd0;
reg buf_we = 1'b0;
reg [7:0] buf_wa = 8'd0;
reg [15:0] buf_wd = 16'd0;
always @(posedge clk) begin
	vid_req <= 1'b0;
	buf_we <= 1'b0;
	if (hcnt == 11'd0 && vnext < V_VISIBLE && !vnext[0]) begin
		busy <= 1'b1;
		waiting <= 1'b0;
		fcol <= 8'd0;
		fline <= vnext[9:1] - { 1'b0, ys };
	end
	else if (busy && !waiting) begin
		if (fcol == 8'd128)
			busy <= 1'b0;
		else begin
			vid_req <= 1'b1;
			vid_addr <= FB_WORD + { 5'd0, fline, fcol[6:0] };
			waiting <= 1'b1;
		end
	end
	else if (busy && vid_valid) begin
		buf_we <= 1'b1;
		buf_wa <= { fline[0], fcol[6:0] };
		buf_wd <= vid_dout;
		fcol <= fcol + 8'd1;
		waiting <= 1'b0;
	end
end

reg [15:0] lbuf [0:255];
reg [15:0] buf_q = 16'd0;
reg [7:0] buf_ra = 8'd0;
always @(posedge clk) begin
	if (buf_we)
		lbuf[buf_wa] <= buf_wd;
	buf_q <= lbuf[buf_ra];
end

// ------------------------------------------------------------------ the picture
// stage 0 (hcnt = h): the cell of pixel h (x = h - X0: cell x / 6, its point 0 0 1 2 2 3 by x % 6)
// addresses the line buffer; stage 1: its word; stage 2: rgb, with hs / vs / de of h delayed as much
wire [10:0] y0 = { 2'b00, ys, 1'b0 };   // the first line of the picture
wire [10:0] x0 = X0 + { 2'b00, xs, 2'b00 } + { 3'b000, xs, 1'b0 };   // its first pixel (6 a cell)
wire in_y = vcnt < V_VISIBLE && { 1'b0, vcnt } >= y0;
reg [2:0] ph = 3'd0;
reg [6:0] pcell = 7'd0;
reg run = 1'b0;
always @(posedge clk) begin
	if (hcnt == x0 - 11'd1) begin
		run <= in_y;
		ph <= 3'd0;
		pcell <= 7'd0;
	end
	else if (run && hcnt == X0 + 11'd767)   // the end of the area
		run <= 1'b0;
	else if (run) begin
		if (ph == 3'd5) begin
			ph <= 3'd0;
			pcell <= pcell + 7'd1;
			if (pcell == 7'd127)
				run <= 1'b0;
		end
		else
			ph <= ph + 3'd1;
	end
end
// run, ph and pcell now describe pixel hcnt

reg [1:0] pt1 = 2'd0;
reg vis1 = 1'b0, vis2 = 1'b0;
reg de1 = 1'b0, hs1 = 1'b0, vs1 = 1'b0;
always @(posedge clk) begin
	// stage 0 -> 1
	buf_ra <= { vcnt[1] ^ ys[0], pcell };
	pt1 <= (ph == 3'd0 || ph == 3'd1) ? 2'd0 : (ph == 3'd2) ? 2'd1 : (ph == 3'd3 || ph == 3'd4) ? 2'd2 : 2'd3;
	vis1 <= run;
	de1 <= hcnt < H_VISIBLE && vcnt < V_VISIBLE;
	hs1 <= hcnt >= H_SYNC && hcnt < H_SYNC_END;
	vs1 <= vcnt >= V_SYNC && vcnt < V_SYNC_END;
end

// stage 1: buf_q is the word of the cell (the read of buf_ra registered once more in lbuf)
reg [1:0] pt2 = 2'd0;
reg de2 = 1'b0, hs2 = 1'b0, vs2 = 1'b0;
always @(posedge clk) begin
	pt2 <= pt1;
	vis2 <= vis1;
	de2 <= de1;
	hs2 <= hs1;
	vs2 <= vs1;
end

wire [3:0] nib = buf_q[{ pt2, 2'b00 } +: 4];
wire p = nib[3], hl = nib[2];
wire [7:0] lv = hl ? 8'hFF : 8'hC0;
wire [23:0] c_mono = p ? { lv, lv, lv } : 24'd0;
wire [23:0] c_color = { (p & ~hl) ? 8'hFF : 8'h00, (p & ~nib[1]) ? 8'hFF : 8'h00, (p & ~nib[0]) ? 8'hFF : 8'h00 };
wire [23:0] c_pt = nib[3] ? { nib[2] ? 8'hFF : 8'h00, nib[1] ? 8'hFF : 8'h00, nib[0] ? 8'hFF : 8'h00 } :
                   nib[0] ? 24'hC0C0C0 : 24'd0;

// stage 2
always @(posedge clk) begin
	de <= de2;
	hs <= hs2;
	vs <= vs2;
	rgb <= vis2 ? (partner ? c_pt : color ? c_color : c_mono) : 24'd0;
end

endmodule
