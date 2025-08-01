MODULE = mult_tests
TOPLEVEL = fpu_mult_tb
VERILOG_SOURCES = "fpu_mult_tb.v, ../../../src/fpu_mult.v"
export MODULE

include $(shell cocotb-config --makefiles)/Makefile.sim

synth:
	yosys -p "read_verilog ../../../src/fpu_mult.v; proc; opt; show -colors 2 -width -signed fpu_mult"

test:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -s fpu_mult_tb -s dump -g2012 dump_multiplier.v ../../../src/fpu_mult.v fpu_mult_tb.v
	PYTHONOPTIMIZE=${NOASSERT} vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml

view:
	gtkwave fpu_multiplier.vcd fpu_multiplier.gtkw
