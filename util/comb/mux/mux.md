# 2/1多路选择器
针对2选1 MUX，主要有以下两种写法：

1. 三元运算符（推荐）
```sv
module mux2to1_assign (
    input  wire a,      // 数据输入 a
    input  wire b,      // 数据输入 b
    input  wire sel,    // 选择信号 (0选a, 1选b)
    output wire out     // 数据输出
);

    assign out = sel ? b : a;

endmodule
```
这种方法实现起来非常简洁，并且可读性很高。

2. 行为级建模

主要是利用if-else或者case实现，以if-else为例：
```sv
module mux2to1_ifelse (
    input  wire a,
    input  wire b,
    input  wire sel,
    output reg  out     // 注意：always块内赋值必须是reg类型
);

    always @(*) begin   // @(*) 自动包含所有输入信号到敏感列表
        if (sel == 1'b1) begin
            out = b;
        end else begin
            out = a;
        end
    end

endmodule
```
这种写法冗余很多，针对2/1这种简单情况非常不推荐。

# 4/1多路选择器

对于这种情况，反倒需要推荐行为级建模了，并且推荐使用case，如下所示:

1. 行为级建模 （推荐）
```sv
module mux4to1_case (
    input  wire [3:0] in,   // 将4个输入打包成一个总线
    input  wire [1:0] sel,  // 2位选择信号
    output reg  out
);

    always @(*) begin
        case (sel)
            2'b00: out = in[0];
            2'b01: out = in[1];
            2'b10: out = in[2];
            2'b11: out = in[3];
            default: out = 1'b0; // 必须写default！
        endcase
    end

endmodule
```

这样写是非常直观的硬件映射关系，并且**case 语句在综合时会非常直接地映射为平级的 MUX 结构，所有输入到输出的延迟（Delay）理论上是相同的（路径对称）。**

当然，也可以使用三元运算符实现，只不过繁琐许多，如下所示：

2. 嵌套三元运算符

```sv
module mux4to1_ternary (
    input  wire a, b, c, d,
    input  wire [1:0] sel,
    output wire out
);

    // 逻辑：sel[1]决定选高两位还是低两位，sel[0]决定选具体的哪一个
    assign out = sel[1] ? (sel[0] ? d : c) : (sel[0] ? b : a);

endmodule
```

> 其他多级多路选择器与4选1多路选择器类似，推荐直接写case。

# 2/1搭建4/1MUX

主要是通过MUX的级联实现，如下所示：
<img src=./image/1.png>

对应代码如下：
```sv
module mux4to1_tree (
    input  wire a, b, c, d,
    input  wire [1:0] sel,
    output wire out
);

    wire mux_low;  // 底层第一个MUX的输出
    wire mux_high; // 底层第二个MUX的输出

    // 第一级 MUX：分别处理 (a,b) 和 (c,d)
    assign mux_low  = sel[0] ? b : a;
    assign mux_high = sel[0] ? d : c;

    // 第二级 MUX：处理第一级的输出
    assign out      = sel[1] ? mux_high : mux_low;

endmodule
```

这样做其实相对繁琐，但是显然拥有明确的时序关系，相当于我们人工通过构建平衡的二叉树，可以保证所有数据到达输出的组合逻辑级数一致，避免了某些路径延迟过大。但是现在的综合器完全有能力解决这个问题。

# MUX作为逻辑门

底层逻辑在于 2选1 MUX 的布尔代数表达式为：Out=Sel⋅B+~Sel⋅A (假设 Sel=1 选 B， Sel=0 选 A)。

- 非门 (NOT)： 将 Sel 接输入信号，引脚 A 接 1'b1，引脚 B 接 1'b0。
- 与门 (AND)： 将 Sel 接输入信号 X，引脚 A 接 1'b0，引脚 B 接输入信号 Y。
- 或门 (OR)： 将 Sel 接输入信号 X，引脚 A 接输入信号 Y，引脚 B 接 1'b1。
- 异或门 (XOR)： 将 Sel 接输入信号 X，引脚A接输入信号Y，引脚B接~Y（需要额外一个非门，或用另一个 MUX 实现的非门）。

这里还涉及到了一个FPGA的面试问题，你可能会被问到**MUX和LUT的关系**:

FPGA 中并没有大量的真实逻辑门，它实现组合逻辑的核心是 LUT。一个 4 输入的 LUT，本质上就是一个包含 16 个存储单元（SRAM）的存储器，加上一个 16选1 的大 MUX。4个输入信号其实就是这棵 16选1 MUX 树的选择控制端 (Select Lines)，而那 16 个 SRAM 里存的值（0 或 1），就是 MUX 的数据输入端。理解了这一点，你就看透了 FPGA 组合逻辑的本质。

