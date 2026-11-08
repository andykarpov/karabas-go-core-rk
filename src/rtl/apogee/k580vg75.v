`default_nettype wire   // karabas: KF8253 before it in the project leaves none
// Imported from MiSTer-devel/Apogee_MiSTer (rtl/k580vg75.sv), converted to Verilog by sv2v for
// karabas-go-core-rk; changes are marked karabas (in the source before the conversion: the font ROM
// moved out to the ports font_addr / font_data). License: rtl/apogee/LICENSE.TXT (modified BSD).
module k580vg75 (
	clk_sys,
	ce_pix,
	iaddr,
	idata,
	odata,
	iwe_n,
	ird_n,
	dack,
	drq,
	irq,
	vrtc,
	hrtc,
	vblank,
	hblank,
	pix,
	hilight,
	gattr,
	charset,
	scr_shift,
	font_addr,
	font_data
);
	input clk_sys;
	input ce_pix;
	input iaddr;
	input [7:0] idata;
	output wire [7:0] odata;
	input iwe_n;
	input ird_n;
	input dack;
	output reg drq;
	output reg irq;
	output reg vrtc;
	output reg hrtc;
	output reg vblank;
	output reg hblank;
	output wire pix;
	output wire hilight;
	output wire [1:0] gattr;
	input charset;
	input [4:0] scr_shift;
	output wire [10:0] font_addr;
	input [7:0] font_data;
	parameter CHAR_WIDTH = 5;
	reg [7:0] init2;
	wire [3:0] charheight = init2[3:0];
	reg [3:0] chline;
	reg [7:0] init3;
	wire linemode = init3[7];
	wire [3:0] line = (linemode == 0 ? chline : (chline == 0 ? charheight : chline + 4'b1111));
	reg [7:0] ochar;
	assign font_addr = {charset, ochar[6:0], line[2:0]};
	wire [7:0] fdata;
	assign fdata = font_data;
	reg du;
	reg enable;
	reg err;
	reg fo;
	reg inte;
	assign odata = {1'b0, inte, irq, 1'b0, err, enable, du, fo};
	reg [5:0] attr2;
	assign gattr = attr2[3:2];
	assign hilight = attr2[0];
	reg blank;
	reg [7:0] cdata;
	assign pix = ((hrtc | blank) | vrtc ? 1'b0 : cdata[CHAR_WIDTH]);
	reg [7:0] init0;
	reg [7:0] init1;
	reg [6:0] curx;
	reg [5:0] cury;
	wire [6:0] maxx = init0[6:0];
	wire [6:0] maxy = {1'b0, init1[5:0]};
	wire [6:0] hrcnt = {2'd0, init3[3:0], 1'b1};
	wire [6:0] vrcnt = {5'd0, init1[7:6]};
	wire [3:0] underline = init2[7:4];
	wire fillattr = init3[6];
	wire curblink = init3[5];
	wire curtype = init3[4];
	reg [5:0] attr;
	reg [7:0] opos;
	reg [6:0] ypos;
	reg [4:0] frame;
	wire vcur = (((opos == {1'b0, curx}) && cury) && (ypos == cury)) && (frame[3] | curblink);
	wire lten = (attr[5] || (curtype && vcur)) && (chline == underline);
	wire vsp = (((attr[1] && frame[4]) || ((underline[3] == 1'b1) && ((chline == 0) || (chline == charheight)))) || !enable) || (ypos == 0);
	wire rvv = attr[4] ^ (((curtype == 0) && vcur) && (chline <= underline));
	wire [47:0] bs_table = 48'h0073d77e7bf7;
	reg [511:0] gchar = 512'b11110000100000000000000000001111100000001000000000000000100000001111000000000000000000001000111110000000000000000000000000001111111100001000000000000000100011111000000010000000000000001000000011110000100000000000000010001111111100000000000000000000000011111111000000000000000000001000000010000000100000000000000010001111111100001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;
	wire [7:0] gdata = (ochar[1] && frame[4] ? 8'd0 : gchar[(63 - {ochar[5:2], chline > underline, chline == underline}) * 8+:8]);
	// karabas: h_shift / v_shift moved out of the block with their initial value: sv2v made the
	// initialisers of the SV source blocking assignments in every clock, which XST refuses
	reg [3:0] h_shift = 4'd8;
	reg [3:0] v_shift = 4'd8;
	always @(posedge clk_sys) begin : sv2v_autoblock_1
		reg [5:0] exattr;
		reg [6:0] ipos;
		reg [3:0] iposf;
		reg [3:0] oposf;
		reg [7:0] buff [0:255];
		reg [6:0] fifo [0:31];
		reg [2:0] pstate;
		reg eos;
		reg [6:0] xpos;
		reg [6:0] xpos2;
		reg exwe_n;
		reg exrd_n;
		reg exdack;
		reg istate;
		reg dmae;
		reg [2:0] dma_bs;
		reg [1:0] dma_bc;
		reg [5:0] cur_bs;
		reg [3:0] cur_bc;
		reg [6:0] ypos2;
		reg exshift;
		reg [7:0] obuf;
		reg vspfe;
		reg lineff;
		reg [3:0] dot;
		exrd_n <= ird_n;
		if (ird_n & ~exrd_n)
			{irq, err, du, fo} <= 0;
		exwe_n <= iwe_n;
		if (~iwe_n & exwe_n) begin
			if (iaddr)
				case (idata[7:5])
					0: {enable, inte, pstate} <= 1;
					1: {enable, inte, dma_bs, dma_bc} <= {2'b11, idata[4:0]};
					2: enable <= 0;
					3: pstate <= 5;
					4: pstate <= 5;
					5: inte <= 1;
					6: inte <= 0;
					7:
						;
				endcase
			else
				case (pstate)
					1: {init0, pstate} <= {idata, 3'd2};
					2: {init1, pstate} <= {idata, 3'd3};
					3: {init2, pstate} <= {idata, 3'd4};
					4: {init3, pstate} <= {idata, 3'd0};
					5: {curx, pstate} <= {idata[6:0] + 1'b1, 3'd6};
					6: {cury, pstate} <= {idata[5:0] + 1'b1, 3'd0};
					default: {err, pstate} <= 4'h8;
				endcase
		end
		exdack <= dack;
		if (~exdack & dack) begin
			if (istate) begin
				iposf <= iposf + 1'b1;
				istate <= 0;
				if (!(~iposf))
					fo <= 1;
			end
			else begin
				if (&{idata[7:4], idata[0]}) begin
					ipos <= 7'h7f;
					drq <= 0;
					if (idata[1])
						dmae <= 0;
				end
				else begin
					ipos <= ipos + 1'b1;
					if (ipos >= maxx)
						drq <= 0;
					else if (bs_table[(7 - dma_bs) * 6+:6]) begin
						cur_bc <= cur_bc - 1'd1;
						if (cur_bc == 1) begin
							drq <= 0;
							cur_bs <= bs_table[(7 - dma_bs) * 6+:6];
						end
					end
				end
				istate <= (idata[7:6] == 2'b10 ? ~fillattr : 1'b0);
			end
			case (istate)
				0: buff[{lineff, ipos}] <= idata;
				1: fifo[{lineff, iposf}] <= idata[6:0];
			endcase
		end
		if (ce_pix) begin
			cdata <= {cdata[6:0], 1'b0};
			dot <= dot + 1'b1;
			if (dot == CHAR_WIDTH)
				dot <= 0;
			if (!dot) begin
				if (cur_bs) begin
					cur_bs <= cur_bs - 1'd1;
					if (cur_bs == 1) begin
						cur_bc <= 4'd1 << dma_bc;
						drq <= (ipos < maxx) & dmae;
					end
				end
				xpos2 <= xpos2 + 1'd1;
				if (xpos == ((hrcnt + maxx) + 1'd1)) begin
					xpos <= 0;
					if (chline == charheight) begin
						if (ypos >= ((vrcnt + maxy) + 1'd1)) begin
							ypos <= 0;
							eos <= 0;
							vspfe <= 0;
							attr <= 0;
							exattr <= 0;
							dmae <= enable;
							drq <= enable;
							frame <= frame + 1'b1;
							ypos2 <= ypos2 + 1'b1;
						end
						else begin
							exattr <= attr;
							ypos <= ypos + 1'b1;
							ypos2 <= ypos2 + 1'b1;
							if (ypos == 4'd10)
								ypos2 <= ypos + 1'b1;
							drq <= (ypos < maxy) & dmae;
							if (ypos == maxy)
								irq <= 1;
							if ((ypos > maxy) | eos)
								vspfe <= 1;
							if (drq)
								{dmae, drq, vspfe, du} <= 4'b0011;
						end
						chline <= 0;
						iposf <= 0;
						ipos <= 0;
						lineff <= ~lineff;
						cur_bs <= 0;
						cur_bc <= 4'd1 << dma_bc;
					end
					else begin
						chline <= chline + 1'b1;
						attr <= exattr;
					end
					oposf <= 0;
					opos <= 0;
				end
				else begin
					if (ypos != 0) begin
						if (~obuf[7:4])
							opos <= opos + 1'b1;
						else if (obuf[1])
							eos <= 1;
						if (opos > maxx)
							ochar <= 0;
						else if (obuf[7:6] == 2'b10) begin
							if (fillattr)
								ochar <= 0;
							else begin
								ochar <= {1'b0, fifo[{~lineff, oposf}]};
								oposf <= oposf + 1'b1;
							end
							attr <= obuf[5:0];
						end
						else
							ochar <= (~obuf[7:4] ? obuf : 8'd0);
					end
					xpos <= xpos + 1'd1;
					if (!xpos2)
						xpos2 <= xpos + 1'd1;
				end
				exshift <= |scr_shift;
				if (~exshift & |scr_shift)
					case (scr_shift)
						5'b00001: h_shift <= h_shift + ~&h_shift;
						5'b00010: h_shift <= h_shift - |h_shift;
						5'b00100: v_shift <= v_shift + ~&v_shift;
						5'b01000: v_shift <= v_shift - |v_shift;
						5'b10000: {h_shift, v_shift} <= 8'h88;
						default:
							;
					endcase
				if (xpos2 == ((maxx + h_shift) - (4'd6 + 4'd6))) begin
					hblank <= 1;
					if ((ypos2 == ((maxy + v_shift) - (4'd6 + 4'd1))) && (chline == charheight))
						vblank <= 1;
				end
				if (xpos2 == (((maxx + hrcnt) + h_shift) - (4'd6 - 4'd8))) begin
					hblank <= 0;
					if ((ypos2 == (((maxy + v_shift) + (1'd1 - 4'd6)) + 4'd1)) && (chline == charheight))
						vblank <= 0;
				end
				if (xpos2 == ((maxx + h_shift) - 4'd6)) begin
					hrtc <= 1;
					blank <= 1;
					if ((ypos2 == ((maxy + v_shift) - 4'd6)) && (chline == charheight))
						vrtc <= 1;
				end
				if (xpos2 == (((maxx + hrcnt) + h_shift) + (2'd3 - 4'd6)))
					blank <= 0;
				if (xpos2 == (((maxx + hrcnt) + h_shift) - 4'd6)) begin
					hrtc <= 0;
					if ((ypos2 == ((maxy + v_shift) + (1'd1 - 4'd6))) && (chline == charheight))
						vrtc <= 0;
				end
				cdata <= (vspfe ? 8'd0 : {8 {rvv}} ^ (ochar[7] ? gdata : (lten ? 8'hff : (vsp ? 8'b00000000 : fdata))));
				attr2 <= (ochar[7] ? {attr[4:2], 1'b0, ochar[0]} : attr);
			end
			if (dot == 1)
				obuf <= buff[{~lineff, opos[6:0]}];
		end
	end
endmodule
