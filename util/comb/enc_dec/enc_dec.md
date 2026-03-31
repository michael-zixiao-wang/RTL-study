# 常见的编码

1. 自然二进制编码
- 原理： 最常规的按顺序递增的二进制表示（00, 01, 10, 11）。
- 硬件映射： 最省资源，N 个触发器可以表示 2N 个状态。
- 优点： 面积最小，极大节省了寄存器开销。
- 缺点： 状态跳转时，可能有多位同时发生翻转（比如从 011 跳到 100，三位都变了）。多位同时翻转会导致较多的动态功耗，且容易在组合逻辑中产生毛刺。译码逻辑也比独热码复杂。
- 应用场景： ASIC 设计中对面积（Area）极其敏感的低速状态机；常规的计数器。

2. 独热码
- 原理： 任何时候只有一位是 1，其余全为 0（例如：0001, 0010, 0100, 1000）。
- 硬件映射： N 个状态需要 N 个触发器。
- 优点（速度极快）： 状态译码极其简单。因为判断当前是哪个状态，只需要检查对应的那一根线是否为高电平，不需要经过复杂的组合逻辑（比如与非门树）。这大大缩短了关键路径，非常适合高速运行的电路。
- 缺点： 极度消耗寄存器资源。如果一个状态机有 32 个状态，就需要 32 个触发器。
- 应用场景： FPGA 设计的绝对首选（因为 FPGA 内部触发器资源极其丰富）；高性能处理器中对时序要求极苛刻的控制逻辑。

> 以上两个单元用于常用于通用的控制单元设计

3. 格雷码
- 原理： 任意两个相邻的状态之间，只有一位发生改变。
    (二进制: 00 -> 01 -> 10 -> 11)
    (格雷码: 00 -> 01 -> 11 -> 10)
- 优点（安全性）： 这是解决跨时钟域问题的核心钥匙。当多位信号跨越不同的时钟域时，由于物理走线的延迟差异，各个 bit 到达目标时钟域的时间不可能绝对一致。如果是二进制码多位同时跳变，目标时钟域可能会采样到错乱的中间态。而格雷码每次只有一位变化，即使采样发生微小时序偏差，采到的要么是前一个状态，要么是后一个状态，绝不会出现未知的灾难性错误。
- 缺点： 无法直接进行加减法等算术运算，必须先转回二进制码，算完再转回格雷码。
- 应用场景： 异步 FIFO 的读写指针；要求极低功耗的地址总线（翻转率低，动态功耗小）。
> 格雷码在CDC和低功耗领域有着很广泛的应用

4. BCD码(Binary-Coded Decimal)
- 原理： 用 4 位二进制数来表示 1 位十进制数（0~9）。比如十进制的 12，用 BCD 码表示就是 0001_0010。
- 特点： 4 位二进制本来可以表示 16 个数（0~15），BCD 码强行丢弃了 1010 到 1111 这 6 个状态，这在硬件上被称为“冗余状态”。
- 优点： 极其方便人类阅读，也极其方便与七段数码管、LCD 屏幕等显示设备对接，不需要做复杂的除法求余运算来提取十进制位。
- 缺点： 存储效率低。更麻烦的是，**BCD 码的加法不能直接用普通的加法器，必须使用专门的 BCD 加法器**（当相加结果大于 9 或产生进位时，需要额外加 6 进行十进制调整）。
- 应用场景： 数字钟、电子秤、高精度金融计算芯片（避免浮点数精度丢失）。

5. 伪随机码 (LFSR - Linear Feedback Shift Register Code)
- 原理： 利用移位寄存器和几个简单的异或门（XOR）反馈，就能产生一串看起来毫无规律的伪随机数序列。
- 应用场景： CPU 和复杂芯片流片后的内建自测试 (BIST)。不需要外部输入庞大的测试激励，芯片内部自己用 LFSR 疯狂生成随机数据去测试各个运算单元。

6. 错误检测与纠正码 (ECC - Error-Correcting Code)
- 原理： 插入冗余的校验位。比如简单的奇偶校验码 (Parity) 只能发现错误；而复杂的汉明码 (Hamming Code) 不仅能发现错误，还能定位具体是哪一位翻转了，并在硬件底层直接把它纠正过来。
- 应用场景： 在乱序执行的高性能处理器中，缓存 (Cache) 和主存的交互极易受到宇宙射线或电气噪声的干扰导致 bit 翻转。ECC 是保证数据完整性的最后一道防线。

