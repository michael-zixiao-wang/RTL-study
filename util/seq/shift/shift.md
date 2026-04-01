# 移位寄存器通识

在硬件设计中，根据数据流向和逻辑特性的不同，移位寄存器主要分为以下几个大类。
## 基础数据流向型（接口与协议的核心）
- SIPO (串入并出)： 数据一个一个周期串行进来，攒够一个 Word（比如 8-bit 或 32-bit）后，并行输出给内部总线。常用于接收端的解串器 (Deserializer)。
- PISO (并入串出)：  内部总线把一个 Word 并行拍进寄存器，然后在后续周期里一位一位串行吐出去。常用于发送端的串行器 (Serializer)。
- SISO (串入串出)： 数据串行进、串行出，主要用于打拍延迟线 (Delay Line)，让数据在流水线中“飞”几个周期，以对齐其他控制信号。
- 通用移位寄存器 (Universal Shift Register)： 带有模式选择端，可以配置为左移、右移、并行加载或保持不变。多用于早期的多周期状态机中。

> 注：并入并出 (PIPO) 本质上就是最普通的寄存器组（Regfile）或流水线级，通常不再特意强调其“移位”属性。

## 带有反馈的高阶型（算法与序列生成核心）

- 环形计数器 (Ring Counter)： 尾部输出直接连回头部输入。用于生成干净的独热码 (One-Hot Code) 状态序列，适合做极高速的高频轮询仲裁。
- 约翰逊计数器 (Johnson Counter/扭环计数器)：  尾部反相输出连回头部输入。产生相邻状态仅有一位翻转的代码，具有极佳的抗毛刺和低功耗特性，常用于分频器。
- LFSR (线性反馈移位寄存器)：  将特定的几位（抽头）异或后反馈到输入端。它是数字芯片中的 **“伪随机数生成器”** ，是芯片内建自测试（BIST）、PCIe 加扰解扰、CRC 校验的绝对底层核心。

# 基础数据流型移位寄存器

## SIPO型
SISO 的逻辑最简单，数据从一端串行进入，经过 N 个时钟周期后从另一端串行输出。

```sv
module siso_shift_reg #(
    parameter DEPTH = 4 // 延迟打拍的级数
)(
    input  wire clk,
    input  wire rst_n,
    input  wire din,    // 串行输入
    output wire dout    // 串行输出
);

    // 内部寄存器链
    reg [DEPTH-1:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {DEPTH{1'b0}};
        end else begin
            // 数据从最低位进入，向高位移位 (左移写法)
            shift_reg <= {shift_reg[DEPTH-2:0], din};
        end
    end

    // 输出最高位
    assign dout = shift_reg[DEPTH-1];

endmodule
```
- 硬件映射： 综合出来就是首尾相连的一串 D 触发器（DFF）。
- 优缺点与应用：
    - 优点： 面积极小，无需任何复杂的控制逻辑。
    - 核心应用：打拍延迟线。 在复杂的流水线中，如果数据通路计算需要 4 个周期，而与之配套的某个控制信号需要和结果同时到达终点，我们就会用一个 DEPTH=4 的 SISO 把控制信号“暂存” 4 个周期，完美实现时序对齐。

## SIPO型
SIPO 负责把线缆上连串飞过来的单 bit 数据，收集拼装成一个完整的并行 Word（如 8-bit 或 32-bit），供内部总线读取。他是协议接收端 (Rx) 的核心解串器。

```sv
module sipo_shift_reg #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,   // 移位使能信号 (常用于波特率对齐)
    input  wire             din,  // 串行输入
    output wire [WIDTH-1:0] dout  // 并行输出
);

    reg [WIDTH-1:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {WIDTH{1'b0}};
        end else if (en) begin
            // 假设协议规定高位先发 (MSB First)
            // 新来的 bit 放在最低位，老数据不断向高位推
            shift_reg <= {shift_reg[WIDTH-2:0], din};
            
            // 如果是低位先发 (LSB First)，写法会变成：
            // shift_reg <= {din, shift_reg[WIDTH-1:1]};
        end
    end

    assign dout = shift_reg;

endmodule
```
- 硬件映射： 一组 D 触发器，每个触发器的输出不仅连给下一个触发器，还全部引出作为并行总线。
- 工程考点： SIPO 本身非常简单，但在实际项目中，你面临的最大挑战是“组帧 ”。总线一直在跑，SIPO 一直在移位，芯片内部的逻辑怎么知道什么时候这 8 个 bit 刚好拼成了一个有效的数据？因此，SIPO 永远不可能单独工作，它的旁边一定配有一个**计数器或状态机**，当移满 8 次时，产生一个 rx_valid 脉冲，告诉后级电路赶紧把并口数据取走。

