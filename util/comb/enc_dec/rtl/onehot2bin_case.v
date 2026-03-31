module onehot2bin_case #(
    parameter BIN_W = 3,
    parameter OH_W  = 8
)(
    input  wire [OH_W-1:0]  onehot,
    output reg  [BIN_W-1:0] bin
);

    always @(*) begin
        bin = {BIN_W{1'b0}}; // 默认值，防止锁存器
        case (1'b1)          // 核心技巧：谁是1就匹配谁
            onehot[0]: bin = 3'd0;
            onehot[1]: bin = 3'd1;
            onehot[2]: bin = 3'd2;
            onehot[3]: bin = 3'd3;
            onehot[4]: bin = 3'd4;
            onehot[5]: bin = 3'd5;
            onehot[6]: bin = 3'd6;
            onehot[7]: bin = 3'd7;
            default:   bin = 3'd0;
        endcase
    end

endmodule
