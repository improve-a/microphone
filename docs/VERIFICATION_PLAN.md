# Verification Plan

## Gates

| Gate | Evidence required |
|---|---|
| M1 model | order, signed range, deterministic seed, amplitude, delay, frame boundary |
| M1 RTL | reset, sine/pseudo values, metadata, TLAST, randomized backpressure stability |
| Packer RTL | even/odd packing, TKEEP, TLAST, output stall stability |
| M2 OOC | Vivado 2019.1 synth, critical DRC=0, WNS >= 0 |
| M2 BD | GP0 control, HP0 data, IRQ/reset/clock connectivity, validate_bd_design |
| M2 implementation | route complete, failed nets=0, critical DRC=0, setup/hold met |
| M2 software | host `-Werror` test and SDK 2019.1 BSP/ELF build |
| M3 Python | header/CRC/MTU, signed recovery, loss, duplicate, malformed, exact matrix |
| M3 MATLAB | same packet file, exact matrix, loss/duplicate/malformed, known delays |
| Bonus MATLAB | known linear-array delay and DOA recovery |

`scripts/run_regression.py` records command output, tool paths, Git/source-tree
identity, required PASS tokens and a JSON summary. A zero process exit without
the expected token is failure. XSim logs are also rejected if they contain
`Fatal`, `_FAIL`, or an error marker.

## Not offline-testable

No offline gate may establish physical microphone protocol, GPIO/XDC,
electrical compatibility, DDR integrity, Ethernet PHY/lwIP operation or
end-to-end board throughput. These remain UNKNOWN until controlled physical
bring-up.

