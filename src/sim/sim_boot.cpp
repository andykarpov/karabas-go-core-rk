// sim_boot: tb_boot (rk_system + SRAM model) under verilator (after the sim_boot of core-specialist).
//
//   sim_boot --rom FILE:ADDR ... [--model N] [--turbo] [--color] [--noauto] [--ms N] [--file MS:SLOT:FILE ...]
//            [--key MS:B,B,.. ...] [--ppm OUT] [--frame OUT] [--expect ADDR:VAL ...] [--dump ADDR:N]
//
// The ROMs go in through the ROM loader (one byte every 12 clocks), then the machine runs N ms of its
// time. --file loads a file through the FL port at that time (as the mcu: one byte every 12 clocks, the
// machine in reset meanwhile). --key sends PS/2 set 2 bytes (hex) at that time, 50 us apart. --ppm
// writes the frame buffer (512 x 300, 4 bits a point at 300000 of the SRAM) as an image; --frame
// captures the next whole frame of the video output (800 x 600). --expect checks a byte of the SRAM (a
// byte address of rk_sram) at the end; --dump prints bytes of the SRAM. TRACE=N prints N CPU reads (from TRACE_FROM ms).
// --wav OUT writes the audio sampled at 48 kHz (every 833 clocks), mono 16-bit.
// --model: 0 the RK86, 1 the Mikrosha, 2 the Apogey; --switch MS:N changes it at that time under a reset of
// 255 clocks, as the top does. "sound edges" counts the changes of the audio.
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

static std::vector<uint8_t> readfile(const char *name) {
	std::vector<uint8_t> d;
	FILE *f = fopen(name, "rb");
	if (!f) { perror(name); exit(2); }
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	return d;
}

