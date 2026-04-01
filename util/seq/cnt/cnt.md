# 二进制计数器

这是所有数字系统中最基础、最直观的计数器。它按照自然二进制序列递增或递减。
```sv
module binary_counter #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n, // 异步复位，低电平有效
    input  wire             en,    // 计数使能
    input  wire             clr,   // 同步清零 (优先级高于使能)
    output reg  [WIDTH-1:0] cnt
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= {WIDTH{1'b0}};
        end else if (clr) begin
            cnt <= {WIDTH{1'b0}};
        end else if (en) begin
            cnt <= cnt + 1'b1;
        end
    end

endmodule
```

架构剖析

- 优点：
    - 极致的资源利用率： N 个触发器可以完美表示 2^N 个状态，一点也不浪费。
    - 算术友好： 可以非常方便地进行加减法、大小比较。底层的硬件映射就是一个加法器加上一组寄存器。
- 致命缺点（物理特性）：
    - 多位同时跳变： 当计数器从 0111 变为 1000 时，4 个 bit 必须在同一个时钟边沿同时翻转。这不仅会带来较大的动态瞬态功耗，还极易在下游的组合逻辑译码电路中产生毛刺。
    - 跨时钟域灾难： 绝对不能将二进制计数器的值直接跨时钟域传递！由于布线延迟不同，多位同时跳变在目标时钟域被采样时，极大概率会采到错乱的中间态。

# 格雷码计数器

为了解决二进制计数器“多位同时翻转”的物理缺陷，格雷码计数器应运而生。它的核心要求是：每一次时钟触发，输出的值只能有 1 个 bit 发生状态翻转。这是异步 FIFO 读写指针设计中绝对的灵魂组件。

纯粹的格雷码加法逻辑极其复杂（因为格雷码本身不支持直接相加）。工业界最标准的做法是：内部维护一个二进制计数器进行加法，然后将其转换为格雷码再输出。

```sv
module gray_counter #(
    parameter WIDTH = 4
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    output reg  [WIDTH-1:0] gray_out
);

    // 内部维护的二进制计数器
    reg  [WIDTH-1:0] bin_cnt;
    wire [WIDTH-1:0] next_bin;
    wire [WIDTH-1:0] next_gray;

    // 1. 二进制加法逻辑
    assign next_bin = en ? (bin_cnt + 1'b1) : bin_cnt;

    // 2. 二进制转格雷码逻辑 (利用错位异或)
    assign next_gray = next_bin ^ (next_bin >> 1);

    // 3. 寄存器打拍输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_cnt  <= {WIDTH{1'b0}};
            gray_out <= {WIDTH{1'b0}};
        end else begin
            bin_cnt  <= next_bin;
            gray_out <= next_gray; // 输出寄存器化，保证无毛刺
        end
    end

endmodule
```

- 优点：
    - 单比特翻转： 每次状态更新只有一根线上的电平发生变化。即使在跨时钟域时发生亚稳态采样偏差，采到的结果要么是前一个周期的旧值，要么是当前周期的新值，绝对不会出现未知的灾难性错误状态。
    - 低功耗： 翻转率低，动态功耗显著小于二进制计数器。
- 缺点：
    - 面积惩罚： 相比纯二进制计数器，它多出了一组寄存器（bin_cnt）以及由异或门构成的转换逻辑。
    - 算术盲区： 外部逻辑无法直接对输出的 gray_out 进行加减或大小比较，必须先做 G2B（格雷转二进制）解码。

# BCD 码计数器

BCD 码计数器（又称十进制计数器）采用 4 个 bit 来表示 0~9 的十进制数。当计数值达到 9 (1001) 时，下一个时钟周期它会清零，并向更高位的 BCD 计数单元产生一个进位。在RTL上往往通过级联实现，这里展示一个两位（可以计数 00~99）的 BCD 计数器：

```sv
module bcd_counter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [3:0] digit_0, // 个位 (0~9)
    output reg  [3:0] digit_1, // 十位 (0~9)
    output wire       cout     // 向百位的进位
);

    // 个位计数逻辑
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            digit_0 <= 4'd0;
        end else if (en) begin
            if (digit_0 == 4'd9) begin
                digit_0 <= 4'd0; // 逢十进一
            end else begin
                digit_0 <= digit_0 + 1'b1;
            end
        end
    end

    // 十位计数逻辑 (只有当个位为9且使能时，十位才加1)
    wire en_digit_1 = en & (digit_0 == 4'd9);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            digit_1 <= 4'd0;
        end else if (en_digit_1) begin
            if (digit_1 == 4'd9) begin
                digit_1 <= 4'd0;
            end else begin
                digit_1 <= digit_1 + 1'b1;
            end
        end
    end

    // 产生全局进位脉冲 (99 变 00 的瞬间)
    assign cout = en & (digit_0 == 4'd9) & (digit_1 == 4'd9);

endmodule
```

- 优点：人机交互便利，其输出可以直接送给七段数码管的译码器，或者 LCD 驱动器，无需经过极其消耗资源的“二进制转十进制（除法/取余或 Double-Dabble 算法）”模块。
- 缺点：
    - 资源浪费： 4 个 bit 物理上可以存 16 个状态，但 BCD 强制废弃了 1010 到 1111 这 6 个状态（冗余状态）。如果是表示 0~999，纯二进制只需 10 bit (210=1024)，而 BCD 码需要 3 个分组共 12 bit。
    - 最高主频受限： 进位链长（en_digit_1 依赖于 digit_0 的比较结果），在大位宽下（如 8 位十进制计数），组合逻辑的延迟会急剧增加。