# 编解码通识

在数字硬件的世界里，编解码本质上就是不同码型之间的“翻译工作”（Mapping / Translation）。也就是说编解码其实是相对的，对A的编码可能是对B的解码。由于不同码型适用的工作场景不一样，于是需要进行编码操作，于是有了“编码->适用于此编码的处理->解码”这样的工作流。

但是，并不是所有码型之间都需要相互转换，在实际的数字 IC 和微架构设计中，以下几组码型之间的“翻译”是最频繁的。

1. 二进制码 ⇌ 格雷码
- 翻译原因：跨时钟域的需求（异步 FIFO）
- 这是 RTL 设计中最经典的翻译场景。
    - 为什么需要二进制？ 在 FIFO 中，我们需要维护读指针和写指针的递增（加法运算），并且要通过计算指针的差值来判断 FIFO 是“空”还是“满”。这种算术运算只有二进制码能做。
    - 为什么需要格雷码？ 读写指针属于不同的时钟域。如果直接把二进制的读指针同步到写时钟域，由于多位同时跳变（比如 011 跳到 100），极易产生亚稳态和采样错误。格雷码每次只变一位，完美解决了多位跨时钟域的同步问题。
    - 电路实战： 在异步 FIFO 内部，发送端计数器用二进制自增 → 翻译成格雷码 → 打两拍跨时钟域 → 接收端把格雷码翻译回二进制 → 比较空满。
- 二进制转格雷码的数学原理： Gi​=Bi​⊕Bi+1​ （最高位保留，其余位与高一位异或）。

2. 二进制/指令码 ⇌ 独热码 (One-Hot)
- 翻译原因：用“空间”换取“时间”
- 如果你正在设计一个处理器核心，这组翻译将贯穿你的整个控制数据通路。
    - 翻译过程（译码阶段 ）： 取指单元拿到的是极其紧凑的 32 位机器码（比如 0000000_rs2_rs1_000_rd_0110011，RISC-V 的 R 型指令）。这种密集编码是为了节省内存和指令缓存的空间。
    - 为什么翻译成独热码？ CPU 内部的 ALU、寄存器堆、多路选择器不需要知道这 32 位到底是什么，它们只需要极其明确的“控制使能信号”。所以，译码器会将这紧凑的指令“翻译”成上百根非此即彼的独热码控制线（例如 is_add, is_sub, reg_we, mem_read）。一旦翻译成独热码，后级电路就不需要再做复杂的逻辑判断，直接用这些线去驱动门电路，极大地压缩了关键路径延迟，拉高了主频。

3. 二进制 ⇌ BCD 码/七段数码管码
- 翻译原因：人机交互的妥协
- 在 FPGA 开发或芯片测试验证阶段非常常见。
    - 为什么翻译？ 芯片内部所有的运算（比如加减乘除、计数）毫无疑问都在用纯二进制进行，因为底层加法器就是基于二进制构建的。但是，当我们需要把芯片的内部状态（比如计算出的某个数据结果、或者网络数据包的收发数量）显示在开发板的七段数码管或屏幕上时，人类是无法快速阅读 1101_0101 的。
    - 电路实战： 我们需要一个 “二进制转 BCD” (Double Dabble 算法 / 加3移位法) 的电路，把底层数据翻译成人类习惯的十进制表示形式，最后再加一级 BCD 到七段数码管的译码器来点亮 LED。

4. 原始数据 (Raw Data) ⇌ 纠错码 (ECC / Hamming Code)
- 翻译原因：抵御物理世界的干扰
- 在集成电路尺寸越来越小、或者设计高性能的乱序执行 CPU 时，存储器（SRAM/DRAM）极易受到电磁干扰发生比特翻转（Bit Flip）。
    - 写入（编码）： 当把原始数据写入存储器或 Cache 时，编码电路会实时计算出一组冗余的校验位（比如汉明码），将其和原始数据拼在一起存入。
    - 读取（解码/翻译）： 当 CPU 从 Cache 中读取数据时，解码电路会将读出的数据连同校验位一起进行矩阵运算“翻译”。如果发现错误，翻译电路不仅能报错，还能利用汉明码的特性，把翻转的那个 bit 强行翻转回来，再送给 CPU 执行。

# 普通编码器和优先级编码器

普通编码器就是最简单的编码映射，而优先级编码器还会按固定优先级（通常是高位优先）来决定译码结果。

哪一个4/2编码器举例，假设输入为I[3:0],输出为Y[1:0]。