## PISO型

与 SIPO 相反，内部总线把一包数据砸给 PISO，PISO 负责在接下来的时钟里，把它一位一位地挤到发信通道上。它是协议发送端 (Tx) 的核心串行器。

```sv
module piso_shift_reg #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             load, // 高电平：并行加载；低电平：开始串行移位
    input  wire [WIDTH-1:0] pin,  // 并行输入
    output wire             dout  // 串行输出
);

    reg [WIDTH-1:0] shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= {WIDTH{1'b0}};
        end else if (load) begin
            // 优先执行并行加载
            shift_reg <= pin;
        end else begin
            // 执行串行移位 (MSB First，高位先出)
            // 最低位补 0 (或补 1，取决于协议空闲态)
            shift_reg <= {shift_reg[WIDTH-2:0], 1'b0};
        end
    end

    // 始终输出移位寄存器的最高位
    assign dout = shift_reg[WIDTH-1];

endmodule
```

- 硬件映射： 每个 D 触发器的输入端多了一个 2选1 MUX（用于选择是接收前一个触发器的值，还是接收外部的并行总线数据）。
- 优缺点与应用：
    - 这是 SPI MOSI 线、UART TX 线的标准驱动电路。
    - 关键点： load 信号的优先级必须高于移位操作。在工程中，往往也是由一个发送状态机来控制 load 信号的拉高时机。

## 通用移位寄存器

它把保持、左移、右移、并行加载全部整合在了一起，通常使用一个 2-bit 的模式选择信号（Mode）来控制。

```sv
module universal_shift_reg #(
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [1:0]       mode, // 00:保持, 01:左移, 10:右移, 11:并行加载
    input  wire             din_l,// 左移时的串行数据输入 (从右边进)
    input  wire             din_r,// 右移时的串行数据输入 (从左边进)
    input  wire [WIDTH-1:0] pin,  // 并行数据输入
    output reg  [WIDTH-1:0] dout  // 寄存器输出
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {WIDTH{1'b0}};
        end else begin
            case (mode)
                2'b00: dout <= dout;                           // 保持不变
                2'b01: dout <= {dout[WIDTH-2:0], din_l};       // 逻辑左移 (LSB进din_l)
                2'b10: dout <= {din_r, dout[WIDTH-1:1]};       // 逻辑右移 (MSB进din_r)
                2'b11: dout <= pin;                            // 并行加载
                default: dout <= dout;
            endcase
        end
    end

endmodule
```

硬件分析与取舍：
- 为了支持这么多功能，综合工具会在每一个 D 触发器的前面，都放置一个巨大的 4选1 MUX。
- 缺点： 极其浪费面积。在现代芯片的接口设计中，我们追求的是“专管专用”。如果只是做 UART 发送，就老老实实写一个带 Load 功能的左移 PISO 即可，绝对不会去例化一个通用移位寄存器。
- 应用场景： 它更像是早期分立逻辑元器件（如 74LS194 芯片）时代的产物，或者用于一些极度资源受限、需要用同一个寄存器分时复用完成多种复杂算法的微控制器（MCU）中。

# 带有反馈的高阶型移位寄存器
普通的移位寄存器只是数据的搬运工，而一旦引入了反馈（将输出端连回输入端），移位寄存器就瞬间发生蜕变，成为了不需要外部数据输入的自治状态机。

## 环形计数器
环形计数器的原理最简单：把移位寄存器的最高位输出（MSB），直接连回最低位输入（LSB）。它在复位时必须被赋予一个且仅有一个 1（或者一个 0），这个状态会在寄存器链中无限循环。
```sv
module ring_counter #(
    parameter WIDTH = 4
)(
    input  wire             clk,
    input  wire             rst_n,
    output reg  [WIDTH-1:0] out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 致命考点：复位时必须且只能塞入一个 1
            // 写法：高 WIDTH-1 位为 0，最低位为 1
            out <= { {WIDTH-1{1'b0}}, 1'b1 }; 
        end else begin
            // 最高位移入最低位，其余左移
            out <= {out[WIDTH-2:0], out[WIDTH-1]};
        end
    end

endmodule
```
架构剖析：
- 优点（极速译码）： 它是天生的独热码发生器。如果用普通的二进制计数器（00, 01, 10, 11），你需要外加译码电路才能选中对应的设备。而环形计数器不需要任何外围组合逻辑，输出的每一根线直接就是一个独立状态的使能信号。因此，它的运行频率可以推到极高，常用于 CPU 内部极高速的**轮询仲裁**或极简指令周期的节拍发生器。
- 缺点（状态浪费）： N 个触发器本来可以表示 2N 个状态，但环形计数器只能表示 N 个状态。面积效率极低。
- 工程隐患（死锁陷阱）： 如果因为宇宙射线或电源噪声（单粒子翻转 SEU），导致寄存器里突然多出了一个 1（变成了 0101），它将永远在这个错误状态里循环，无法自恢复。在工业级的高可靠性设计中，纯粹的环形计数器通常会外加“自纠错逻辑”。

