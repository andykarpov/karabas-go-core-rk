# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A new core of the Soviet home computers of the Radio-86RK family (KR580VM80A with the KR580VG75 CRT controller and the KR580VT57 DMA): Radio-86RK, Mikrosha, Apogey BK-01, Partner 01.01 (memory maps, its colour module MCPG), and Mikro-80 (its own text screen), one core with the model in the OSD, for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). It replaces the old `karabas-go-core-rk86`.

Status: phases 0-4 merged (RK86, Mikrosha, Apogey, Partner with the MCPG, Mikro-80 on the Mini G); phase 5 (SDOS of the RK86, the Go and Mini tops, the release) in progress. Docs, in Russian: `docs/PLAN.md` (research, decisions, phases), `docs/HARDWARE.md` (memory maps and ports), `docs/BACKLOG.md`. Follow the phases; record a changed decision in PLAN.md.

All file work goes through the firmware (OSD, `FL` / `F` items, burst): no loader or soft CPU in the core. **A frame buffer in the SRAM** (the user's decision, 2026-11-07): the VG75 and VT57 of Apogee_MiSTer run at the native timing (the DMA takes cycles from the CPU), their point stream is written into a 512 x 300 x 4-bit window in the SRAM, and the output reads it at a standard video timing (800 x 600 at 60 Hz) whatever the program sets the VG75 to. References: Emu80 v4 (`vpyk/emu80v4`, GPL-3) for the behaviour; Apogee_MiSTer (Tselikov, Sorgelig; BSD-2, `k580vi53` GPL v3) as the main source for the VG75 / VT57 / keyboard; Foxlisic/Radio86Board (MIT) for a VG75 that reads memory itself. The core is GPL v3 (`LICENSE`).

The template is `../karabas-go-core-specialist` (and `../karabas-go-core-orion128`): modules, tops, Makefile, sim harness, `spec_sd` for SDOS.

## Layout

- `src/Makefile`: the ISE flow, as in core-specialist. `src/karabas_<board>.{prj,xst,ut,ucf}`: its inputs (from core-specialist; Mini G maps with `-t 3`).
- `src/make_core.py`: a symlink to `../../karabas-go-tools/make_core/make_core.py`. `src/tools/check_osd.py`: the slot check of `make core`.
- `src/core.json`: the core file description (kgo2, `rk.kg`).
- `src/rtl/karabas_{go,mini,minig}_top.v`: the board tops (Go: VGA; Mini: sigma-delta; Mini G: HDMI + PCM5102).
- `src/rtl/rk/`: `rk_system.v` (the machine, the frame buffer writer), `rk_sd.v` (the SD adapter of SDOS, spec_sd of core-specialist), `rk_cpu.v` (vm80a at 1.78 / 2 MHz with a fractional divider, HOLD / HLDA, ce_f2 for the DMA), `rk_sram.v` (spec_sram), `rk_ppi.v` (spec_ppi). `src/rtl/apogee/`: `k580vg75.v` (sv2v of Apogee_MiSTer, the font moved out), `k580vt57.v` (sync reset), `LICENSE.TXT`. `src/rtl/vm80a/`: upstream.
- `src/roms/`: `rk86.rom` (SRAM 100000), `sgr.bin` (the font, 1F0000), from Emu80; the fonts of Emu80 are inverted (written inverted into the font BRAM).
- `src/sim/run_boot.sh`: verilator, all models (header of the script lists the tests); `EMU80=<emu80v4 checkout>` adds the Partner games and the MCPG, `FULL=1` the Apogey ROM disk shell, `SIM_BUILD=DIR` another build directory; `sim_boot --sd IMG` mounts an SD image (F slot 3) on a model of the file mounter. `sim_boot` `--rom`, `--model`, `--ms`, `--file MS:SLOT:FILE`, `--key`, `--switch MS:MODEL`, `--ppm` (the frame buffer, decoded per model), `--frame`, `--wav`, `--expect`, `--dump ADDR:N`, `TRACE=N` (CPU reads). `src/rk.prj`, `rk.xst`: the machine alone, `make rk-xst`.
- `modules/`: the git submodule [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules). Clone with `--recursive`.

## Rules of the core

The rules of core-specialist apply (its `CLAUDE.md`): one 40 MHz clock with enables, standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, SDRAM idle, OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, FL slots 0..7 only (one array with the F slots), the TIG from clk_sys to clk_hdmi only while the HDMI runs on clk_pix, Verilog-2001 for XST, imported code marked `// karabas:`.

- ROMs are not ours: only those the user allowed go into the repo and the `.kg`.
- **Ask the user before every check on the board** (and the HDMI capture), even inside a phase. Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