1. 普通编码器
我们约定：I0→ 00，I1→ 01，I2→ 10，I3→ 11。
```sv
module normal_encoder (
    input  wire [3:0] I,
    output reg  [1:0] Y
);

always @(*) begin
    case (I)
        4'b0001: Y = 2'b00;
        4'b0010: Y = 2'b01;
        4'b0100: Y = 2'b10;
        4'b1000: Y = 2'b11;
        default: Y = 2'bxx; // 非法输入
    endcase
end

endmodule
```

2. 优先级编码器
我们约定，I3最高，I2次之...

此时很容易想到使用if-else实现，如下所示：
```sv
module priority_encoder (
    input  wire [3:0] I,
    output reg  [1:0] Y,
    output reg        valid
);

always @(*) begin
    if (I[3]) begin
        Y = 2'b11;
        valid = 1'b1;
    end else if (I[2]) begin
        Y = 2'b10;
        valid = 1'b1;
    end else if (I[1]) begin
        Y = 2'b01;
        valid = 1'b1;
    end else if (I[0]) begin
        Y = 2'b00;
        valid = 1'b1;
    end else begin
        Y = 2'b00;
        valid = 1'b0; // 无输入
    end
end

endmodule
```

当然还有一种写法，是利用casez语句：

```sv
module priority_encoder_4to2_casez (
    input  wire [2:0] I;
    output reg  [1:0] Y,
    output wire       valid
);

    assign valid = |I; // 使用按位或归约操作：只要 in 中有一个 1，valid 就为 1
    always @(*) begin
        casez (in)
            4'b1???: Y = 2'b11; // 只要最高位是1，后面是什么都不管
            4'b01??: Y = 2'b10;
            4'b001?: Y = 2'b01;
            4'b0001: Y = 2'b00;
            default: Y = 2'b00;
        endcase
    end

endmodule

```

# 二进制和格雷码转换

## 二进制转格雷码

逻辑推导：
保留二进制的最高位作为格雷码的最高位。格雷码的其余各位，等于对应的二进制位与其高一位相异或。

公式表达为：
G[N−1]=B[N−1];G[i]=B[i]⊕B[i+1](0≤i<N−1)。

```sv
module bin2gray #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] bin,
    output wire [WIDTH-1:0] gray
);

    // bin 整体右移一位后，最高位自动补 0。
    // 然后与原 bin 按位异或。
    assign gray = bin ^ (bin >> 1);

    /*
    // 当然也可以一位一位操作，注意此时gray是reg类型
    integer i;
    always @(*) begin
        gray[WIDTH-1] = bin[WIDTH-1]; // 最高位保留
        for (i = 0; i < WIDTH-1; i = i + 1) begin
            gray[i] = bin[i] ^ bin[i+1];
        end
    end
    */

endmodule
```
硬件分析（核心）： 这行代码综合出来的电路是完全并行的。每一个格雷码的 bit 位，只依赖于二进制的当前位和高一位，中间只经过了一个异或门。无论位宽是多少，组合逻辑延迟始终只有一个异或门的延迟。 时序表现极佳。

## 格雷码转二进制
逻辑推导：
保留格雷码的最高位作为二进制的最高位。二进制的其余各位，等于高一位的二进制与当前位的格雷码相异或。
公式表达为：
B[N−1]=G[N−1];B[i]=B[i+1]⊕G[i](0≤i<N−1)

```sv
module gray2bin #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] gray,
    output reg  [WIDTH-1:0] bin
);

    integer i;
    always @(*) begin
        bin[WIDTH-1] = gray[WIDTH-1]; // 最高位保留
        // 注意循环方向：必须从高到低计算
        for (i = WIDTH-2; i >= 0; i = i - 1) begin
            bin[i] = bin[i+1] ^ gray[i]; 
        end
    end

endmodule
```
通过数学推导，我们可以发现二进制的第 i 位，其实等于格雷码从第 i 位到最高位所有 bit 的异或和。
公式：B[i]=G[N−1]⊕G[N−2]⊕...⊕G[i]

```sv
module gray2bin_reduction #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] gray,
    output reg  [WIDTH-1:0] bin
);

    integer i;
    always @(*) begin
        for (i = 0; i < WIDTH; i = i + 1) begin
            // 利用归约异或运算符 ^
            // gray >> i 会把第 i 位及其上面的位移到低位
            // ^(gray >> i) 就是把第 i 位到最高位全部异或起来
            bin[i] = ^(gray >> i); 
        end
    end
endmodule
```

