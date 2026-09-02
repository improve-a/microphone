# microphone

Offline-first FPGA/PS pipeline for a parameterized digital microphone array on
the ALINX AX7Z020 (XC7Z020).

The physical microphone protocol and GPIO mapping are not yet known. Until the
hardware facts are available, development uses a deterministic eight-channel
PCM stream and keeps the board-facing frontend behind
`REAL_MIC_PROTOCOL_PENDING`.

Development targets Vivado and Xilinx SDK 2019.1. No board programming or
physical hardware access is part of the current baseline.

## Offline regression

The complete command-line gate auto-detects the installed tools and records a
run under `evidence/runs/<RUN_ID>`:

```powershell
python scripts/run_regression.py
```

Focused gates are also directly reproducible:

```powershell
python -m unittest discover -s tests -v
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\run_rtl_tests.tcl
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\run_ooc.tcl
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\build_mic_dma.tcl
E:\vivado\SDK\2019.1\bin\xsct.bat sw\build_sdk.tcl
matlab -batch "cd('D:/microphone'); addpath('matlab'); run_all_tests"
```

See `docs/CURRENT_STATUS.md` before interpreting any PASS token. Offline DMA
build success is not evidence of physical DDR, Ethernet, GPIO, or microphone
operation.
