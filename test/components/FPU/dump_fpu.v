module dump();
	initial begin
		$dumpfile ("fpu.vcd");
		$dumpvars (0, fpu_tb);
		#1;
	end
endmodule