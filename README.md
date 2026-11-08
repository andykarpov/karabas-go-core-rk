# RK family core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The Soviet home computers of the **Radio-86RK** family for the Karabas Go family of boards (Xilinx
Spartan-6 XC6SLX25): the **Radio-86RK** (*Radio* magazine, 1986), its industrial relatives the
**Mikrosha**, the **Apogey BK-01** and the **Partner 01.01** (with its colour module MCPG), and the
**Mikro-80** (*Radio*, 1983), the forerunner of them all.
One core, the model is chosen in the OSD. All file work (programs, ROM disks) goes through the OSD and
the file browser of the board firmware: the core has no loader of its own. The core is to replace the
old [karabas-go-core-rk86](https://github.com/andykarpov/karabas-go-core-rk86).

| Board | Video | Audio |
|---|---|---|
| Karabas Mini G | HDMI with sound | HDMI, PCM5102 DAC |
| Karabas Go | VGA | PCM5102 DAC, the beeper of the board (the beeper of the machine) |
| Karabas Mini | HDMI with sound | HDMI, sigma-delta |

The core file is `src/rk.kg`.

**State:** build 26110807. The Radio-86RK (with SDOS), the Mikrosha, the Apogey, the Partner 01.01 and
the Mikro-80 run on the Mini G; the Go and the Mini are built, not tried on a board yet (see
[What is tested](#what-is-tested)). The plan and the next options are in
[docs/PLAN.md](docs/PLAN.md) (Russian).

## Contents

- [The machines](#the-machines)
- [What the core does](#what-the-core-does)
- [Getting started](#getting-started)
- [Where to get software](#where-to-get-software)
- [The SD card](#the-sd-card)
- [Ways to use it](#ways-to-use-it)
- [OSD menu](#osd-menu)
- [Keyboard](#keyboard)
- [What is tested](#what-is-tested)
- [Known issues](#known-issues)
- [Building](#building)
- [Credits and licenses](#credits-and-licenses)

## The machines

| | Radio-86RK | Mikrosha | Apogey BK-01 | Partner 01.01 | Mikro-80 |
|---|---|---|---|---|---|
| CPU | KR580VM80A, 1.78 MHz | KR580VM80A, 1.78 MHz | KR580VM80A, 1.78 MHz | KR580VM80A, 2 MHz | KR580VM80A, 2 MHz |
| RAM | 32 KB | 32 KB | 59 KB (to EBFF) | 64 KB in 16 memory maps | 62 KB + RAM disk 8 × 64 KB |
| ROM | Monitor, 2 KB at F800 | Monitor, 2 KB at F800 | 4 KB at F000 | 16 KB: Monitor, BASIC, editor and assembler | Monitor, 2 KB at F800 (two versions) |
| Screen | KR580VG75 + KR580VT57 (DMA): text 64 × 25, pseudo-graphics | as the RK, two fonts | as the RK, in colour, with a graphic font | as the RK, 8 fonts chosen by the attributes; colour graphics with the MCPG | its own text screen 64 × 32, inverse per character |
| Sound | INTE of the CPU (beeper) | 8253 timer, channel 2 | 8253 timer, three channels | beeper; 8253 timer of the MCPG, three channels | the tape output |
| Keyboard | 8 × 8 matrix on a PPI | the same keys, ports A and B swapped | as the RK | as the RK | its own matrix, the PPI on I/O ports |
| Storage | tape; SD card with SDOS | tape | tape, ROM disk 512 KB | tape (floppy and SD modules: not in the core) | tape, ROM disk 32 KB |

The Mikrosha and the Apogey are compatible with the Radio-86RK in the Monitor calls and the screen,
but not in the memory map: a program that touches the hardware directly needs its version for the
model (`.rkm` for the Mikrosha, `.rka` for the Apogey). The Partner is the most developed of the
family: its memory is switched by maps, it has an interrupt from the screen and slots for modules; its
programs (`.rkp`) are its own. The Mikro-80 is the older, simpler machine
with I/O ports instead of memory-mapped devices; its programs (`.rk8`) are a world of their own, and
with the Monitor of the RK type (Mikro-80RK) it runs a part of the RK software.

## What the core does

- **Processor:** KR580VM80A (vm80a, a cycle exact model of the chip) at the clock of the model
  (1.78 or 2 MHz), or twice that with Turbo.
- **Video:** the KR580VG75 and its DMA KR580VT57 at their native timing, as on the real machines (the
  DMA takes cycles from the CPU, so programs run at their true speed). The picture goes into a frame
  buffer in the SRAM of the board and comes out as **800 × 600 at 60 Hz**, whatever a program sets the
  VG75 to: there is no mode a monitor cannot take. The Mikro-80 text screen goes into the same buffer.
- **Colour** of the Apogey (the attributes of the VG75) and its graphic font (switched by INTE), the
  second font of the Mikrosha, the 8 fonts of the Partner and the colour graphics of its **MCPG**
  module (4 points of 8 colours per character over the text).
- **Sound:** the beeper of the RK and the Partner, the 8253 timer of the Mikrosha, the Apogey and the
  MCPG, the tape output of the Mikro-80, through HDMI and the DAC.
- **Keyboard:** the matrix of each model from a USB keyboard, with the punctuation matched to the PC
  keys. A USB gamepad works as keys.
- **Programs:** tape files (`.rk`, `.rkr`, `.gam`, `.rkm`, `.rka`, `.rkp`, `.rk8`) loaded straight into memory
  and started by themselves.
- **SDOS** of the Radio-86RK: the SD adapter HWM / PVV on an image file of an SD card (FAT12 / FAT16),
  with the 4 KB ROM of SDOS at E000.
- **ROM disks:** the 512 KB ROM disk of the Apogey and the 32 KB ROM disk of the Mikro-80, from a file
  on the SD card.
- **RAM disk** of the Mikro-80: 8 pages of 64 KB.
- **Tape:** TAPE_IN and TAPE_OUT of the board for a real tape recorder (not tried yet).

Not there yet: the floppy (RK-DOS), the floppy and SD modules of the
Partner, the ROM disk of the Mikrosha, KR-03 and Krista, the Go and Mini boards. See [docs/BACKLOG.md](docs/BACKLOG.md) (Russian).

## Getting started

1. Copy `rk.kg` to the root of the SD card of the board.
2. Make a folder `/rk` on the card and put programs there (see
   [Where to get software](#where-to-get-software)).
3. Choose **Radio-86RK family** in the core menu. The Radio-86RK starts: `РАДИО-86РК` and the prompt
   `-->`.
4. Open the OSD with **Menu+Esc**, choose **Tape file** (Menu+F2) and pick an `.rk` or `.gam` file: it
   loads and starts by itself.

Another machine: **Model** in the OSD (Menu+M). The machine resets and starts its Monitor. The model
and the switches are remembered between starts of the core.

## Where to get software

| Source | What | Models |
|---|---|---|
| [Emu80](https://github.com/vpyk/emu80v4) by Viktor Pykhonin: a [release](https://github.com/vpyk/emu80v4/releases), or `dist/` on GitHub | `dist/rk86/sdcard/GAMES` (37 games), `dist/rk86/sdcard/SOFT` (40 programs) | Radio-86RK |
| | `dist/apogey/sdcard`: `TGAMES` (88 text games), `GGAMES` (7 graphic games), `DEMO`, `MUSIC`, `PROG`, `UTIL`, all `.rka`; `dist/apogey/romdisk512.bin`, the ROM disk with the same software and a shell | Apogey |
| | `dist/partner/sdcard`: `GAMES` (5 games), `COLOR` (6 games for the MCPG), `DEMO`, all `.rkp` | Partner |
| | `dist/mikro80/romdisk.bin`: the ROM disk (two BASICs, Tetris, CP/M; from [prokushev/micro-80-cpm](https://github.com/prokushev/micro-80-cpm)) | Mikro-80 |
| | `dist/rk86/sd_rk86.img`: an SD card image for SDOS with most of the RK software (`GAMES`, `SOFT`) | Radio-86RK |
| [rk86.ru](https://rk86.ru) ([begoon/rk86-js](https://github.com/begoon/rk86-js)) | an online Radio-86RK with a catalog of programs (`.rk`, `.rkr`, `.gam`) to download | Radio-86RK |
| [emu80.org/files](https://emu80.org/files/) | the file archive of the Emu80 site, filtered by computer (РК-86, Микроша, Апогей, Микро-80, Партнер) | all |

**Formats:** a tape file is an optional sync byte `E6`, the start and end address (high byte first),
the bytes, a checksum. `.rk`, `.rkr`, `.gam` are files of the Radio-86RK, `.rkm` of the Mikrosha,
`.rka` of the Apogey, `.rkp` of the Partner, `.rk8` of the Mikro-80: the format is the same, the extension tells the model.
A ROM disk is a plain binary (`.bin`, `.rom`). An SD card for SDOS is an image of a whole card (`.img`).

## The SD card

```
/rk.kg
/rk/
    *.rk, *.rkr, *.gam   Radio-86RK programs (Tape file)
    *.rkm                Mikrosha programs
    *.rka                Apogey programs
    *.rkp                Partner programs
    *.rk8                Mikro-80 programs
    APOGEY.ROM           the ROM disk of the Apogey (romdisk512.bin of Emu80; ROM disk)
    MIKRO80.ROM          the ROM disk of the Mikro-80 (romdisk.bin of Emu80)
    SD_RK86.IMG          the SD card of SDOS (sd_rk86.img of Emu80; SD card)
```

The two ROM disks of Emu80 have similar names: renaming them as above keeps them apart. The Monitors
and the fonts of all models are inside `rk.kg`.

## Ways to use it

### Radio-86RK

The Monitor prompt is `-->`. Useful directives: `D<start>,<end>` dumps the memory, `M<address>`
changes it, `G<address>` runs a program, `I` reads a tape, `O<start>,<end>` writes one. The memory
maps and the ports of all models are in [docs/HARDWARE.md](docs/HARDWARE.md) (Russian).

**Programs:** Tape file (Menu+F2). With **Autorun = On** the machine is reset and its Monitor runs
for about a second (3.5 s on the Mikro-80; it sets up the PPI, the VG75 and its variables, as after a
real start), then the program starts at its start address. With Autorun = Off the program is only loaded: start it with `G<address>`.

### SDOS

Choose an image as **SD card** (Menu+F4), e.g. `sd_rk86.img` of Emu80, then type `GE000` Enter: SDOS
prints `SDOS_V8.9N` and the prompt `A:\>`. `DIR` lists the folder, `CD <name>` goes into a folder
(`CD ..` back), `<name>` starts a program. Writes go back into the image file. While an image is
chosen, the RK86 has the SD adapter at D000-DFFF and the VG75 at C000-CFFF only (as the SDOS
version of the machine); choosing no image gives the plain RK86 back. A new image of your own: a
FAT12 / FAT16 image of a small card with the files copied onto it (e.g. with `mtools`).

### Mikrosha

Model = Mikrosha: `- МИКРОША -` and the prompt `->`. The directives are those of the RK Monitor.
Programs: `.rkm` files, Tape file as above. The sound is the 8253 timer.

### Apogey BK-01

Model = Apogey: `АПОГЕЙ БК-01` and the prompt `==>`. Set **Color** = Color for the colours of the
Apogey; Mono gives the picture of a black and white TV. Programs: `.rka` files, Tape file.

**ROM disk:** choose `APOGEY.ROM` as ROM disk (Menu+F3), then type `R,C` Enter and `G` Enter: the
shell of the ROM disk shows its sections (graphic games, demos, games, music, programming,
utilities); the arrows choose, Enter starts. The chosen ROM disk is loaded again at every start of
the core.

### Partner 01.01

Model = Partner: `ПАРТНЕР-01.01 (В.03)` and the prompt `:->`. The directives are those of the RK
Monitor; `B` starts the built-in BASIC (Бейсик-Микрон), `A` the built-in editor and assembler Микрон
(`СТР`, here Delete, switches between them). If letters come out in Cyrillic (the BASIC may start
in the Russian mode), press Caps Lock (РУС/ЛАТ). Programs: `.rkp` files, Tape file.

**MCPG:** the colour module is always there: a program switches it on and draws in colour over the
text, as the games of `COLOR` in Emu80 do. Its 8253 plays three channels of music. The floppy and SD
card modules (`E1`, `E2` of the Monitor) are not in the core.

### Mikro-80

Two models, two Monitors:

- **Mikro-80**: its own Monitor, `*МИКРО/80* MONITOR` and the prompt `>`.
- **Mikro-80RK**: the Monitor of the RK type, `M/80K DFFF` and `-->`. At a cold start it checks the
  memory for about 3 seconds. The ROM disk shell wants this one.

**ROM disk:** Model = Mikro-80RK, ROM disk = `MIKRO80.ROM`, then `R7E00,7FFF` Enter and `G` Enter:
`*ROM-DISK/32K*` lists BASIC, BASIC2, TETRIS and CP/M; the arrows choose, Enter starts. The **RAM
disk** (8 × 64 KB) is the disk of CP/M; it keeps its contents until the board is switched off.

The Mikro-80 has no sound of its own: what it plays goes to the tape output, and the core sends that
to HDMI and the DAC.

### Tape

TAPE_IN of the board goes to the tape input of the model (PC4 of the keyboard PPI, port 01 of the
Mikro-80), its tape output to TAPE_OUT: the tape directives of the Monitors should work with a real
tape recorder (not tried yet). The tape output is also heard, quietly, in the sound.

### Turbo

**CPU speed** = Turbo doubles the CPU clock (3.56 or 4 MHz): programs run faster. The VG75 and the
8253 keep their clocks, so music on the 8253 keeps its pitch.

## OSD menu

Open the OSD with **Menu+Esc**. File items open the browser in `/rk`. A change of Model resets the
machine; the other switches act at once.

| Item | Values | Hotkey | What it does |
|---|---|---|---|
| Tape file | `.rk .rkr .gam .rkm .rka .rkp .rk8` | Menu+F2 | loads a program into the RAM (Autorun starts it) |
| ROM disk | `.bin .rom` | Menu+F3 | the ROM disk of the Apogey (up to 512 KB) or of the Mikro-80 (32 KB) |
| SD card | `.img` | Menu+F4 | the SD card image of SDOS (the RK86) |
| Model | RK86, Mikrosha, Apogey, Partner, Mikro-80, Mikro-80RK | Menu+M | the machine |
| CPU speed | Normal, Turbo | Menu+S | the CPU clock, × 2 in Turbo |
| Color | Mono, Color | Menu+C | the colours of the Apogey (the Partner shows the colours of the MCPG always, the other models are black and white) |
| Autorun | On, Off | Menu+A | start a tape file after its load |
| Reset | | F12 | resets the machine |

Ctrl+Alt+Backspace goes back to the boot menu of the board (the firmware).

## Keyboard

The layout is positional: letters and digits are on their places, and the punctuation of the PC keys
gives the same characters on the machine (`=`, `'`, `"`, `@`, `^`, `*`, `(`, `)`, `:`, `+`), whatever
key of the matrix that takes.

| PC key | RK keyboard |
|---|---|
| Shift | СС |
| Ctrl | УС |
| Caps Lock | РУС/ЛАТ |
| Enter | ВК |
| Backspace | ЗБ |
| Insert | ПС (line feed) |
| Delete | СТР (clear screen) |
| Home | ↖ (cursor home) |
| Esc | АР2 |
| Tab | ТАБ |
| F1–F5 | F1–F5 |
| `` ` `` | `^` (Ч in Russian) |
| arrows, keypad digits | arrows, digits |

The Mikro-80 has no АР2, ТАБ, ПС and F keys: Esc, Tab, Insert and F1–F5 do nothing there.

USB gamepad: the arrows are the cursor keys, A is Space, B and Start are Enter.

## What is tested

On the Mini G with an HDMI capture (picture and sound):

| | Mini G |
|---|---|
| Radio-86RK: Monitor, keyboard (a dump of the ROM), `.rk` games with Autorun | yes |
| SDOS: `GE000`, `DIR`, `CD`, a program from the SD card, the RK86 back after the image is ejected | yes |
| SDOS: writing to the image | not yet |
| Mikrosha: Monitor, keyboard | yes |
| Apogey: Monitor, keyboard, ROM disk shell in colour, a graphic game, music on the 8253 | yes |
| Mikro-80, Mikro-80RK: Monitors, keyboard, ROM disk shell, Tetris | yes |
| A change of the model on the fly | yes |
| Mikro-80 RAM disk | simulation only |
| Partner: Monitor, BASIC, keyboard, `.rkp` games (XONIX), MCPG colour games and their music (PACMAN, MARS2) | yes |
| Mikrosha `.rkm` programs and their sound | not yet |
| Tape | not yet |
| Go, Mini | built, not tried yet |

## Known issues

- The picture of the models with the VG75 sits at the top left of the screen: the raster their
  Monitors set is smaller than the frame buffer window. Centring is in the backlog.
- The Mikro-80 shows rows of 9 lines (8 + 1 dark) instead of 10, so that its 32 rows fit the frame
  buffer: the gaps between pseudo-graphic rows are one line thinner.

## Building

Clone with `--recursive` (the board modules are the submodule `modules/`,
[karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)) and put
[karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this repository. With
ISE 14.7, `cd src && make minig` builds the Mini G and `rk.kg` (`make go`, `make mini` the other boards into the
same file). `src/sim/run_boot.sh` runs the
simulation (verilator): every model starts its Monitor, takes keys and autoruns a file; `EMU80=<emu80v4>` adds the Partner games and the MCPG; SDOS on the SD image of Emu80 too; `FULL=1 ROMDISK=<romdisk512.bin>` adds the Apogey ROM disk shell. [CLAUDE.md](CLAUDE.md) has the details,
[docs/PLAN.md](docs/PLAN.md) the decisions and the history (Russian).

## Credits and licenses

The core is GPL v3 (`LICENSE`). Third-party code: the KR580VG75 and KR580VT57 of
[Apogee_MiSTer](https://github.com/MiSTer-devel/Apogee_MiSTer) (Dmitry Tselikov, modified BSD, with
the changes of Sorgelig; the VG75 converted to Verilog by sv2v, its font moved out, a reset added),
vm80a (1801BM1, CC-BY 3.0), KF8253 (kitune-san, MIT, through core-specialist). The Monitors and the
fonts of all models come with [Emu80](https://github.com/vpyk/emu80v4) by Viktor Pykhonin, the
reference of the behaviour together with Apogee_MiSTer by Sorgelig. The structure of the core follows
[core-specialist](https://github.com/andykarpov/karabas-go-core-specialist) and
[core-orion128](https://github.com/andykarpov/karabas-go-core-orion128).
