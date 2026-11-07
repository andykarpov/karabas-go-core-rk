#!/bin/bash
# The machine in simulation. Builds sim_boot (verilator) into src/sim/build, runs it from src/; the
# frame buffer pictures are in build/*.ppm.
#  1. the Radio-86RK, its Monitor: the frame buffer shows its first screen (not empty), and the video
#     output (800 x 600) is not empty.
#  2. the same in turbo.
#  3. keys (held 100 ms): DF800,F81F + Enter dumps the Monitor ROM, the screen changes, the keys click.
#  4. a tape file (mkrk.py: writes 5A at 1000) loads through the FL port and starts by itself 200 ms
#     later; with --noauto it loads but does not start.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/rk/rk_system.v $R/rk/rk_kbd.v $R/rk/rk_loader.v $R/rk/rk_video.v $R/rk/rk_cpu.v $R/rk/rk_ppi.v $R/rk/rk_sram.v $R/apogee/k580vg75.v $R/apogee/k580vt57.v $R/vm80a/vm80a.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_boot -Mdir "$B/obj" -o sim_boot \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_boot.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_boot
ROMS="--rom roms/rk86.rom:0x100000 --rom roms/sgr.bin:0x1F0000"
T=${BOOT_MS:-1000}
err=0
"$SIM" $ROMS --ms $T --ppm "$B/rk86.ppm" --frame "$B/rk86_frame.ppm" || err=1
"$SIM" $ROMS --turbo --ms $T --ppm "$B/rk86_turbo.ppm" || err=1
for f in rk86 rk86_frame; do
	[ "$(tail -c +16 "$B/$f.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "$f: empty"; err=1; }
done
keys() { t=$1; shift; for k in "$@"; do printf -- '--key %d:%s --key %d:F0,%s ' $t $k $((t+100)) $k; t=$((t+300)); done; }
"$SIM" $ROMS --ms 5200 $(keys 600 23 2B 3E 45 45 41 2B 3E 16 2B 5A) --ppm "$B/rk86_key.ppm" | tee "$B/key.txt" || err=1
cmp -s "$B/rk86.ppm" "$B/rk86_key.ppm" && { echo "the keys changed nothing"; err=1; }
grep -q "beep edges 0 " "$B/key.txt" && { echo "the keys do not click"; err=1; }
python3 "$H/mkrk.py" "$B/t.rk"
"$SIM" $ROMS --ms 1200 --file 500:1:"$B/t.rk" --expect 0x1000:0x5A || err=1
"$SIM" $ROMS --noauto --ms 1200 --file 500:1:"$B/t.rk" --expect 0x1000:0x00 || err=1
echo "run_boot: $err errors"
exit $err