## 约翰逊计数器 (扭环计数器)
为了改善环形计数器极其低下的状态利用率，约翰逊计数器做了一个巧妙的改动：把最高位输出取反后，连回最低位输入。
```sv
module johnson_counter #(
    parameter WIDTH = 4
)(
    input  wire             clk,
    input  wire             rst_n,
    output reg  [WIDTH-1:0] out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时可以全 0 启动
            out <= {WIDTH{1'b0}};
        end else begin
            // 最高位取反后移入最低位，其余左移
            out <= {out[WIDTH-2:0], ~out[WIDTH-1]};
        end
    end

endmodule
```

架构剖析：

- 状态翻转过程： 假设 WIDTH=4，状态变化为：0000 → 0001 → 0011 → 0111 → 1111 → 1110 → 1100 → 1000 → 0000。
- 优点（无毛刺 & 容量翻倍）：
    - 状态数从环形计数器的 N 增加到了 2N（4 个触发器产生 8 个状态），面积效率提升了一倍。
    - 它具备“格雷码”的特性。 任意相邻的两个状态之间，永远只有一位发生翻转。这使得我们在对其进行组合逻辑译码时，绝对不会产生毛刺。
- 应用场景： 这是生成**多相时钟**或安全分频器的首选。例如用一个高频时钟驱动它，输出的不同位组合可以产生极其精确的 90 度、180 度相位差的时钟脉冲。
- 缺点： 同样存在非法状态锁死问题，只使用了 2N 个状态，依然有 2N−2N 个非法状态，陷入其中便无法逃脱。

## 线性反馈移位寄存器 (LFSR)
它的反馈逻辑不是简单的连线，而是将特定的几位进行**异或（XOR）**后再反馈到输入端。LFSR 有两种经典结构：斐波那契（多对一外部异或）和伽罗瓦（一对多内部异或）。这里以最常见的斐波那契结构为例，实现一个 8-bit 的 LFSR。它的特征多项式通常查表获得，比如 x8+x6+x5+x4+1，意味着抽头在第 8, 6, 5, 4 位（对应寄存器的 out[7], out[5], out[4], out[3]）。

```sv
module lfsr_8bit_fibonacci (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] out
);

    // 根据多项式构成的反馈网络 (XOR 树)
    wire feedback = out[7] ^ out[5] ^ out[4] ^ out[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 致命考点：LFSR 绝对不能用全 0 复位！
            // 必须赋予一个非零的种子 (Seed)
            out <= 8'hFF; 
        end else begin
            // 左移，并将异或结果反馈到最低位
            out <= {out[6:0], feedback};
        end
    end

endmodule
```
架构剖析：
- 优点（伪随机与极致效率）：
    - 只要多项式选得对（本原多项式），一个 N 位的 LFSR 可以遍历 2N−1 个状态（遍历除了全 0 之外的所有状态）。这是状态利用率最高的状态机。
    - 生成的序列具备极好的统计学“白噪声”特性，0 和 1 出现的概率几乎相等。
- 核心应用： 
    - BIST（内建自测试）： 芯片生产出来后，不需要外部昂贵的测试机，LFSR 可以自己疯狂产生 2^N−1 种随机测试向量，灌入 ALU 测试有没有坏点。
    - 通信加解密与加扰： PCIe、SATA、USB 3.0 等高速协议中，为了防止连串的 0 导致时钟恢复电路（CDR）失锁，会在物理层用 LFSR 产生的随机码和原始数据异或（打乱），接收端再用同构的 LFSR 异或一次（恢复）。
- 致命缺陷（全零陷阱）： 如果某一刻 out 变成了 00000000，那么 0^0^0^0 = 0，反馈进去的还是 0。LFSR 会在“全 0”状态永远死机。这就是为什么复位时必须给它一个非零的种子（Seed），并且在设计高可靠性 LFSR 时，常常需要外加一个 NOR树（或非门）来强制避开全 0 陷阱

# 避免死锁的反馈移位寄存器

## 环形计数器

解锁思路：放弃死板的环形反馈，采用“全零检测”注入法。我们不再把最高位直接连到最低位。而是用一个多输入的 NOR 门（或非门）监控除了最高位之外的所有低位。
- 只要低位里有任何一个 1，就不允许往里进 1（注入 0）。
- 只有当低位全为 0 时，才允许往里注入一个 1。

