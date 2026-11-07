// sim_boot: tb_boot (rk_system + SRAM model) under verilator (after the sim_boot of core-specialist).
//
//   sim_boot --rom FILE:ADDR ... [--turbo] [--ms N] [--ppm OUT] [--expect ADDR:VAL ...]
//
// The ROMs go in through the ROM loader (one byte every 12 clocks). The machine then runs N ms of its
// time. --ppm writes the frame buffer (512 x 300, 4 bits a point at 300000 of the SRAM: point, highlight,
// colour) as an image, a point white, a highlighted one bright. Prints a checksum of the frame buffer and
// how many points are lit. --expect checks a byte of the SRAM (a byte address of rk_sram) at the end.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include "Vtb_boot.h"
#include "verilated.h"

static Vtb_boot *top;
static uint64_t clks = 0;

static void tick() {
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clks++;
}

static uint8_t peek(uint32_t a) {
	top->dbg_addr = a; top->eval();
	return top->dbg_q;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_boot;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::vector<std::pair<uint32_t, int>> expects, dumps;
	int ms = 1000;
	const char *ppm = nullptr;
	bool turbo = false;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--rom") || !strcmp(argv[i], "--expect")) {
			bool rom = argv[i][2] == 'r';
			std::string s = argv[++i];
			size_t c = s.rfind(':');
			if (rom)
				roms.push_back({ s.substr(0, c), (uint32_t)strtoul(s.c_str() + c + 1, nullptr, 0) });
			else
				expects.push_back({ (uint32_t)strtoul(s.c_str(), nullptr, 0), (int)strtol(s.c_str() + c + 1, nullptr, 0) });
		}
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else if (!strcmp(argv[i], "--dump")) { std::string d = argv[++i]; size_t c = d.find(':'); dumps.push_back({ (uint32_t)strtoul(d.c_str(), nullptr, 0), atoi(d.c_str() + c + 1) }); }
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->turbo = turbo;
	top->reset = 1; top->rom_active = 0; top->rom_wr = 0;
	top->kb_pb_i = 0xFF; top->kb_pc_i = 7;
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0; top->rom_active = 1;
	for (auto &r : roms) {
		FILE *f = fopen(r.first.c_str(), "rb");
		if (!f) { perror(r.first.c_str()); return 2; }
		int c; uint32_t a = r.second;
		while ((c = fgetc(f)) != EOF) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 11; i++) tick();
		}
		fclose(f);
	}
	for (int i = 0; i < 40; i++) tick();
	top->rom_active = 0;
	uint64_t end = clks + (uint64_t)ms * 40000;
	int beeps = 0, prev = 0;
	int trace = getenv("TRACE") ? atoi(getenv("TRACE")) : 0;
	int prd = 0, lastdi = 0;
	while (clks < end) {
		tick();
		if (trace > 0 && !top->dbg_rd && prd) { printf("rd %04x di %02x saddr %06x rom %d\n", top->dbg_a, top->dbg_din, top->dbg_saddr, top->dbg_rom); trace--; }
		if (top->dbg_rd) { lastdi = top->dbg_din; }
		prd = top->dbg_rd;
		if (top->beep && !prev) beeps++;
		prev = top->beep;
	}
	uint32_t sum = 0, lit = 0;
	std::vector<uint8_t> fb(512 * 300);
	for (int y = 0; y < 300; y++)
		for (int x = 0; x < 512; x += 2) {
			uint8_t b = peek(0x300000 + y * 256 + x / 2);
			fb[y * 512 + x] = b & 15;
			fb[y * 512 + x + 1] = b >> 4;
			sum = sum * 31 + b;
			lit += ((b >> 3) & 1) + ((b >> 7) & 1);
		}
	printf("RK86 %s %d ms: beep edges %d frame sum %08x lit %u\n", turbo ? "turbo" : "1.78MHz", ms, beeps, sum, lit);
	for (auto &d : dumps) {
		for (int i = 0; i < d.second; i++) { if (i % 32 == 0) printf("\n%06x:", d.first + i); printf(" %02x", peek(d.first + i)); }
		printf("\n");
	}
	int err = 0;
	for (auto &e : expects) {
		uint8_t v = peek(e.first);
		if (v != e.second) { printf("expect %06x: %02x, not %02x\n", e.first, v, e.second); err = 1; }
	}
	if (ppm) {
		FILE *f = fopen(ppm, "wb");
		fprintf(f, "P6\n512 300\n255\n");
		for (int i = 0; i < 512 * 300; i++) {
			uint8_t v = (fb[i] & 8) ? ((fb[i] & 4) ? 255 : 192) : 0;
			uint8_t p[3] = { v, v, v };
			fwrite(p, 1, 3, f);
		}
		fclose(f);
	}
	delete top;
	return err;
}
