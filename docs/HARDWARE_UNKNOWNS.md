# Hardware Unknowns

Confirmed from the LC-AI-K210-7Mic documentation and installed J20 wiring:

- seven MSM261S4030H0R digital MEMS microphones;
- I2S output with four DATA lines;
- module 5 V supply and 3.3 V logic;
- FPGA-to-module BCK and WS outputs;
- D0=M0/M1, D1=M2/M3, D2=M4/M5, D3=empty/M6;
- BCK operating range 1-4 MHz, current plan 3.125 MHz;
- J20 mapping D0=R14, D1=P14, D2=U12, D3=T12, WS=T15, BCK=T14;
- all six FPGA I/O use LVCMOS33;
Still UNKNOWN until a physical ILA capture:

- exact data-changing and data-sampling BCK edges;
- WS-to-MSB delay, valid bit width and PCM extraction alignment;
- measured BCK/WS frequency and jitter at module pins;
- array spacing/orientation calibration and DOA sign convention;
- electrical level of the D3 empty slot.

The confirmed project target is ALINX AX7Z020 / Zynq XC7Z020, with Vivado and
SDK 2019.1 used for this baseline. The exact board PS7 preset, DDR timing and
Ethernet PHY configuration still require the matching schematic/vendor project
before physical use.
