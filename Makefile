# Verilator Makefile for systolic array simulation & Gowin FPGA synthesis

VERILATOR       = verilator
VERILATOR_FLAGS = --binary --timing --trace -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-TIMESCALEMOD -j 4

RTL_SRCS = rtl/systolic_mac_pe.sv rtl/systolic_top.sv rtl/bram.sv rtl/systolic_control_unit.sv rtl/systolic_accumulator.sv rtl/shift_register.sv
TB_SRCS  = tb/systolic_top_tb.sv
TOP_TB   = systolic_top_tb
SIM_BIN  = obj_dir/sim_test

# ---------------------------------------------------------------------------- #
# Gowin / Tang Nano 9K settings                                                #
# ---------------------------------------------------------------------------- #
YOSYS           = yosys
SYNTH_DIR       = synth
TOP_RTL         = systolic_top

# Tang Nano 9K target (GW1NR-9 / GW1NR-9C in QFN88P package)
BOARD           = tangnano9k
FPGA_FAMILY     = GW1N-9C
FPGA_DEVICE     = GW1NR-LV9QN88PC6/I5
CST             = constraints/tangnano9k.cst

NEXTPNR_GOWIN   = nextpnr-himbaechel
GOWIN_PACK      = gowin_pack
OPENFPGALOADER  = openFPGALoader

# ---------------------------------------------------------------------------- #
.PHONY: all compile run wave clean \
        synth gates pnr bitstream pnr-gui flash

all: run

# ─── Simulation ─────────────────────────────────────────────────────────────

compile: $(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(TB_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRCS) --top-module $(TOP_TB) -o sim_test

run: $(SIM_BIN)
	./$(SIM_BIN)

wave:
	gtkwave waveform.vcd &

# ─── Synthesis (Yosys with Gowin backend) ───────────────────────────────────

## synth: synthesise RTL → gate-level JSON netlist (Gowin LittleBee target)
synth: $(SYNTH_DIR)/netlist.json

$(SYNTH_DIR)/netlist.json: $(RTL_SRCS)
	@mkdir -p $(SYNTH_DIR)
	$(YOSYS) -p " \
	    read_verilog -sv $(RTL_SRCS); \
	    synth_gowin -top $(TOP_RTL) -json $@; \
	"

## gates: generate a gate-level schematic (SVG) via Graphviz
gates: $(SYNTH_DIR)/gates.svg

$(SYNTH_DIR)/gates.dot: $(RTL_SRCS)
	@mkdir -p $(SYNTH_DIR)
	$(YOSYS) -p " \
	    read_verilog -sv $(RTL_SRCS); \
	    synth_gowin -top $(TOP_RTL); \
	    show -format dot -prefix $(SYNTH_DIR)/gates $(TOP_RTL); \
	"

$(SYNTH_DIR)/gates.svg: $(SYNTH_DIR)/gates.dot
	dot -Tsvg $< -o $@
	@echo "Gate schematic written to $@"

# ─── Place & Route + Bitstream (nextpnr-himbaechel + apycula) ───────────────

## pnr: run Place & Route, generating placement & routing SVGs
pnr: $(SYNTH_DIR)/pnr.json

$(SYNTH_DIR)/pnr.json: $(SYNTH_DIR)/netlist.json $(CST)
	@command -v $(NEXTPNR_GOWIN) >/dev/null 2>&1 || \
	    { echo "ERROR: $(NEXTPNR_GOWIN) not found."; exit 1; }
	$(NEXTPNR_GOWIN) --device $(FPGA_DEVICE) \
	    --vopt family=$(FPGA_FAMILY) \
	    --vopt cst=$(CST) \
	    --json $< \
	    --write $@ \
	    --placed-svg $(SYNTH_DIR)/placed.svg \
	    --routed-svg $(SYNTH_DIR)/routed.svg
	@echo "Placed layout: $(SYNTH_DIR)/placed.svg"
	@echo "Routed layout: $(SYNTH_DIR)/routed.svg"

## bitstream: P&R + pack bitstream for Tang Nano 9K (produces synth/bitstream.fs)
##   Requires: nextpnr-himbaechel (P&R) + apycula (gowin_pack)
bitstream: $(SYNTH_DIR)/bitstream.fs

$(SYNTH_DIR)/bitstream.fs: $(SYNTH_DIR)/pnr.json
	@command -v $(GOWIN_PACK) >/dev/null 2>&1 || \
	    { echo "ERROR: gowin_pack not found — install via 'pip install apycula'."; exit 1; }
	$(GOWIN_PACK) -d $(FPGA_FAMILY) -o $@ $<
	@echo "Tang Nano 9K bitstream written to $@"

## pnr-gui: open nextpnr interactive floorplan GUI (if compiled with Qt)
pnr-gui: $(SYNTH_DIR)/netlist.json $(CST)
	@command -v $(NEXTPNR_GOWIN) >/dev/null 2>&1 || \
	    { echo "ERROR: $(NEXTPNR_GOWIN) not found."; exit 1; }
	$(NEXTPNR_GOWIN) --device $(FPGA_DEVICE) \
	    --vopt family=$(FPGA_FAMILY) \
	    --vopt cst=$(CST) \
	    --json $< \
	    --gui || { \
	        echo ""; \
	        echo "NOTE: $(NEXTPNR_GOWIN) was built in CLI mode without Qt GUI."; \
	        echo "Run 'make pnr' to generate full-chip vector visual files:"; \
	        echo "  - $(SYNTH_DIR)/placed.svg (die floorplan & placement)"; \
	        echo "  - $(SYNTH_DIR)/routed.svg (physical routing paths)"; \
	        exit 1; \
	    }

## flash: program bitstream onto Tang Nano 9K via openFPGALoader
flash: $(SYNTH_DIR)/bitstream.fs
	@command -v $(OPENFPGALOADER) >/dev/null 2>&1 || \
	    { echo "ERROR: openFPGALoader not found."; exit 1; }
	$(OPENFPGALOADER) -b $(BOARD) $<

# ─── Cleanup ────────────────────────────────────────────────────────────────

clean:
	rm -rf obj_dir waveform.vcd $(SYNTH_DIR)
