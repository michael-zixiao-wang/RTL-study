# 普通全加器

全加器负责处理三个单 bit 信号的相加：加数 A、被加数 B 以及来自低位的进位 Cin​，输出本位和 Sum 以及向高位的进位 Cout​。

1. 布尔逻辑门级映射
```sv
module full_adder_gates (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);

    // Sum 是三个输入的异或
    assign sum  = a ^ b ^ cin;
    // Cout 逻辑：任意两个及以上输入为 1，则进位为 1
    assign cout = (a & b) | (a & cin) | (b & cin);

endmodule
```

2. 数据流建模拼接
```sv
module full_adder_assign (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);

    // {cout, sum} 组成了一个 2-bit 的结果
    assign {cout, sum} = a + b + cin;

endmodule
```

# 行波进位加法器 (Ripple Carry Adder, RCA)
当我们需要处理多位数据（例如 64-bit 操作数）时，最直观的想法就是把多个全加器像链条一样串联起来。低位的 Cout​ 连到高位的 Cin​。

```sv
module ripple_carry_adder #(
    parameter WIDTH = 64
)(
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire             cin,
    output wire [WIDTH-1:0] sum,
    output wire             cout
);

    wire [WIDTH:0] carry; // 内部进位链
    assign carry[0] = cin;
    assign cout     = carry[WIDTH];

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : gen_fa
            // 实例化基础全加器
            full_adder_assign u_fa (
                .a   (a[i]),
                .b   (b[i]),
                .cin (carry[i]),
                .sum (sum[i]),
                .cout(carry[i+1])
            );
        end
    endgenerate

endmodule
```

- 优点： 面积极小。 消耗的硬件资源与位宽 N 成正比（O(N) 复杂度）。
- 缺点： 进位依赖导致的极长延迟。 第 i 位的全加器必须等待第 i−1 位的进位算完才能得出结果。整个电路的延迟是 O(N)。在 64 位架构中，高位必须等待前面 63 个全加器像波浪一样把进位传过来，根本无法满足高性能处理器的频率要求。

# 超前进位加法器 (Carry Lookahead Adder, CLA)

为了打破 RCA 的进位链条，我们需要让高位的进位不再依赖低位的层层传递，而是“并行”计算出来。这需要引入两个核心概念：

- 生成信号 (Generate, Gi​)： Gi​=Ai​⋅Bi​。如果两个输入都是 1，必定产生进位，与低位无关。
- 传播信号 (Propagate, Pi​)： Pi​=Ai​⊕Bi​。如果两个输入一个是 1 一个是 0，只要低位有进位传过来，本位就会把进位“传播”到高位。

进位公式可以展开为：Ci+1​=Gi​+Pi​⋅Ci​。通过不断代入，可以在不等待中间进位的情况下，直接用原始输入 A、B 和初始 Cin​ 算出任意位的进位。

```sv
// 以 4-bit CLA 的核心进位逻辑为例
module carry_lookahead_logic_4bit (
    input  wire [3:0] p, // Propagate
    input  wire [3:0] g, // Generate
    input  wire       c0,
    output wire [4:1] c
);

    // 纯并行组合逻辑展开，没有任何级联等待！
    assign c[1] = g[0] | (p[0] & c0);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c0);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c0);
    assign c[4] = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]) | (p[3] & p[2] & p[1] & p[0] & c0);

endmodule
```

> 在真正从事数字前端设计时，除非你是专门开发标准单元库或极度定制化算术 IP 的底层工程师，否则我们几乎从来不会手动去手撕一个 64 位的 CLA 或是更复杂的 Kogge-Stone 树形加法器。

现代 EDA 综合工具非常强大,因为一个单纯的 + 号，在综合工具眼里是一个“未绑定的宏单元”。
- 如果你给的时钟约束很宽松（比如 10MHz），工具为了省面积，会自动把这个 + 综合成最便宜的 RCA（行波进位加法器）。
- 如果你给的时钟约束极度紧绷（比如 1GHz，甚至还要在单周期内完成浮点加法前的对齐计算），工具为了保时序，会自动调用 DesignWare 库中极其庞大、速度极快的 Carry-Select Adder (进位选择加法器) 或 Prefix Adder (并行前缀加法器)。

