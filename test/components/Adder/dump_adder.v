module dump();
	initial begin
		$dumpfile ("fpu_adder.vcd");
		$dumpvars (0, fpu_add_tb);
		#1;
	end
endmodule