硬件分析： 因为 B[i] 依赖 B[i+1]，综合出来的电路是串行级联的。B[N−2] 经过 1 个异或门;B[N−3] 经过 2 个异或门...最低位 B[0] 必须等待上面所有的异或运算全部完成，它所在的路径经过了 N−1 个异或门。
结论：格雷码转二进制存在很长的关键路径。随着位宽 N 的增加，组合逻辑延迟会线性飙升。

## 总结
1. 并行 vs 串行： B2G 是纯并行电路，延迟极小；G2B 是串行/树状级联电路，延迟较大。
2. 异步 FIFO 的瓶颈： 在设计高频的异步 FIFO 时，通常是由慢时钟域同步格雷码指针到快时钟域。在快时钟域里，需要将同步过来的格雷码转回二进制（G2B），然后再与本地指针比较以判断空满。由于 G2B 有很长的组合逻辑延迟，这个转换过程往往会成为限制 FIFO 最高运行频率（Fmax​）的关键路径。 如果位宽很大（比如深度为 65536 的 FIFO 读写指针需要 17位），通常需要用流水线（Pipeline）插入寄存器来打断这条过长的组合逻辑路径。

# 二进制和独热码的转换

## 二进制转独热码
这其实就是一个标准的 N 线到 2N 线译码器。
```sv
module bin2onehot_shift #(
    parameter BIN_W = 3,
    parameter OH_W  = 8  // OH_W = 2^BIN_W
)(
    input  wire [BIN_W-1:0] bin,
    output wire [OH_W-1:0]  onehot
);

    // 将数字 1 左移 bin 指定的位数
    assign onehot = 1'b1 << bin;
    
    /*
    // 也可以如下实现，注意将onhot 改为reg类型
    integer i;
    always @(*) begin
        for (i = 0; i < OH_W; i = i + 1) begin
            onehot[i] = (bin == i); 
        end
    end
    */
endmodule

```

## 独热码转二进制

这是面试的高频考点！ 很多初学者会直接套用“优先级编码器”的代码来实现独热码转二进制，这是大错特错的。因为独热码已经保证了只有一位是 1，根本不存在“谁优先级高”的问题。如果强行用 if-else if 写成优先级编码器，综合出来的电路会带有一条长长的串行级联路径，白白浪费了面积并恶化了时序。我们应该利用“非此即彼”的特性，综合出一个完全并行的 OR 树（或门树）。

1. 经典并行case法(反向case法)

```sv
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
```

- 优点： 完美避开了优先级逻辑。因为这是 case 而不是 if-else，且我们明确只有一位是 1，综合工具会直接将其优化为并行的组合逻辑。在 ASIC 综合时，通常会配合 // synopsys parallel_case 原语来强制告诉综合器“这绝对是并行的，不要给我推断优先级”。
- 缺点： 无法参数化。如果位宽变成 128 位，你需要手敲 128 行 case 分支。

2. 按位或归约的 for 循环（高阶/参数化首选）

```sv
module onehot2bin_for #(
    parameter BIN_W = 3,
    parameter OH_W  = 8
)(
    input  wire [OH_W-1:0]  onehot,
    output reg  [BIN_W-1:0] bin
);

    integer i;
    always @(*) begin
        bin = {BIN_W{1'b0}}; // 必须初始化为0
        for (i = 0; i < OH_W; i = i + 1) begin
            if (onehot[i]) begin
                bin = bin | i; // 利用按位或（Bitwise OR）合并结果
            end
        end
    end

endmodule
```
- 硬件原理深度剖析： 这段代码看起来像是有优先级（因为用了 if），但精妙之处在于它利用了按位或（|）。
    假设 onehot 是 0001_0000（第 4 位为 1，即 i=4）。在循环执行时：
    - 当 i!=4 时，if 不成立，bin 保持不变（内部全 0）。
    - 当 i=4 时，if 成立，bin = 000 | 100，bin 变成了 100。
    综合工具非常聪明，它分析出这里面没有覆盖（Overwrite）的冲突，会直接把这个循环展开成一组并行的或门树（OR Tree）。二进制输出的每一位，只是若干个输入线的或逻辑。
- 优点： 代码极度紧凑，完全支持任意位宽的参数化配置，且综合出的硬件电路是理论上延迟最小的 O(log2​N) 或门树结构
> 注意bin = bin | i; // 利用按位或（Bitwise OR）合并结果
## 总结

