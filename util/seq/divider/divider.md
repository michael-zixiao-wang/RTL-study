# 偶数分频器
偶数分频是最简单、最安全的分频方式。核心思路是使用一个计数器，当计数到分频系数一半减一的时候，翻转输出时钟。以4分频为例，占空比50%：

```sv
module clk_div_even #(
    parameter DIV_N = 4 // 必须为偶数
)(
    input  wire clk_in,
    input  wire rst_n,
    output reg  clk_out
);
    // 计数器位宽取决于分频系数
    reg [$clog2(DIV_N/2)-1:0] cnt;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt     <= 0;
            clk_out <= 1'b0;
        end else begin
            // 计数到 (N/2) - 1 时清零并翻转时钟
            if (cnt == (DIV_N/2) - 1) begin
                cnt     <= 0;
                clk_out <= ~clk_out;
            end else begin
                cnt     <= cnt + 1;
            end
        end
    end
endmodule
```
架构剖析：
- 优点： 
    1. 100% 同步设计： 完全依赖 posedge clk_in，时序路径极其干净。
    2. 完美的 50% 占空比： 无需任何特殊处理。
    3. 无毛刺（Glitch-free）： 输出是由触发器（DFF）直接打出来的，绝对不会有组合逻辑毛刺。
- 缺点： 逻辑产生的分频时钟在物理走线上与源时钟存在不可避免的插入延迟，跨时钟域时需要特别注意相位对齐问题。

# 奇数分频器

**奇数分频的难点在于如何实现完美的 50% 占空比。**如果不需要 50% 占空比，只需像偶数分频一样计数即可。但如果硬性要求 50%，就必须同时利用源时钟的上升沿和下降沿。以3分频为例，实现 50% 占空比：

```sv
module clk_div_odd #(
    parameter DIV_N = 3 // 必须为奇数
)(
    input  wire clk_in,
    input  wire rst_n,
    output wire clk_out
);

    reg [$clog2(DIV_N)-1:0] cnt;
    reg clk_pos; // 上升沿生成的时钟
    reg clk_neg; // 下降沿生成的时钟

    // 1. 模 N 计数器 (上升沿触发)
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
        end else if (cnt == DIV_N - 1) begin
            cnt <= 0;
        end else begin
            cnt <= cnt + 1;
        end
    end

    // 2. 上升沿生成占空比为 (N-1)/(2N) 的高电平
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            clk_pos <= 1'b0;
        // 在 cnt = 0 到 (DIV_N-1)/2 - 1 期间拉高 (对3分频而言，只有cnt=0时拉高)
        end else if (cnt < (DIV_N+1)/2 - 1) begin 
            clk_pos <= 1'b1;
        end else begin
            clk_pos <= 1'b0;
        end
    end

    // 3. 下降沿将 clk_pos 打一拍 (平移半个源时钟周期)
    always @(negedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            clk_neg <= 1'b0;
        end else begin
            clk_neg <= clk_pos;
        end
    end

    // 4. 逻辑或 (拼接出完美的 50% 占空比)
    // 3分频中，clk_pos 高 1 个周期，clk_neg 高 1 个周期，交叠错开半个周期。
    // 总高电平时间 = 1.5 个源时钟周期，1.5 / 3 = 50%
    assign clk_out = clk_pos | clk_neg;

endmodule

```

架构深度剖析：

- 优点： 通过上升沿和下降沿的巧妙拼接，实现了严丝合缝的 50% 占空比。这在某些要求严格占空比的模拟电路接口或双沿采样（DDR）总线中非常有用。
- 致命缺点： 
    1. 引入了 negedge clk_in。在 ASIC/FPGA 综合时，上升沿和下降沿混合使用会极大地增加时钟树综合的难度，容易引发时序违例。
    2. 输出 clk_out 是经过组合逻辑（或门 |）输出的。虽然理论上无毛刺，但在物理连线中，如果 clk_pos 和 clk_neg 到达或门的延迟不一致，输出端就会产生细微的毛刺。

# 小数分频器
在数字逻辑中，我们无法把一个时钟波形均匀地切成小数（比如 4.5 个周期翻转一次，这是物理上做不到的）。小数分频的物理本质是吞脉冲技术，例如实现 4.5 分频，就是让电路在 4 分频和 5 分频之间交替切换。平均下来：(4+5)/2=4.5。

这里提供一种工业界最常用的基于**相位累加器**的小数分频写法，它通常用于生成波特率或音频采样率脉冲。

```sv
module clk_div_fractional #(
    parameter M = 2, // 分子 (输出频率比例)
    parameter N = 9  // 分母 (输入频率比例)
)(
    input  wire clk_in,
    input  wire rst_n,
    output reg  clk_en_out // 注意：这是时钟使能脉冲，不是占空比50%的时钟
);

    // 累加器位宽必须能容纳 N
    reg [$clog2(N):0] acc;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            acc        <= 0;
            clk_en_out <= 1'b0;
        end else begin
            // 每次累加 M。如果累加结果大于等于 N，则溢出并输出一个脉冲
            if (acc + M >= N) begin
                acc        <= acc + M - N; // 保留余数
                clk_en_out <= 1'b1;        // 产生高电平脉冲
            end else begin
                acc        <= acc + M;
                clk_en_out <= 1'b0;
            end
        end
    end

endmodule
```

架构剖析：
- 优点： 可以实现任意精度的小数分频，且完全同步于 clk_in。
- 致命缺点（周期抖动 Jitter）： 它输出的脉冲间隔是不均匀的。以 4.5 分频为例，它会间隔 4 个周期出一个脉冲，然后间隔 5 个周期出一个脉冲。这种不可避免的周期到周期抖动，绝不能直接用来驱动下游触发器的时钟端！

# 关于分频器

在现代 ASIC 和 FPGA 设计中，对于分频器有一个不成文的规定：

永远不要把你用 RTL 逻辑（计数器/组合逻辑）写出来的时钟，直接连到大批量触发器的时钟引脚上。原因在于，逻辑生成的时钟没有经过全局时钟缓冲器，它的扇出能力极差，到达不同触发器的时间会有巨大的时钟偏斜，直接导致系统崩溃。

正确的工业级做法有两种：
- 宏单元调用： 如果需要干净、稳定、50% 占空比、甚至是带相移的时钟，直接调用芯片内部的硬核模拟电路——PLL（锁相环）或 MMCM（混合模式时钟管理器）。
- 时钟使能法（Clock Enable, CE）： 就像上面的小数分频器一样，我们只生成一个**宽度为 1 个源时钟周期**的 enable 脉冲信号。所有下游电路依然统一使用高频的源时钟 clk_in，仅仅将这个分频脉冲作为触发器的使能端输入。

> 至于**倍频器**是完全无法使用RTL实现的，使能通过PLL和MMCM的IP核实现。