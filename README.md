# microphone

Offline-first FPGA/PS pipeline for a parameterized digital microphone array on
the ALINX AX7Z020 (XC7Z020).

The board-facing frontend is a staged LC-AI-K210-7Mic I2S receiver. Seven
MSM261S4030H0R microphones map to M0..M6 and channel 7 is forced to zero. The
validated acoustic Ethernet path is 100 Mbps full duplex, with UDP/45123 and
the existing PCM16LE protocol. The I2S bitstream is selected with
`MIC_SOURCE_MODE=1`; the default synthetic source remains available for
offline tests only.

Development targets Vivado and Xilinx SDK 2019.1. No board programming or
physical hardware access is now staged and remains volatile-only (no QSPI write).

Bring-up commands:

```powershell
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\build_mic_dma.tcl
E:\vivado\SDK\2019.1\bin\xsct.bat scripts\program_physical_mic.xsct
scripts\capture_uart.ps1 -Port COM4
matlab -batch "cd('D:/microphone'); addpath('matlab'); live_mic_receiver('LocalPort',45123)"

# Automated acoustic capture (MATLAB ready marker, XSCT download, and analysis)
powershell -ExecutionPolicy Bypass -File scripts\run_acoustic_acceptance.ps1
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