1. 翻译方向决定复杂度： 二进制转独热码（解码）非常简单，一个左移操作符即可搞定；但独热码转二进制（编码）需要特别注意避免综合出冗余的优先级逻辑。
2. 安全隐患： 上述独热码转二进制的代码都建立在一个完美的前提下（严格输入独热码）。在实际的高可靠性芯片设计中，如果输入的 onehot 出现了全 0 或者多位为 1 的非法状态（比如受到单粒子翻转干扰），这些代码可能会输出错误的值。因此，在关键控制通路上，经常需要额外添加一个**valid**信号，利用奇偶校验或归约统计来确认当前输入确实是合法的独热码。

# 二进制和BCD码转换

BCD 码的转换与前面提到的多路选择器或独热码截然不同。BCD 码由于其非线性的“逢十进一”特性（抛弃了 A-F 这 6 个状态），使得它的转换电路本质上是在做除法和取余运算。这就引出了一个硬件设计的核心矛盾：在单周期组合逻辑里做大位宽的除法，时序绝对会爆炸。为了解决这个矛盾，前辈们发明了经典的 加3移位法 (Double Dabble Algorithm)。
## 二进制转BCD码
核心思想：加 3 移位算法 (Double Dabble)。
算法规则：将二进制数逐位左移。每次左移前，检查各个 BCD 位（每 4 bit 为一组），如果某一组的值大于或等于 5，则该组加 3，然后再整体左移。

1. 全组合逻辑 for 循环法

```sv
module bin2bcd_comb #(
    parameter BIN_W = 8,
    parameter BCD_W = 12 // 8位二进制最大255，需要3个BCD位(3*4=12)
)(
    input  wire [BIN_W-1:0] bin,
    output reg  [BCD_W-1:0] bcd
);
    integer i, j;
    always @(*) begin
        bcd = {BCD_W{1'b0}}; // 初始化为0    
        for (i = BIN_W-1; i >= 0; i = i - 1) begin
            // 1. 检查所有的 BCD 位，如果 >= 5，则加 3
            for (j = 0; j < BCD_W; j = j + 4) begin
                if (bcd[j +: 4] >= 4'd5) begin // bcd[j +: 4] 相当于 bcd[j+3 : j]
                    bcd[j +: 4] = bcd[j +: 4] + 4'd3;
                end
            end
            // 2. 整体左移 1 位，将二进制的最高位移入 BCD 的最低位
            bcd = {bcd[BCD_W-2:0], bin[i]};
        end
    end
endmodule
```
- 优点： 代码逻辑紧凑，一个时钟周期（纯组合逻辑）就能直接拿到结果。
    利用 j +: 4 语法，完美支持参数化，扩展到位宽更大的二进制极其容易。
- 硬件分析： 综合工具会把这个嵌套的 for 循环展开成一个巨大的、级联的“比较-加法器”阵列。如果 BIN_W 是 32 位（比如 32 位的 RISC-V 寄存器数据），这个组合逻辑链条会长得令人发指，产生极大的组合逻辑延迟。

2. 时序逻辑状态机法
为了解决组合逻辑延迟过大的问题，我们用“空间换时间”，把移位和加 3 的过程拆分到多个时钟周期里完成。

```sv
module bin2bcd_seq #(
    parameter BIN_W = 8,
    parameter BCD_W = 12
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start, // 转换开始信号
    input  wire [BIN_W-1:0]   bin,
    output reg  [BCD_W-1:0]   bcd,
    output reg                done   // 转换完成脉冲
);

    reg [BIN_W+BCD_W-1:0] shift_reg; // 移位寄存器，拼接 BCD 和 BIN
    reg [3:0]             cnt;       // 移位计数器
    
    // 状态机定义
    localparam IDLE  = 2'd0;
    localparam SHIFT = 2'd1;
    localparam ADD3  = 2'd2;
    localparam DONE  = 2'd3;
    reg [1:0] state, next_state;

    // 此处省略标准三段式状态机的写法细节，直接讲核心状态转移逻辑：
    // 1. IDLE: 当 start 为高时，将 {12'b0, bin} 载入 shift_reg，跳至 ADD3。
    // 2. ADD3: 检查 shift_reg 高 12 位的各个 BCD 块，>=5 则加 3。完成后跳至 SHIFT。
    // 3. SHIFT: shift_reg 整体左移一位。cnt++。
    //           如果 cnt == BIN_W，说明所有位移完，跳至 DONE。否则跳回 ADD3。
    // 4. DONE: 输出 bcd = shift_reg[高12位]，拉高 done 信号，跳回 IDLE。
endmodule

```