这样，无论当前有多少个乱七八糟的 1，它们都会在不断的右移中被推出去，最后寄存器一定会被清空，然后重新由 NOR 门注入一个干净的 1。

```sv
module self_correcting_ring_counter #(
    parameter WIDTH = 4
)(
    input  wire             clk,
    input  wire             rst_n,
    output reg  [WIDTH-1:0] out
);

    // 监控除了最高位之外的所有低位
    // 如果低位全为 0，则 feedback 为 1；否则为 0。
    wire feedback = ~( |out[WIDTH-2:0] );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out <= { {WIDTH-1{1'b0}}, 1'b1 }; 
        end else begin
            // 用 feedback 替代原来的 out[WIDTH-1]
            out <= {out[WIDTH-2:0], feedback};
        end
    end

endmodule
```

这种写法被称为扭环式或非门自恢复结构。它不仅彻底消灭了死锁，还顺带解决了一个复位难题——你甚至可以全 0 启动它，因为下一个周期它自己就会生成一个 1。这是工业界环形计数器的标准答案。

## 约翰逊计数器（扭环形计数器）

正常的约翰逊计数器状态块是连续的（如 000 → 100 → 110）。非法状态通常表现为“0和1交替出现”（如 010、101），一旦陷入，常规的反馈逻辑 MSB 会让这些交替状态无限循环。

解锁思路：破坏非法交替模式。以 4-bit 为例，合法的序列中，绝对不可能出现 out[2] == 0 且 out[0] == 0 的同时，还要移入一个 1 的情况。我们通过修改反馈方程，强制在检测到特定非法模式时注入 0，从而把非法状态“冲刷（Flush）”成全 0（全 0 是合法的起点）。

```sv
module self_correcting_johnson_counter (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [3:0] out
);

    // 标准的反馈是 ~out[3]
    // 增加的纠错项是：只有当 (out[0] == 1 或者 out[2] == 0) 时，才允许正常的反馈。
    // 否则强制反馈 0，打破死锁循环。
    // 逻辑代数化简后：
    wire feedback = (~out[3]) & (out[0] | (~out[2]));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out <= 4'b0000;
        end else begin
            out <= {out[2:0], feedback};
        end
    end

endmodule
```

- 分析： 约翰逊计数器的自纠错方程与位宽强相关。位宽变大时，推导这个布尔方程极其繁琐且容易出错。
- 工程实战备选方案： 在真正的复杂 ASIC 设计中，如果位宽很大（比如 12 位约翰逊），为了绝对安全且不费脑细胞，工程师通常直接加一个**“非法状态检测器”（一堆逻辑门组合）。一旦检测到非法状态，直接在时钟沿触发一个同步复位（Synchronous Reset）**，将寄存器强行拍回全 0。


## LFSR

LFSR 的反馈是由异或门（XOR）构成的。如果寄存器掉进了“全 0”状态，异或的结果永远是 0，系统就彻底死机了。

解锁思路：用 NOR 门打破全零陷阱（变身 de Bruijn 序列发生器）。我们监控 **LFSR的低N−1位**。如果低 N−1 位全变成了 0，此时不管正常的异或树算出来是什么，我们都强制把最终反馈位翻转！

```sv
module self_correcting_lfsr_8bit (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] out
);

    // 1. 标准的 Fibonacci 异或反馈树
    wire normal_fb = out[7] ^ out[5] ^ out[4] ^ out[3];

    // 2. 全零检测（只检测低 N-1 位）
    // 如果低 7 位全为 0，zero_detect 为 1
    wire zero_detect = ~( |out[6:0] );

    // 3. 终极反馈：将全零检测信号作为最高优先级的“翻转扰动”
    wire final_fb = normal_fb ^ zero_detect;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 现在，你甚至可以用全 0 甚至任意值来复位它！
            out <= 8'h00; 
        end else begin
            out <= {out[6:0], final_fb};
        end
    end

endmodule
```

这段代码不仅仅是解决了死锁这么简单，它其实完成了一个数学转换。
- 正常的 8-bit LFSR 只能遍历 28−1=255 个状态（缺了 00000000）。
- 当你加上这个 NOR 门后：假设寄存器走到了 10000000。正常的移位本该进入 00000000。进入全 0 后，下一个时钟：正常的 normal_fb 算出 0，但此时 zero_detect 为 1。最终 final_fb =0⊕1=1。
- LFSR 成功在全 0 状态只停留了一个周期，就被一脚踹到了 00000001。
- 结果： 这个 LFSR 现在能完美遍历完整的 28=256 个状态！在密码学和数学中，这种包含了全零状态的满周期序列，叫做：德·布鲁因序列 (de Bruijn Sequence)。

