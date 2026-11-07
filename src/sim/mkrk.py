#!/usr/bin/env python3
# A test tape file for run_boot.sh: at 0100 it writes 5A at 1000 and stops in a loop. The RK format:
# E6, start and end (high byte first), the bytes, a checksum.
import sys
code = bytes([0x3E, 0x5A, 0x32, 0x00, 0x10, 0xC3, 0x05, 0x01])
start = 0x0100
end = start + len(code) - 1
cs = sum(code) & 0xFFFF
open(sys.argv[1], 'wb').write(bytes([0xE6]) + start.to_bytes(2, 'big') + end.to_bytes(2, 'big') + code + cs.to_bytes(2, 'big'))