- 优点： 极高的 Fmax（最高主频）： 每一步都在寄存器之间完成，组合逻辑极短（只有一个简单的“大于5加3”逻辑）。极小的面积： 复用了同一套加法逻辑，而不是像写法 1 那样铺开几百个加法器。
- 缺点： 延迟大： 需要消耗 N 个时钟周期才能输出一次结果。
- 工程经验： 当我们需要驱动慢速外设（比如数码管的刷新频率只有几十赫兹）时，系统时钟可能高达上百兆，用多周期状态机来实现 BCD 转换是绝对的工业标准做法。

## BCD码转二进制

BCD 转二进制通常不需要复杂的移位算法，因为人类输入的 BCD 码（比如键盘输入按键 1 2 3）通常位宽不大。它的数学本质就是多项式求和：Binary=BCDn​×10n+⋯+BCD2​×100+BCD1​×10+BCD0​。

1. 乘法树直写 -> 依赖EDA优化

```sv
module bcd2bin_mult (
    input  wire [11:0] bcd, // 3个BCD位：百十个
    output wire [9:0]  bin
);

    wire [3:0] bcd_100 = bcd[11:8];
    wire [3:0] bcd_10  = bcd[7:4];
    wire [3:0] bcd_1   = bcd[3:0];

    // 直接调用乘法器和加法器
    assign bin = (bcd_100 * 7'd100) + (bcd_10 * 4'd10) + bcd_1;

endmodule
```
- 优点： 代码可读性满分，不费吹灰之力。
- 底层硬件分析： 很多初学者不敢这么写，觉得 * 100 会综合出庞大的硬件乘法器（DSP 资源）。但请记住，乘以常数在现代 EDA 综合工具（如 Design Compiler 或 Vivado）眼里根本不是乘法！工具会自动将其优化为移位和加法。
例如，x×10 会被瞬间优化为 (x≪3)+(x≪1)。

2. 手动移位加法树

```sv
module bcd2bin_shiftadd (
    input  wire [11:0] bcd, 
    output wire [9:0]  bin
);
    wire [3:0] bcd_100 = bcd[11:8];
    wire [3:0] bcd_10  = bcd[7:4];
    wire [3:0] bcd_1   = bcd[3:0];
    // 100 = 64 + 32 + 4  -> (x<<6) + (x<<5) + (x<<2)
    wire [9:0] bin_100 = (bcd_100 << 6) + (bcd_100 << 5) + (bcd_100 << 2);
    // 10 = 8 + 2         -> (x<<3) + (x<<1)
    wire [7:0] bin_10  = (bcd_10 << 3)  + (bcd_10 << 1);
    // 最终加法树
    assign bin = bin_100 + bin_10 + bcd_1;
endmodule
```

- 硬件分析： 这段代码综合出来的网表完全是一棵由全加器/半加器构成的加法树（Adder Tree）。没有任何乘法器资源被浪费。
- 优缺点对比： 性能与写法 1 经过高级工具优化后的结果是一样的。

# 奇偶校验码

这是最简单的检测错误标志，如下是编码方式：

```sv
module parity_generator #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] data_in,
    output wire             even_parity_bit, // 偶校验位
    output wire             odd_parity_bit   // 奇校验位
);

    // 偶校验：将数据各位全部异或。
    // 如果 data_in 中有奇数个 1，异或结果为 1，加上这个 1 之后总共就是偶数个 1。
    assign even_parity_bit = ^data_in;
    // 奇校验：偶校验的取反。或者使用同或操作符 ~^
    assign odd_parity_bit  = ~^data_in; 
endmodule

```

随后是接收端的验证：
```sv
module parity_checker #(
    parameter WIDTH = 8
)(
    input  wire [WIDTH-1:0] data_rx,   // 接收到的数据
    input  wire             parity_rx, // 接收到的偶校验位
    output wire             error      // 错误标志：1表示出错
);

    // 将收到的数据和校验位拼接起来，进行全校验
    // 如果是偶校验协议，传输无误的话，总共有偶数个1，异或结果必然是 0。
    // 如果结果是 1，说明在传输中发生了位翻转。
    assign error = ^ {parity_rx, data_rx};

endmodule
```
> 可以看出奇偶校验的硬件开销非常非常小。