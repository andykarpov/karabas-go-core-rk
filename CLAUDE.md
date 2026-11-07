# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A new core of the Soviet home computers of the Radio-86RK family (KR580VM80A with the KR580VG75 CRT controller and the KR580VT57 DMA): Radio-86RK, Mikrosha, Apogey BK-01, and Mikro-80 (its own text screen), one core with the model in the OSD, for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). It replaces the old `karabas-go-core-rk86`.

Status: plan and build skeleton, no RTL yet. Docs, in Russian: `docs/PLAN.md` (research, decisions, phases), `docs/HARDWARE.md` (memory maps and ports), `docs/BACKLOG.md`. Follow the phases; record a changed decision in PLAN.md.

All file work goes through the firmware (OSD, `FL` / `F` items, burst): no loader or soft CPU in the core. **No frame buffer**: the screen goes out in a standard video mode straight from the SRAM; the VG75 is split into the CPU side (registers, status, IRQ, the DMA cycles taken from the CPU at the native timing) and a renderer that reads the character rows from the SRAM by the VG75 parameters and the DMA address. References: Emu80 v4 (`vpyk/emu80v4`, GPL-3) for the behaviour; Apogee_MiSTer (Tselikov, Sorgelig; BSD-2, `k580vi53` GPL v3) as the main source for the VG75 / VT57 / keyboard; Foxlisic/Radio86Board (MIT) for a VG75 that reads memory itself. The core is GPL v3 (`LICENSE`).

The template is `../karabas-go-core-specialist` (and `../karabas-go-core-orion128`): modules, tops, Makefile, sim harness, `spec_sd` for SDOS.

## Layout

- `src/Makefile`: the ISE flow, as in core-specialist. `src/karabas_<board>.{prj,xst,ut,ucf}`: its inputs (from core-specialist; Mini G maps with `-t 3`).
- `src/make_core.py`: a symlink to `../../karabas-go-tools/make_core/make_core.py`. `src/tools/check_osd.py`: the slot check of `make core`.
- `src/core.json`: the core file description (kgo2, `rk.kg`).
- `modules/`: the git submodule [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules). Clone with `--recursive`.

## Rules of the core

The rules of core-specialist apply (its `CLAUDE.md`): one 40 MHz clock with enables, standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, SDRAM idle, OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, FL slots 0..7 only (one array with the F slots), the TIG from clk_sys to clk_hdmi only while the HDMI runs on clk_pix, Verilog-2001 for XST, imported code marked `// karabas:`.

- ROMs are not ours: only those the user allowed go into the repo and the `.kg`.
- **Ask the user before every check on the board** (and the HDMI capture), even inside a phase. Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
