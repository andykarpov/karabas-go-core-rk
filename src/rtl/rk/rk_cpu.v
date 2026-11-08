`timescale 1ns / 1ps
`default_nettype wire

/*
 rk_cpu.v (spec_cpu.v of karabas-go-core-specialist, the KR580VM80A only)

 KR580VM80A (vm80a, a cycle accurate model) on the clock of 40 MHz. The state length by fast:
 0: 1 777 777 Hz, the 16 MHz / 9 of the Radio-86RK, Mikrosha and Apogey: 22.5 clocks, made by
    states of 22 and 23 clocks in turn;
 1: 2 MHz (Mikro-80, Partner): 20 clocks.
 turbo halves them. F1 and F2 do not overlap, with a gap of one clock between them, as on a real 8080.
 ce_f2 is one clock at the start of F2: the clock enable of the KR580VT57 (as Apogee_MiSTer).

 hold / hlda are the HOLD / HLDA pins: the DMA of the VG75 takes the bus between the cycles of the CPU.
 ready (the READY pin) stops the CPU for a slow device. fetch: the status word of the cycle (D5, M1)
 says that it fetches an opcode; it holds until the next SYNC. io: the cycle is an IN or OUT (D6, D4 of
 the status; the 8080 shows them as a read or a write of { n, n }), stack: a cycle of the stack (D2;
 the RAM disk of the Mikro-80 takes them). Change fast and turbo at any time: they
 take effect at the start of the next state.
*/

module rk_cpu (
	input wire clk,
	input wire reset,
	input wire fast,             // 2 MHz instead of 1.78
	input wire turbo,
	input wire hold,
	output wire hlda,
	input wire ready,

	output wire [15:0] addr,
	output wire [7:0] dout,
	input wire [7:0] din,
	output wire mem_rd,
	output wire mem_wr,
	output reg fetch = 1'b0,
	output reg io = 1'b0,
	output reg stack = 1'b0,
	input wire intr,             // the INT pin
	output reg inta = 1'b0,      // the cycle acknowledges an interrupt (D0 of the status): put the opcode (RST n) on din
	output wire inte,
	output reg ce_f2 = 1'b0
);

reg [4:0] cnt = 5'd0;
reg odd = 1'b0;              // 1.78 MHz: the state of 23 clocks
reg [4:0] last = 5'd21;
reg f1 = 1'b0, f2 = 1'b0;
always @(posedge clk) begin
	if (cnt == last) begin
		cnt <= 5'd0;
		odd <= ~odd;
		// the next state: 2 MHz 20 (turbo 10), 1.78 MHz 22 / 23 (turbo 11 / 12) clocks
		last <= fast ? (turbo ? 5'd9 : 5'd19) : turbo ? (odd ? 5'd10 : 5'd11) : (odd ? 5'd21 : 5'd22);
	end
	else
		cnt <= cnt + 5'd1;
	f1 <= cnt <= 5'd3;
	f2 <= cnt >= 5'd5 && cnt < last;
	ce_f2 <= cnt == 5'd4;
end

wire dbin, wr_n, sync;

vm80a_core cpu80 (
	.pin_clk(clk),
	.pin_f1(f1),
	.pin_f2(f2),
	.pin_reset(reset),
	.pin_a(addr),
	.pin_dout(dout),
	.pin_din(din),
	.pin_aena(),
	.pin_dena(),
	.pin_hold(hold),
	.pin_hlda(hlda),
	.pin_ready(ready),
	.pin_wait(),
	.pin_int(intr),
	.pin_inte(inte),
	.pin_sync(sync),
	.pin_dbin(dbin),
	.pin_wr_n(wr_n)
);

always @(posedge clk)
	if (sync) begin
		fetch <= dout[5];
		io <= dout[6] | dout[4];
		stack <= dout[2];
		inta <= dout[0];
	end

assign mem_rd = dbin;
assign mem_wr = ~wr_n;

endmodule
