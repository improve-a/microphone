# Hardware Unknowns

The following are UNKNOWN and must not be inferred from the digital baseline:

- microphone manufacturer and part number;
- PDM, I2S or TDM protocol;
- microphone and FPGA clock frequency;
- sampling edge and setup/hold requirements;
- channel count and DATA-line topology;
- L/R or channel-select wiring;
- GPIO package pins;
- I/O standard and bank voltage;
- physical array spacing and orientation.

The confirmed project target is ALINX AX7Z020 / Zynq XC7Z020, with Vivado and
SDK 2019.1 used for this baseline. The exact board PS7 preset, DDR timing and
Ethernet PHY configuration still require the matching schematic/vendor project
before physical use.

