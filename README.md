# microphone

Offline-first FPGA/PS pipeline for a parameterized digital microphone array on
the ALINX AX7Z020 (XC7Z020).

The physical microphone protocol and GPIO mapping are not yet known. Until the
hardware facts are available, development uses a deterministic eight-channel
PCM stream and keeps the board-facing frontend behind
`REAL_MIC_PROTOCOL_PENDING`.

Development targets Vivado and Xilinx SDK 2019.1. No board programming or
physical hardware access is part of the current baseline.
