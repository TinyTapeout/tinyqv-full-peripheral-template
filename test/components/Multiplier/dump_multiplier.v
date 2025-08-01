module dump();
	initial begin
		$dumpfile ("fpu_multiplier.vcd");
		$dumpvars (0, fpu_mult_tb);
		#1;
	end
endmodule