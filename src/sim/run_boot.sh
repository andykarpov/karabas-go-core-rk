#!/bin/bash
# The machine in simulation. Builds sim_boot (verilator) into src/sim/build, runs it from src/; the
# frame buffer pictures are in build/*.ppm.
#  1. the Radio-86RK, its Monitor: the frame buffer shows its first screen (not empty), and the video
#     output (800 x 600) is not empty, with the picture in the middle (the raster centred).
#  2. the same in turbo.
#  3. keys (held 100 ms): DF800,F81F + Enter dumps the Monitor ROM, the screen changes, the keys click.
#  4. a tape file (mkrk.py: writes 5A at 1000) loads through the FL port and starts by itself after the Monitor
#     has run 2 000 000 CPU ticks (Emu80); with --noauto it loads but does not start.
#  5. the Mikrosha and the Apogey: their Monitors start, the keys of 3 change the screen, a tape file
#     starts by itself.
#  6. a change of the model on the fly (the RK86, then the Mikrosha at 317 ms): the same screen as the
#     Mikrosha from power on (the VG75 is reset with the machine); the RK86 after the dump of 3, then the
#     Apogey: the same screen as the Apogey from power on (nothing of the old frame stays).
#  7. the Mikro-80: both Monitors start (the RK type one checks the memory for 3 s), the keys of 3 on
#     its own, a tape file starts by itself, the RAM disk takes the stack cycles (mkrk.py ramdisk).
#  8. the Partner 01.01: its Monitor starts, the keys of 3 change the screen, a tape file starts by itself.
#  9. EMU80=DIR (Emu80 dist): the Partner games XONIX (needs the Monitor variables, set 0.4 s after
#     reset) and CROSSFIR start by themselves: the screen is not that of the Monitor; PACMAN draws
#     in colour through the MCPG; SDOS of the RK86 (GE000) on the SD image of Emu80 reads the card.
# 10. FULL=1: the ROM disk of the Apogey (Emu80 romdisk512.bin, ROMDISK=FILE) loads by FL slot 2 and
#     R,C + G starts its shell (2.5 minutes).
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=${SIM_BUILD:-$H/build}
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/rk/rk_system.v $R/rk/rk_kbd.v $R/rk/rk_loader.v $R/rk/rk_video.v $R/rk/rk_m80video.v $R/rk/rk_sd.v $S/../modules/rtl/mcu/img_sdc.v $S/../modules/rtl/mem/kg_tdpram.v $R/rk/rk_cpu.v $R/rk/rk_ppi.v $R/rk/rk_sram.v $R/apogee/k580vg75.v $R/apogee/k580vt57.v $R/vm80a/vm80a.v $R/kf8253/KF8253.v $R/kf8253/KF8253_Control_Logic.v $R/kf8253/KF8253_Counter.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_boot -Mdir "$B/obj" -o sim_boot \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_boot.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_boot
ROMS="--rom roms/rk86.rom:0x100000 --rom roms/mikrosha.rom:0x100800 --rom roms/apogey.rom:0x101000 --rom roms/sgr.bin:0x1F0000 --rom roms/sgm.bin:0x1F0800 --rom roms/sga.bin:0x1F1000 --rom roms/mikro80.rom:0x102000 --rom roms/mikro80rk.rom:0x102800 --rom roms/sgm80.bin:0x1F1800 --rom roms/romp1.bin:0x104000 --rom roms/romp2.bin:0x106000 --rom roms/sdrom.bin:0x108000 --rom roms/fddrom.bin:0x108800 --rom roms/mcpgrom.bin:0x109000 --rom roms/d14.bin:0x10A000 --rom roms/sgp.bin:0x1F2000 --rom roms/sdos_hwmpvv.bin:0x10B000"
T=${BOOT_MS:-1000}
err=0
"$SIM" $ROMS --ms $T --ppm "$B/rk86.ppm" --frame "$B/rk86_frame.ppm" || err=1
"$SIM" $ROMS --turbo --ms $T --ppm "$B/rk86_turbo.ppm" || err=1
for f in rk86 rk86_frame; do
	[ "$(tail -c +16 "$B/$f.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "$f: empty"; err=1; }