struct Ev { uint64_t at; int kind; int slot; std::string file; std::vector<uint8_t> keys; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_boot;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::vector<std::pair<uint32_t, int>> expects, dumps;
	std::vector<Ev> evs;
	int ms = 1000, model = 0;
	const char *ppm = nullptr, *frame = nullptr, *wav = nullptr;
	std::vector<int16_t> pcm;
	bool turbo = false, color = false, autorun = true;
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
		else if (!strcmp(argv[i], "--dump")) { std::string d = argv[++i]; size_t c = d.find(':'); dumps.push_back({ (uint32_t)strtoul(d.c_str(), nullptr, 0), atoi(d.c_str() + c + 1) }); }
		else if (!strcmp(argv[i], "--file")) {
			std::string s = argv[++i];
			size_t c1 = s.find(':'), c2 = s.find(':', c1 + 1);
			evs.push_back({ strtoull(s.c_str(), nullptr, 0) * 40000, 0, atoi(s.c_str() + c1 + 1), s.substr(c2 + 1), {} });
		}
		else if (!strcmp(argv[i], "--key")) {
			std::string s = argv[++i];
			Ev e { strtoull(s.c_str(), nullptr, 0) * 40000, 1, 0, "", {} };
			const char *p = strchr(s.c_str(), ':') + 1;
			while (*p) { e.keys.push_back(strtoul(p, (char **)&p, 16)); if (*p == ',') p++; }
			evs.push_back(e);
		}
		else if (!strcmp(argv[i], "--model")) model = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--switch")) {
			std::string s = argv[++i];
			evs.push_back({ strtoull(s.c_str(), nullptr, 0) * 40000, 2, atoi(s.c_str() + s.find(':') + 1), "", {} });
		}
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--color")) color = true;
		else if (!strcmp(argv[i], "--noauto")) autorun = false;
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else if (!strcmp(argv[i], "--wav")) wav = argv[++i];
		else if (!strcmp(argv[i], "--frame")) frame = argv[++i];
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->turbo = turbo; top->color = color; top->autorun = autorun; top->model = model;
	top->reset = 1; top->rom_active = 0; top->rom_wr = 0; top->file_active = 0; top->file_wr = 0;
	top->kb_scancode = 0; top->kb_scancode_upd = 0;
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0; top->rom_active = 1;
	for (auto &r : roms) {
		std::vector<uint8_t> d = readfile(r.first.c_str());
		uint32_t a = r.second;
		for (uint8_t c : d) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 11; i++) tick();
		}
	}
	for (int i = 0; i < 40; i++) tick();
	top->rom_active = 0;
	uint64_t t0 = clks, end = t0 + (uint64_t)ms * 40000;
	int beeps = 0, prev = 0, prd = 0, snds = 0, psnd = 0;
	int trace = getenv("TRACE") ? atoi(getenv("TRACE")) : 0;
	uint64_t trace_from = getenv("TRACE_FROM") ? strtoull(getenv("TRACE_FROM"), nullptr, 0) * 40000 : 0;   // ms
	while (clks < end) {
		for (auto &e : evs) {
			if (e.at == UINT64_MAX || clks - t0 < e.at) continue;
			if (e.kind == 0) {
				std::vector<uint8_t> d = readfile(e.file.c_str());
				top->file_slot = e.slot; top->file_active = 1;
				for (int i = 0; i < 40; i++) tick();
				for (size_t k = 0; k < d.size(); k++) {
					top->file_addr = k; top->file_data = d[k]; top->file_wr = 1; tick();
					top->file_wr = 0;
					for (int i = 0; i < 11; i++) tick();
				}
				for (int i = 0; i < 40; i++) tick();
				top->file_active = 0;
			}
			else if (e.kind == 2) {
				top->model = e.slot; model = e.slot; top->reset = 1;
				for (int i = 0; i < 255; i++) tick();
				top->reset = 0;
			}
			else
				for (uint8_t k : e.keys) {
					top->kb_scancode = k; top->kb_scancode_upd ^= 1;
					for (int i = 0; i < 2000; i++) tick();
				}
			e.at = UINT64_MAX;
		}
		tick();
		if (top->beep != prev) beeps++;
		prev = top->beep;
		if (top->audio != psnd) snds++;
		psnd = top->audio;
		if (wav && (clks - t0) % 833 == 0) pcm.push_back((int16_t)(top->audio >> 1));
		if (trace > 0 && top->dbg_rd && !prd && clks - t0 >= trace_from) { printf("rd %04x\n", top->dbg_a); trace--; }
		prd = top->dbg_rd;
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
	static const char *names[] = { "RK86", "Mikrosha", "Apogey", "Partner", "Mikro-80", "Mikro-80RK", "?", "?" };
	printf("%s %s %d ms: beep edges %d sound edges %d frame sum %08x lit %u\n", names[model & 7], turbo ? "turbo" : model >= 4 ? "2MHz" : "1.78MHz", ms, beeps, snds, sum, lit);
	for (auto &d : dumps) {
		for (int i = 0; i < d.second; i++) { if (i % 32 == 0) printf("\n%06x:", d.first + i); printf(" %02x", peek(d.first + i)); }
		printf("\n");
	}
	int err = 0;
	for (auto &e : expects) {
		uint8_t v = peek(e.first);
		if (v != e.second) { printf("expect %06x: %02x, not %02x\n", e.first, v, e.second); err = 1; }
	}
	if (wav) {
		FILE *f = fopen(wav, "wb");
		uint32_t n = pcm.size() * 2, r = 48000, br = 96000, h = 16, sz = 36 + n;
		uint16_t pcmf = 1, ch = 1, al = 2, bits = 16;
		fwrite("RIFF", 1, 4, f); fwrite(&sz, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&h, 4, 1, f);
		fwrite(&pcmf, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&r, 4, 1, f); fwrite(&br, 4, 1, f);
		fwrite(&al, 2, 1, f); fwrite(&bits, 2, 1, f); fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f);
		fwrite(pcm.data(), 2, pcm.size(), f);
		fclose(f);
	}
	if (ppm) {
		FILE *f = fopen(ppm, "wb");
		fprintf(f, "P6\n512 300\n255\n");
		for (int i = 0; i < 512 * 300; i++) {
			uint8_t v = (fb[i] & 8) ? ((fb[i] & 4) ? 255 : 192) : 0;
			uint8_t p[3] = { v, v, v };
			if (color && (fb[i] & 8)) {   // the Apogey: R = !hilight, G = !gattr1, B = !gattr0
				p[0] = (fb[i] & 4) ? 0 : 255; p[1] = (fb[i] & 2) ? 0 : 255; p[2] = (fb[i] & 1) ? 0 : 255;
			}
			if (model == 3) {   // the Partner: { 0, p, p, p } the text, { 1, R, G, B } the MCPG
				uint8_t t = (fb[i] & 1) ? 192 : 0;
				p[0] = (fb[i] & 8) ? ((fb[i] & 4) ? 255 : 0) : t;
				p[1] = (fb[i] & 8) ? ((fb[i] & 2) ? 255 : 0) : t;
				p[2] = (fb[i] & 8) ? ((fb[i] & 1) ? 255 : 0) : t;
			}
			fwrite(p, 1, 3, f);
		}
		fclose(f);
	}
	if (frame) {
		// the frame starts after the trailing edge of vsync; a line is the run of de
		while (!top->vs) tick();
		while (top->vs) tick();
		std::vector<uint8_t> img(800 * 600 * 3, 0);
		int y = -1, x = 0, de_d = 0;
		while (y < 600) {
			tick();
			if (top->de && !de_d) { y++; x = 0; }
			if (top->de && y >= 0 && y < 600 && x < 800) {
				uint8_t *p = &img[(y * 800 + x) * 3];
				p[0] = top->rgb >> 16; p[1] = top->rgb >> 8; p[2] = top->rgb;
				x++;
			}
			if (!top->de && de_d && y == 599) break;
			de_d = top->de;
		}
		FILE *f = fopen(frame, "wb");
		fprintf(f, "P6\n800 600\n255\n");
		fwrite(img.data(), 1, img.size(), f);
		fclose(f);
	}
	delete top;
	return err;
}