# 减法器

减法器完全可以由加法器**复用**而来，如下推导：
A−B=A+(−B)=A−B=A+~B+1

仔细观察上面的最终公式 A+B+1，我们需要三个元素：
1. 操作数 A（直接输入给加法器）。
2. 操作数 B 的反码 B。
3. 一个额外的 +1。

**复用逻辑1**：利用异或门（XOR）处理操作数 B
异或门有一个极其重要的特性：
1. 任何数与 0 异或，等于它本身（B⊕0=B）。
2. 任何数与 1 异或，等于按位取反（B⊕1=~B）。
所以，我们只需要把操作数 B 的每一位都和 sub_ctrl(sub使能信号) 进行异或，就可以在硬件上完美实现加法时原样输入，减法时按位取反！

**复用逻辑2**：利用全加器的进位输入（Cin​）处理 +1
我们直接把 sub_ctrl 信号接到这个 Cin​ 上。
- 加法时，sub_ctrl = 0，相当于 A+B+0，完美。
- 减法时，sub_ctrl = 1，相当于 A+~B+1，刚好补齐了那个末位加一。

# 溢出位

## 无符号溢出
无符号数没有符号位，所有 bit 都用来表示数值大小。它的溢出条件只和**最高位的进位输出（Cout​）**有关。

1. 加法溢出条件：
很简单，如果两个数相加，超出了当前位宽能表示的最大值，最高位就会向外产生一个进位。
- 条件： Cout​=1 （发生溢出）

2. 减法借位条件（极其反直觉）：
前面我们推导过，减法在硬件里是 A+~B+1。
在无符号减法 A−B 中：
- 如果 A ≥ B（够减）：硬件加法器反而会产生一个进位 Cout​=1。这表示“没有发生借位”。
- 如果 A < B（不够减）：硬件加法器不会产生进位 Cout​=0。这反而表示“发生了借位（Underflow）”。

对于无符号加减法，判断溢出/借位的逻辑是：
```sv
// sub_ctrl 为 0 表示加法，为 1 表示减法
// cout 是加法器最高位产生的物理进位
assign unsigned_overflow = sub_ctrl ? (~cout) : cout;
```

## 有符号溢出
有符号数使用最高位作为符号位（0 为正，1 为负）。有符号溢出的核心物理意义是：运算结果的符号，违背了数学常理。

条件判定（符号突变法）：
正数加负数，结果一定在两者之间，绝对不可能溢出。
溢出只可能发生在“同号相加”的情况下：
- 正 + 正 = 负： 两个正数相加，结果的最高位（符号位）变成了 1。
- 负 + 负 = 正： 两个负数相加，结果的最高位（符号位）变成了 0。

(注意：减法 A−B 已经被我们转换成了 A+~B+1，所以我们只需要看参与真正加法运算的 A 和 ~B 的符号位即可。)

硬件实现方法一：比较符号位
设 Amsb​ 为操作数 A 的符号位，Beff_msb​ 为送入加法器的 B 的有效符号位（加法时是 Bmsb​，减法时是 ∼Bmsb​），Summsb​ 为最终结果的符号位。
```sv
// 只有当 A 和 B_eff 符号相同，且与 Sum 符号不同时，才发生有符号溢出
assign signed_overflow = (a[WIDTH-1] == b_eff[WIDTH-1]) && (a[WIDTH-1] != sum_ext[WIDTH-1]);
```

硬件实现方法二：异或次高位进位
底层逻辑推导发现，有符号溢出发生时，必然满足一个条件：最高位产生的进位（Cout​），与次高位向最高位传递的进位（Cin_MSB​）不相等！
这就引出了一个极其优雅的门级实现，只需要一个异或门：Overflow=Cout​⊕Cin_MSB​。