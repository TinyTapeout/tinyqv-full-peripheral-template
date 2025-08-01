MODULE = fpu_tests
TOPLEVEL = fpu_tb
VERILOG_SOURCES = "fpu_tb.v, ../../../src/fpu_mult.v", ../../../src/fpu_add.v", ../../../src/tqvp_dsatizabal_fpu.v"
export MODULE

include $(shell cocotb-config --makefiles)/Makefile.sim

synth:
	yosys -p "read_verilog ../../../src/tqvp_dsatizabal_fpu.v ../../../src/fpu_mult.v ../../../src/fpu_add.v; proc; opt; show -colors 2 -width -signed tqvp_dsatizabal_fpu"

test:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -s fpu_tb -s dump -g2012 ../../../src/tqvp_dsatizabal_fpu.v dump_fpu.v ../../../src/fpu_mult.v ../../../src/fpu_add.v fpu_tb.v
	PYTHONOPTIMIZE=${NOASSERT} vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml

view:
	gtkwave fpu.vcd fpu.gtkw
