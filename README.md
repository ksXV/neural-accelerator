# Systolic Matrix Multiplier

A parameterized systolic architecture implemented in SystemVerilog designed for DNN inference acceleration. The project implements the matmul algorithm into hardware using quantized 8 bit integer values. (still WIP)

---

### Key Modules

- [`rtl/systolic_mac_pe.sv`](rtl/systolic_mac_pe.sv): Multiply-Accumulate Processing Element with accumulation register and drain multiplexing.
- [`rtl/shift_register.sv`](rtl/shift_register.sv): Generates skewed input delays (triangular latency buffering) to align matrix inputs with the systolic wavefront.
- [`rtl/systolic_control_unit.sv`](rtl/systolic_control_unit.sv): FSM sequencing tile execution, address calculation, PE wavefront enables, and result drain phases.
- [`rtl/bram.sv`](rtl/bram.sv): Dual-word memory blocks initialized with input matrices A, B, and bias tensors.
- [`rtl/systolic_accumulator.sv`](rtl/systolic_accumulator.sv): Output accumulator pipeline handling bias addition and streaming tile results.
- [`rtl/systolic_top.sv`](rtl/systolic_top.sv): Top-level wrapper integrating memories, shift registers, PE grid, and control.

---

## Quickstart

### 1. Prerequisites
- [Verilator](https://www.veripool.org/verilator/) (>= 5.0) for simulation
- [GTKWave](https://gtkwave.sourceforge.net/) for waveform viewing
- Python 3 with `numpy` (optional) for test vector generation
- Open-source FPGA toolchain: [Yosys](https://yosyshq.net/yosys/), [nextpnr-himbaechel](https://github.com/YosysHQ/nextpnr), [apycula](https://github.com/YosysHQ/apicula), and [openFPGALoader](https://github.com/trabucayre/openFPGALoader)

### 2. Generate Memory Files
Generate input matrices and golden reference files into `systolic_mem_files/`:
```bash
python3 scripts/gen_mem.py
```

### 3. Simulation
Compile and run the Verilator testbench verifying all 48 tiles against `c_golden.txt`:
```bash
make run
```

To inspect waveform traces (`waveform.vcd`):
```bash
make wave
```

---

## FPGA Build & Synthesis

| Command | Action |
|---|---|
| `make synth` | Synthesize RTL to gate-level netlist (`synth/netlist.json`) via Yosys |
| `make gates` | Generate gate schematic SVG (`synth/gates.svg`) via Graphviz |
| `make pnr` | Run place & route and generate layout SVGs (`synth/placed.svg`, `synth/routed.svg`) |
| `make bitstream`| Pack bitstream (`synth/bitstream.fs`) for Tang Nano 9K |
| `make flash` | Flash bitstream to Tang Nano 9K using openFPGALoader |
