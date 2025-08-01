MODULE = add_tests
TOPLEVEL = fpu_add_tb
VERILOG_SOURCES = "fpu_add_tb.v, ../../../src/fpu_add.v"
export MODULE

include $(shell cocotb-config --makefiles)/Makefile.sim

synth:
	yosys -p "read_verilog ../../../src/fpu_add.v; proc; opt; show -colors 2 -width -signed fpu_add"

test:
	rm -rf sim_build/
	mkdir sim_build/
	iverilog -o sim_build/sim.vvp -s fpu_add_tb -s dump -g2012 dump_adder.v ../../../src/fpu_add.v fpu_add_tb.v
	PYTHONOPTIMIZE=${NOASSERT} vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus sim_build/sim.vvp
	! grep failure results.xml

view:
	gtkwave fpu_adder.vcd fpu_adder.gtkw
