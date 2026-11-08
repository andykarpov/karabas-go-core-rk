`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_m80video.v

 The text screen of the Mikro-80 (Emu80 Mikro80Renderer) as a stream of points for the frame buffer
 of rk_system, in place of the VG75: 64 x 32 characters of 6 x 8 points; E800-EFFF the codes (7 bits),
 E000-E7FF the attributes, bit 7 of the attribute of the NEXT cell inverts a cell (not the last of a
 row). The machine shows a row of 10 lines (8 of the character, 2 dark): here 9 (8 + 1), so the 32
 rows (288 lines) fit the window of 512 x 300; the picture (384 x 288) is in its middle.

 The stream has the shape of the VG75 one: a point at each ce_pix, lines of 640 points (hblank after
 512), frames of 312 lines (vblank after 300). The screen memory is a copy in block RAM, written with
 the CPU writes at E000-EFFF (vram_we); the font is the font RAM of rk_system (font_addr / font_q,
 one clock), the points inverted there already (a point is 1).
*/

module rk_m80video (
	input wire clk,
	input wire ce_pix,

	input wire vram_we,
	input wire [11:0] vram_a,     // the CPU address - E000
	input wire [7:0] vram_d,

	output wire [9:0] font_addr,  // { code[6:0], line[2:0] }
	input wire [7:0] font_q,

	output reg pix = 1'b0,
	output reg hblank = 1'b0,
	output reg vblank = 1'b0
);

// the copy of the screen: the codes and bit 7 of the attributes
reg [6:0] chr [0:2047];
reg att [0:2047];
always @(posedge clk)
	if (vram_we) begin
		if (vram_a[11])
			chr[vram_a[10:0]] <= vram_d[6:0];
		else
			att[vram_a[10:0]] <= vram_d[7];
	end

reg [9:0] x = 10'd0;          // 0..639
reg [8:0] y = 9'd0;           // 0..311
reg [2:0] pt = 3'd0;          // the point in the character, 0..5
reg [5:0] col = 6'd0;
reg [3:0] line = 4'd0;        // 0..8
reg [4:0] row = 5'd0;
wire xin = x >= 10'd64 && x < 10'd448;
wire yin = y >= 9'd6 && y < 9'd294;

reg [6:0] chr_q = 7'd0;
reg att_q = 1'b0;
always @(posedge clk) begin
	chr_q <= chr[{ row, col }];
	att_q <= col != 6'd63 && att[{ row, col + 6'd1 }];
end
assign font_addr = { chr_q, line[2:0] };

always @(posedge clk)
	if (ce_pix) begin
		// the point of the current place (its character and font read since the last ce_pix)
		pix <= xin && yin && line != 4'd8 && (font_q[3'd5 - pt] ^ att_q);
		hblank <= x >= 10'd512;
		vblank <= y >= 9'd300;
		// the next place
		if (x == 10'd639) begin
			x <= 10'd0;
			if (y == 9'd311)
				y <= 9'd0;
			else
				y <= y + 9'd1;
			if (y == 9'd5) begin
				line <= 4'd0;
				row <= 5'd0;
			end
			else if (yin) begin
				if (line == 4'd8) begin
					line <= 4'd0;
					row <= row + 5'd1;
				end
				else
					line <= line + 4'd1;
			end
		end
		else
			x <= x + 10'd1;
		if (x == 10'd63) begin
			pt <= 3'd0;
			col <= 6'd0;
		end
		else if (xin) begin
			if (pt == 3'd5) begin
				pt <= 3'd0;
				col <= col + 6'd1;
			end
			else
				pt <= pt + 3'd1;
		end
	end

endmodule
