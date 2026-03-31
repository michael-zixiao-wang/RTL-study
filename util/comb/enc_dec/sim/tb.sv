module tb();

bit clk;
initial begin clk = 1'b0; forever #5 clk = ~clk; end

bit rst;
initial begin rst = 1'b1; #10 rst = 1'b0; end

  logic [8:0] cnt;

always @(posedge clk, posedge rst)begin
	if(rst)begin
		cnt <= '0;
	end else begin
		cnt <= cnt + 1'b1; 
	end
end

  logic [7:0]onehot;
  logic [2:0]bin;
  assign onehot = cnt;
initial begin
  $dumpfile("dump.vcd");
  $dumpvars(1,tb); // 1 表示记录当前层级的信号
end
initial begin
  repeat(200) @(posedge clk);
  $finish();
end

onehot2bin_case dut(.*);
endmodule
