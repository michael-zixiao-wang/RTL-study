# LZC和LOC
前导零计数器（Leading Zero Counter, LZC）和前导一计数器（Leading One Counter, LOC）是现代高性能微处理器中绝对不可或缺的算术组件。在浮点运算（FPU）的规格化（Normalization）阶段，或者在执行类似 RISC-V 架构中的 CLZ（Count Leading Zeros）指令时，它们直接决定了关键路径的延迟。

在工程实践中，LOC 不需要单独设计。因为一个数值的前导一数量，完全等于它按位取反后的前导零数量。即 LOC(in) = LZC(~in)。因此，我们只需要倾注全力将 LZC 的微架构优化到极致即可。

# LZC和TZC
尾随零(Tail Zero Counter, TZC)同样，只需要先将输入先反转，随后送入LZC模块即可产生尾随零的模块代码。

# 行为级建模的LZC

```sv
module lzc_for #(
    parameter WIDTH = 32,
    parameter COUNT_W = $clog2(WIDTH) + 1 
)(
    input  wire [WIDTH-1:0] in,
    output reg  [COUNT_W-1:0] count
);

    integer i;
    reg     found; // 用于标记是否已经找到第一个 1

    always @(*) begin
        count = WIDTH; // 默认值为全 0 的情况
        found = 1'b0;
        
        // 从最高位向最低位扫描
        for (i = WIDTH - 1; i >= 0; i = i - 1) begin
            if (!found && in[i]) begin
                count = (WIDTH - 1) - i;
                found = 1'b1; // 找到后锁定，后续循环不再更新 count
            end
        end
    end

endmodule
```

优点：
- 代码极其简洁，逻辑可读性满分。
- 完美支持参数化。无论位宽是 16 还是 128，代码只需改一个参数。
致命缺点：
- 综合工具会将这种带有“锁定”标志 (found) 的顺序循环，展开成一条极其漫长的优先级多路选择器链。（现代综合工具偶尔能把简单的 for 循环智能优化成树状结构，但不能完全依赖它）
- 第 i 位的判断必须等待第 i+1 位的判断结果。如果是 64 位 LZC，信号要穿过 64 级级联的逻辑门。它的延迟是 O(N)。在高性能 CPU 中，这种写法一旦放入组合逻辑的单周期关键路径，时序会立刻爆炸。

# 结构化建模的LZC

核心思想是：将大位宽的输入一分为二，左半部分和右半部分并行计算它们自己的前导零个数。然后用极少量的逻辑门，将这两个结果合并成总结果。
我们先看基础的 2-bit LZC（叶子节点），然后再看如何将它们组合成 4-bit、8-bit 直至更大位宽（树干节点）。
1. 叶子节点：2-bit LZC
```sv
// 2-bit 前导零计数器
module lzc_2bit (
    input  wire [1:0] in,
    output wire [1:0] count, // 计数值：00(0个), 01(1个), 10(2个全零)
    output wire       vld    // 有效位：为1表示区间内全为0
);

    // 逻辑极其简单，直接用真值表映射出最简组合逻辑
    assign vld = ~(in[1] | in[0]);
    assign count[1] = vld;
    assign count[0] = ~in[1] & in[0]; 

endmodule
```

2. 树干节点：利用子模块合并（以 4-bit 为例）

```sv
// 4-bit 前导零计数器（由两个 2-bit 拼成）
module lzc_4bit (
    input  wire [3:0] in,
    output wire [2:0] count,
    output wire       vld
);

    wire [1:0] cnt_h, cnt_l; // 高2位和低2位的计数值
    wire       vld_h, vld_l; // 高2位和低2位的全零标志

    // 1. 并行实例化两个 2-bit LZC
    lzc_2bit u_lzc_h (.in(in[3:2]), .count(cnt_h), .vld(vld_h));
    lzc_2bit u_lzc_l (.in(in[1:0]), .count(cnt_l), .vld(vld_l));

    // 2. 合并逻辑（核心精髓）
    // 如果高段全为0 (vld_h == 1)，说明前导零数量 = 高段长度(2) + 低段前导零数量
    // 如果高段不全为0 (vld_h == 0)，说明前导零就在高段里，直接等于高段的计数值
    
    assign vld = vld_h & vld_l; // 只有高低都全0，整体才全0
    
    // 最高位指示是否跨越了高半区（即高半区全0）
    assign count[2] = vld_h & vld_l; 
    
    // 剩余的位：如果高区全0，接管低区计数；否则使用高区计数
    assign count[1:0] = vld_h ? (2'b10 + cnt_l) : cnt_h; 

endmodule
```
- 优点（速度的极致）：
    通过并行的二叉树结构，无论位宽多大，底层的各个小模块都在同时进行运算。64 位的 LZC 只需要经过 log2​(64)=6 级 MUX 树。其延迟由级联的 O(N) 暴降至树状的 O(logN)。这是在极高频时钟下实现浮点规格化的唯一解法。
- 缺点：
    代码编写较为繁琐，层级较多。
    要实现完美的任意位宽参数化（比如一个位宽为 53 这种非 2 的幂次方的 LZC）需要非常高阶的 SystemVerilog generate 递归语法，对代码功底要求极高。