# microphone

Offline-first FPGA/PS pipeline for a parameterized digital microphone array on
the ALINX AX7Z020 (XC7Z020).

The board-facing frontend is a staged LC-AI-K210-7Mic I2S receiver. Seven
MSM261S4030H0R microphones map to M0..M6 and channel 7 is forced to zero. The
validated acoustic Ethernet path is 100 Mbps full duplex, with UDP/45123 and
the existing PCM16LE protocol. The I2S bitstream is selected with
`MIC_SOURCE_MODE=1`; the default synthetic source remains available for
offline tests only.

Development targets Vivado and Xilinx SDK 2019.1. Board programming is
volatile-only through JTAG (no QSPI/Flash writes). The current stable physical
artifacts use `MIC_SOURCE_MODE=1`, 100 Mbps full duplex, and conversion
`signed(slot[30:7]) >>> 8` before int16 saturation.

Bring-up commands:

```powershell
E:\vivado\Vivado\2019.1\bin\vivado.bat -mode batch -source vivado\build_mic_dma.tcl
E:\vivado\SDK\2019.1\bin\xsct.bat scripts\program_physical_mic.xsct
scripts\capture_uart.ps1 -Port COM4
matlab -batch "cd('D:/microphone'); addpath('matlab'); live_mic_receiver('LocalPort',45123)"

# One-command morning acoustic capture (MATLAB first, then JTAG download)
powershell -NoProfile -ExecutionPolicy Bypass -File D:\microphone\scripts\run_morning_acoustic_test.ps1
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

The final controlled 1 kHz physical acceptance is recorded under
[`evidence/physical/acoustic_handshake_20260904_204104_671`](evidence/physical/acoustic_handshake_20260904_204104_671/acceptance_summary.md).
MATLAB received 95,068 contiguous PCM packets with zero CRC, malformed, loss,
duplicate, ordering, or frame-layout errors. Both requested tone intervals
produced a 1000.0 Hz dominant peak on CH1-CH7, with RMS 21.30-36.63 dB above
quiet and zero clipping; CH8 remained empty. This records
`MIC_ACOUSTIC_1KHZ_PHYSICAL_PASS`, `MIC_ACOUSTIC_RESPONSE_PHYSICAL_PASS`, and
`MIC_MATLAB_LIVE_PHYSICAL_PASS`.

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

## Stability evidence

`scripts/run_overnight_soak.ps1` starts the rolling Python receiver before
volatile JTAG programming, captures UART, and records adapter counter deltas.
It validates every MIC0 datagram while retaining only first/middle/last
10-second windows and minute statistics. The 5-minute smoke and 1-hour soak
evidence are stored under
`evidence/physical/overnight_final_20260904/`; quiet-environment data does not
constitute an acoustic PASS. The separate controlled test linked above closes
the acoustic and MATLAB-live gates.