done
# the picture is in the middle: the raster of the RK86 is 389 x 280, so 15 cells (90 pixels) right and 10 lines (20) down
python3 -c "
import sys
d = open(sys.argv[1], 'rb').read().split(b'\n', 3)[3]
lit = [(i // 3 % 800, i // 3 // 800) for i in range(0, len(d), 3) if d[i] or d[i + 1] or d[i + 2]]
sys.exit((min(x for x, y in lit), min(y for x, y in lit)) != (115, 44))" "$B/rk86_frame.ppm" || { echo "the picture is not in the middle"; err=1; }
keys() { t=$1; shift; for k in "$@"; do printf -- '--key %d:%s --key %d:F0,%s ' $t $k $((t+100)) $k; t=$((t+300)); done; }
"$SIM" $ROMS --ms 5200 $(keys 600 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --ppm "$B/rk86_key.ppm" | tee "$B/key.txt" || err=1
cmp -s "$B/rk86.ppm" "$B/rk86_key.ppm" && { echo "the keys changed nothing"; err=1; }
grep -q "beep edges 0 " "$B/key.txt" && { echo "the keys do not click"; err=1; }
python3 "$H/mkrk.py" "$B/t.rk"
"$SIM" $ROMS --ms 2000 --file 500:1:"$B/t.rk" --expect 0x1000:0x5A || err=1
"$SIM" $ROMS --noauto --ms 2000 --file 500:1:"$B/t.rk" --expect 0x1000:0x00 || err=1
for m in 1 2; do
	"$SIM" $ROMS --model $m --ms $T --ppm "$B/m$m.ppm" || err=1
	[ "$(tail -c +16 "$B/m$m.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "model $m: empty"; err=1; }
	"$SIM" $ROMS --model $m --ms 5200 $(keys 600 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --ppm "$B/m${m}_key.ppm" || err=1
	cmp -s "$B/m$m.ppm" "$B/m${m}_key.ppm" && { echo "model $m: the keys changed nothing"; err=1; }
	"$SIM" $ROMS --model $m --ms 2000 --file 500:1:"$B/t.rk" --expect 0x1000:0x5A || err=1
done
"$SIM" $ROMS --switch 317:1 --ms 1500 --ppm "$B/switch.ppm" || err=1
"$SIM" $ROMS --model 1 --ms 1500 --ppm "$B/m1_cold.ppm" || err=1
cmp -s "$B/switch.ppm" "$B/m1_cold.ppm" || { echo "a change of the model gives another screen"; err=1; }
"$SIM" $ROMS --ms 6700 $(keys 600 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --switch 5200:2 --ppm "$B/switch2.ppm" || err=1
"$SIM" $ROMS --model 2 --ms 1500 --ppm "$B/m2_cold.ppm" || err=1
# the cursor may blink in another phase: up to one cursor (6 points of a line) may differ
python3 -c "import sys; a, b = (open(f, 'rb').read() for f in sys.argv[1:]); sys.exit(sum(x != y for x, y in zip(a, b)) > 18)" \
	"$B/switch2.ppm" "$B/m2_cold.ppm" || { echo "the RK86 screen stays under the Apogey"; err=1; }
for m in 4 5; do
	"$SIM" $ROMS --model $m --ms 4000 --ppm "$B/m$m.ppm" || err=1
	[ "$(tail -c +16 "$B/m$m.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "model $m: empty"; err=1; }
done
"$SIM" $ROMS --model 4 --ms 5000 $(keys 1000 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --ppm "$B/m4_key.ppm" || err=1
cmp -s "$B/m4.ppm" "$B/m4_key.ppm" && { echo "Mikro-80: the keys changed nothing"; err=1; }
"$SIM" $ROMS --model 4 --ms 4300 --file 500:1:"$B/t.rk" --expect 0x1000:0x5A || err=1
python3 "$H/mkrk.py" "$B/rd.rk" ramdisk
"$SIM" $ROMS --model 4 --ms 4300 --file 500:1:"$B/rd.rk" --expect 0x281000:0x5A --expect 0x281001:0xA5 --expect 0x1000:0x00 || err=1
"$SIM" $ROMS --model 3 --ms $T --ppm "$B/m3.ppm" || err=1
[ "$(tail -c +16 "$B/m3.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "Partner: empty"; err=1; }
"$SIM" $ROMS --model 3 --ms 5200 $(keys 600 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --ppm "$B/m3_key.ppm" || err=1
cmp -s "$B/m3.ppm" "$B/m3_key.ppm" && { echo "Partner: the keys changed nothing"; err=1; }
"$SIM" $ROMS --model 3 --ms 2000 --file 500:1:"$B/t.rk" --expect 0x1000:0x5A || err=1
EMU80=${EMU80:-$HOME/emu80v4}
if [ -d "$EMU80/dist/partner/sdcard/GAMES" ]; then
	"$SIM" $ROMS --model 3 --ms 2000 --ppm "$B/m3_2s.ppm" || err=1
	for g in XONIX CROSSFIR; do
		"$SIM" $ROMS --model 3 --ms 4000 --file 500:1:"$EMU80/dist/partner/sdcard/GAMES/$g.RKP" --ppm "$B/p_$g.ppm" || err=1
		cmp -s "$B/m3_2s.ppm" "$B/p_$g.ppm" && { echo "Partner: $g does not start"; err=1; }
	done
	# SDOS: GE000 on the SD image of Emu80 (F slot 3), DIR lists its folders
	"$SIM" $ROMS --ms 5000 --sd "$EMU80/dist/rk86/sd_rk86.img" $(keys 800 34 24 45 45 45 5A) $(keys 3500 23 43 2D 5A) \
		--ppm "$B/sdos.ppm" | tee "$B/sdos.txt" || err=1
	grep -q "sd reads [1-9]" "$B/sdos.txt" || { echo "SDOS reads nothing of the SD card"; err=1; }
	# the colour module: PACMAN draws its picture through the MCPG (points of colour, not grey)
	"$SIM" $ROMS --model 3 --ms 5000 --file 500:1:"$EMU80/dist/partner/sdcard/COLOR/PACMAN.RKP" --ppm "$B/p_PACMAN.ppm" || err=1
	python3 -c "import sys; d = open(sys.argv[1], 'rb').read()[15:]; sys.exit(sum(d[i] != d[i + 1] for i in range(0, len(d), 3)) < 1000)" \
		"$B/p_PACMAN.ppm" || { echo "Partner: no colours of the MCPG"; err=1; }
fi
if [ -n "${FULL:-}" ]; then
	RD=${ROMDISK:-$EMU80/dist/apogey/romdisk512.bin}
	"$SIM" $ROMS --model 2 --color --ms 6000 --file 100:2:"$RD" $(keys 1500 2D 41 21 5A 34 5A) --ppm "$B/romdisk.ppm" \
		--expect 0x200000:0x16 || err=1
	echo "the shell of the ROM disk: $B/romdisk.ppm"
fi
echo "run_boot: $err errors"
exit $err
