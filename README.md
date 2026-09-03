# microphone

Offline-first FPGA/PS pipeline for a parameterized digital microphone array on
the ALINX AX7Z020 (XC7Z020).

The physical microphone protocol and GPIO mapping are not yet known. Until the
hardware facts are available, development uses a deterministic eight-channel
PCM stream and keeps the board-facing frontend behind
`REAL_MIC_PROTOCOL_PENDING` has been replaced by a staged LC-AI-K210-7Mic
I2S frontend. Seven MSM261S4030H0R microphones map to M0..M6 and channel 7 is
forced to zero. The current clock plan is BCK 3.125 MHz and WS 48.828125 kHz
from the 50 MHz PS FCLK; I2S bit alignment remains pending an ILA capture.

Development targets Vivado and Xilinx SDK 2019.1. No board programming or
physical hardware access is now staged and remains volatile-only (no QSPI write).

Bring-up commands:

```powershell
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\build_mic_dma.tcl
E:\vivado\SDK\2019.1\bin\xsct.bat scripts\program_physical_mic.xsct
scripts\capture_uart.ps1 -Port COM4
matlab -batch "cd('D:/microphone'); addpath('matlab'); live_mic_receiver('LocalPort',45123)"
```

The stable physical link uses 100 Mbps full duplex: board `192.168.1.10/24`
to Windows adapter `以太网 3` at `192.168.1.2/24` (ifIndex 17), with UDP
port `45123`. Start the receiver before programming the board:

```powershell
D:\python3.12.3\python.exe scripts\udp_capture.py --bind 0.0.0.0 --port 45123 --seconds 150 --output evidence/physical/udp_capture
```

The complete 100M physical evidence, including UART/XSCT logs, adapter
counter deltas, raw packet capture, Python validation, and MATLAB `udpport`
live capture is summarized in
[`docs/physical_evidence_20260903.md`](docs/physical_evidence_20260903.md).

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
