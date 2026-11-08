#!/usr/bin/env python3
# A test tape file for run_boot.sh: at 0100 it writes 5A at 1000 and stops in a loop. The RK format:
# E6, start and end (high byte first), the bytes, a checksum.
#   mkrk.py OUT          the test above
#   mkrk.py OUT ramdisk  the RAM disk of the Mikro-80: page 1 (OUT 40, FE), PUSH A55A at 1000, the main
#                        memory again (OUT 40, FF), a loop: A5 5A in page 1 at 1000, nothing at 1000
import sys
if len(sys.argv) > 2 and sys.argv[2] == 'ramdisk':
    code = bytes([0x3E, 0xFE, 0xD3, 0x40, 0x31, 0x02, 0x10, 0x01, 0x5A, 0xA5, 0xC5,
                  0x3E, 0xFF, 0xD3, 0x40, 0xC3, 0x0F, 0x01])
else:
    code = bytes([0x3E, 0x5A, 0x32, 0x00, 0x10, 0xC3, 0x05, 0x01])
start = 0x0100
end = start + len(code) - 1
cs = sum(code) & 0xFFFF
open(sys.argv[1], 'wb').write(bytes([0xE6]) + start.to_bytes(2, 'big') + end.to_bytes(2, 'big') + code + cs.to_bytes(2, 'big'))
