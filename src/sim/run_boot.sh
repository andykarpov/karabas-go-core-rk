#!/bin/bash
# The machine in simulation. Builds sim_boot (verilator) into src/sim/build, runs it from src/; the
# frame buffer pictures are in build/*.ppm.
#  1. the Radio-86RK, its Monitor: the frame buffer shows its first screen (not empty).
#  2. the same in turbo: the same picture.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/rk/rk_system.v $R/rk/rk_cpu.v $R/rk/rk_ppi.v $R/rk/rk_sram.v $R/apogee/k580vg75.v $R/apogee/k580vt57.v $R/vm80a/vm80a.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_boot -Mdir "$B/obj" -o sim_boot \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_boot.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_boot
ROMS="--rom roms/rk86.rom:0x100000 --rom roms/sgr.bin:0x1F0000"
T=${BOOT_MS:-1000}
err=0
"$SIM" $ROMS --ms $T --ppm "$B/rk86.ppm" || err=1
"$SIM" $ROMS --turbo --ms $T --ppm "$B/rk86_turbo.ppm" || err=1
[ "$(tail -c +16 "$B/rk86.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "rk86: empty frame"; err=1; }
echo "run_boot: $err errors"
exit $err
