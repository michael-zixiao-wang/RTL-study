# 固定优先级仲裁器

固定优先级仲裁器为每个请求端口分配固定的优先级（例如：Port 0 > Port 1 > ... > Port N）。当多个请求同时到来时，永远只响应优先级最高的那个。

在常规的定义中，我们通常假设最低有效位（LSB，即 req[0]）拥有最高优先级，最高有效位（MSB，即 req[N-1]）拥有最低优先级。

## 行为级描述

这是最直观、最符合人类思维的写法。利用 SystemVerilog / Verilog 语法中 if-else 的天然优先级特性，将高优先级的请求放在前面判断。

```sv
module fixed_arb_behavioral #(
    parameter N = 4
)(
    input  wire [N-1:0] req,
    output reg  [N-1:0] grant
);

    integer i;
    always @(*) begin
        grant = {N{1'b0}}; // 默认全0
        
        // 由于是行为级描述，我们可以用for循环配合内部跳出机制
        // 但更常见的是让工具自动展开if-else。
        // 这里提供一种利用SystemVerilog特性的简洁写法（Verilog 2001也支持此种逻辑展开）
        for (i = 0; i < N; i = i + 1) begin
            if (req[i]) begin
                grant[i] = 1'b1;
                // 找到最低位的1后立即退出循环（模拟if-else的短路特性）
                // 注意：这里的disable仅在部分综合工具中支持较好，
                // 传统写法是用连续的 if-else if 级联，但这难以做到参数化。
            end
        end
    end

    // ---------------------------------------------------------
    // 补充：非参数化的经典 casez 写法 (适用于端口数固定的场景)
    // ---------------------------------------------------------
    /*
    always @(*) begin
        grant = 4'b0000;
        casez (req)
            4'b???1: grant = 4'b0001; // req[0] 优先级最高
            4'b??10: grant = 4'b0010;
            4'b?100: grant = 4'b0100;
            4'b1000: grant = 4'b1000;
            default: grant = 4'b0000;
        endcase
    end
    */

endmodule

```

优缺点：

- 优点： 代码极其易读，对于少量端口（如4或8端口）来说，综合工具能很好地优化。
- 缺点： 深度嵌套的 if-else 在端口数 N 较大时，会导致很长的逻辑级数，参数化实现相对不那么优雅。

## 进位链法

这种方法类似于行波进位加法器（Ripple Carry Adder）。我们构建一根“使能链条”（Enable Chain）。

核心思路： 最高优先级端口的“授权使能（Grant Enable）”永远为 1。如果某个端口有请求且拿到了使能，它就会把请求截流；如果没有请求，它就把使能传递给下一个低优先级端口。

```sv

module fixed_arb_daisy_chain #(
    parameter N = 8
)(
    input  wire [N-1:0] req,
    output wire [N-1:0] grant
);

    // en 数组比请求数组多1位，用于串联传递
    wire [N:0] en; 

    // 最高优先级（bit 0）的使能永远有效
    assign en[0] = 1'b1; 

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_chain
            // 获得授权的条件：本级有使能，且本级有请求
            assign grant[i] = req[i] & en[i];
            
            // 传递使能给下一级的条件：本级有使能，且本级【没有】截胡（没有请求）
            assign en[i+1]  = en[i] & ~req[i]; 
        end
    endgenerate

endmodule

```

优缺点：

- 优点： 硬件结构非常清晰，面积较小，参数化完美。
- 缺点： 关键路径延迟是 O(N)。如果 N 很大，信号从 en[0] 传导到 en[N] 需要经过 N 级逻辑门，时序极差，不适合高速微架构。


## 前缀屏蔽法
为了打破串行链的级联延迟，我们可以并行地计算每个端口的“屏蔽信号”。

核心思路： 对于端口 i，只要所有比它优先级高的端口（即 0 到 i−1）中存在任何一个请求，端口 i 就被屏蔽（Mask）。我们通过前缀按位或（Prefix-OR）来生成这个屏蔽掩码。

```sv
module fixed_arb_prefix_or #(
    parameter N = 8
)(
    input  wire [N-1:0] req,
    output wire [N-1:0] grant
);

    wire [N-1:0] higher_req; // 记录比当前位优先级更高的请求汇总

    // bit 0 没有比它优先级更高的请求
    assign higher_req[0] = 1'b0; 

    genvar i;
    generate
        for (i = 1; i < N; i = i + 1) begin : gen_prefix
            // 递归定义：当前位的 higher_req = 前一位的 higher_req | 前一位的 req
            assign higher_req[i] = higher_req[i-1] | req[i-1];
        end
    endgenerate

    // 产生授权：本位有请求，且没有被更高优先级的请求屏蔽
    assign grant = req & ~higher_req;

endmodule

```

优缺点：
- 优点： 逻辑层级变浅。虽然代码里看起来还是级联的（higher_req[i-1]），但综合工具很容易将其展平为并行的“宽或门”网络（例如 higher_req[3] = req[0] | req[1] | req[2]），速度比 Daisy-Chain 快。
- 缺点： 随着 N 的增大，宽或门的扇入（Fan-in）会增加，依然会有一定的连线延迟和面积开销。

## 二进制补码法

核心思路： 利用计算机体系结构中补码的数学性质。一个二进制数 A 的相反数 -A（在硬件中即为补码 ~A + 1），其最低位的 1 会保持不变，而这个最低位 1 左边（高位）的所有位都会与 A 的原始位相反。
因此，将 A 与 -A 进行按位与（Bitwise AND），即可精准提取出 A 中最低位的 1，其余位全部清零。

推演示例：假设 req = 8'b1011_0100（bit 2 优先级最高）
- 按位取反：~req = 8'b0100_1011
- 加1求补码：-req = 8'b0100_1100
- 按位与：req & -req = 8'b1011_0100 & 8'b0100_1100 = 8'b0000_0100（完美授权给了 bit 2）

```sv
module fixed_arb_parallel_fast #(
    parameter N = 8
)(
    input  wire [N-1:0] req,
    output wire [N-1:0] grant
);

    // 简单粗暴，一行代码解决所有战斗
    // 等价于 assign grant = req & (~req + 1'b1);
    assign grant = req & -req;

endmodule

```

优缺点：
- 优点： 极致的简洁。综合工具对加法器（含进位生成）的优化非常成熟（如Look-Ahead Carry），其组合逻辑延迟通常为 O(logN)，速度极快。
- 缺点： 几乎没有缺点，是工程实践中的首选。唯一的注意事项是，如果最低有效位（LSB）不是最高优先级，而是 MSB 拥有最高优先级，则需要将 req 信号进行位序翻转（Bit Reverse）后再套用此公式

# 轮徇仲裁器

## 掩码法
这是目前数字 IC 业界最标杆、应用最广泛、时序最好的实现方式。不管是 ARM 的 AMBA 总线互联，还是各种高性能网络交换机，底层几乎都是这个架构。

核心思想：利用一个 One-hot 码的寄存器（hist_ptr）记录上一个周期的授权者。通过数学逻辑生成一个“掩码（Mask）”，将所有的请求（req）一分为二：
- Masked Req（掩码请求）： 优先级严格大于 hist_ptr 的请求。
- Unmasked Req（非掩码请求）： 原始的所有请求（也即绕了一圈回来的低优先级请求）。

分别对这两个请求做“固定优先级仲裁（利用上一节学过的 req & -req 神技）”。如果存在掩码请求，就授权给掩码请求；如果没有，就说明高优先级没人要，授权给非掩码请求。

```sv
module rra_mask_based #(
    parameter N = 8 // 端口数量，支持任意正整数
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [N-1:0] req,
    output wire [N-1:0] grant
);

    reg  [N-1:0] hist_ptr; // 记录上一次被授权的端口，One-hot码

    // =========================================================================
    // 1. 生成掩码 (Mask) 
    // =========================================================================
    // 原理：假设 hist_ptr = 8'b0000_1000 (bit 3 刚获得授权)
    // hist_ptr - 1'b1         = 8'b0000_0111
    // (hist_ptr - 1) | hist_ptr = 8'b0000_1111
    // mask = ~上述结果          = 8'b1111_0000 (精确覆盖了 bit 4 ~ bit 7 这几个更高优先级的位)
    wire [N-1:0] mask = ~((hist_ptr - 1'b1) | hist_ptr);

    // =========================================================================
    // 2. 分别计算两组固定优先级 (利用补码求最低位的 1)
    // =========================================================================
    wire [N-1:0] masked_req     = req & mask;
    wire [N-1:0] grant_masked   = masked_req & (~masked_req + 1'b1);
    
    wire [N-1:0] grant_unmasked = req & (~req + 1'b1);

    // =========================================================================
    // 3. 产生最终的授权结果 (MUX 选路)
    // =========================================================================
    // 只要 masked_req 里面有任何一个请求为 1，就优先给 masked；否则绕回低优先级
    assign grant = (|masked_req) ? grant_masked : grant_unmasked;

    // =========================================================================
    // 4. 更新历史指针
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时，把最后一位拉高，相当于第一次仲裁时 bit 0 优先级最高
            hist_ptr <= {N{1'b0}}; 
            // 实际上全0也可以，全0时 mask 算出是 0，会直接走 grant_unmasked
        end else if (|req) begin
            hist_ptr <= grant; // 谁拿到了授权，谁就成为新的历史指针
        end
    end

endmodule

```

优缺点分析：
- 优点： 完美的全并行结构。底层全是加法器（求补码）和逻辑门，综合工具能将其优化到极小的延迟。这是手撕代码环节必须掌握的 Top 1 写法。
- 缺点： 关键路径上要经过两次加法器（减 1 和求补码）加上一级 MUX，当端口数 N 极大（比如 N=64）时，时序依然会成为瓶颈。

## 桶型移位法
这种方法完美呼应了你上一个问题中的“一般场景”处理思维。既然我们已经有了一个性能极度优异的固定优先级仲裁器（永远 LSB 优先），那我们为什么要把轮询逻辑写得那么复杂？

核心思想：维护一个二进制的轮询计数器（Pointer）。
- 把请求信号 req 向右循环移位（Rotate Right），移位的位数就是当前的 Pointer。这样原本该拥有最高优先级的端口，就被硬生生挪到了最低位（LSB）。
- 送入那个“闭着眼睛都写得出来的”固定优先级仲裁器 grant_tmp = req_rot & -req_rot。
- 把得出的授权结果 grant_tmp，再向左循环移位（Rotate Left） 相同的位数，复原到原始的端口对应位置。

```sv
module rra_barrel_shifter #(
    parameter N = 8,
    parameter W = 3 // log2(N)
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [N-1:0] req,
    output wire [N-1:0] grant
);

    reg  [W-1:0] rr_ptr; // 二进制轮询指针，指示当前优先级最低的端口（刚拿到授权的）

    // =========================================================================
    // 1. 请求向量右移位 (将下一个高优先级端口移到 LSB)
    // =========================================================================
    // 注意：这里使用 Verilog 的拼接运算符配合移位来实现循环移位
    wire [N*2-1:0] double_req = {req, req};
    wire [N-1:0]   req_rotated = double_req >> (rr_ptr + 1'b1);

    // =========================================================================
    // 2. 调用极致优化的 固定优先级仲裁核心 (LSB First)
    // =========================================================================
    wire [N-1:0] grant_rotated = req_rotated & (~req_rotated + 1'b1);

    // =========================================================================
    // 3. 授权结果左移位复原 (逆向映射回真实物理端口)
    // =========================================================================
    wire [N*2-1:0] double_grant_rot = {grant_rotated, grant_rotated};
    // 左循环移位等价于从高位截取
    assign grant = double_grant_rot >> (N - (rr_ptr + 1'b1));

    // =========================================================================
    // 4. 更新轮询指针 (二进制编码)
    // =========================================================================
    // 需要通过编码器将 one-hot 的 grant 转换回二进制，或者直接用 case
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr <= {W{1'b0}};
        end else if (|req) begin
            // One-hot 转 Binary 逻辑
            for (i = 0; i < N; i = i + 1) begin
                if (grant[i]) rr_ptr <= i[W-1:0];
            end
        end
    end

endmodule
```

# 其他特殊仲裁器

## 树形仲裁器
对于大规模树形仲裁，最核心的是写好一个两输入的乒乓节点 (Ping-Pong Node)。随后，可以通过例化这些基础节点来构建任意深度的树。

```sv
module ping_pong_arb_node (
    input  wire clk,
    input  wire rst_n,
    input  wire req_L,      // 左分支请求
    input  wire req_R,      // 右分支请求
    output wire gnt_L,      // 左分支授权
    output wire gnt_R,      // 右分支授权
    output wire node_req    // 向上传递的请求 (OR逻辑)
);

    // 状态位：0表示偏好左(L)，1表示偏好右(R)
    reg fav_ptr; 

    // 向上汇报：只要有任一侧请求，当前节点就向上一级发起请求
    assign node_req = req_L | req_R;

    // 产生授权逻辑 (组合逻辑)
    // 如果偏好L，且L有请求，则给L；否则只要R有请求就给R。反之亦然。
    assign gnt_L = req_L & (~req_R | ~fav_ptr);
    assign gnt_R = req_R & (~req_L |  fav_ptr);

    // 状态更新逻辑 (时序逻辑)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fav_ptr <= 1'b0; // 复位默认偏好左
        end else begin
            // 谁刚拿到了授权，下一次就把偏好给对面 (Ping-Pong机制)
            if (gnt_L) 
                fav_ptr <= 1'b1; 
            else if (gnt_R) 
                fav_ptr <= 1'b0;
        end
    end

endmodule

```


## 矩阵仲裁器 
这里以一个 4 端口的矩阵仲裁器为例。我们需要维护一个 4×4 的寄存器矩阵。当 matrix[i][j] == 1 时，表示 端口 i 的优先级高于 端口 j。

核心逻辑： 每次端口 k 获得授权后，将矩阵中第 k 行全部清零（将其优先级降到最低），并将第 k 列全部置一（让其他所有端口对 k 的优先级变高）

```sv
module matrix_arbiter_4port (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] req,
    output wire [3:0] grant
);

    // 4x4 优先级矩阵
    reg [3:0] matrix [3:0];

    // 授权逻辑：要想获得授权，必须有请求，且对其它所有有请求的端口优先级都更高
    // (或者其它端口根本没请求)
    wire [3:0] win;
    
    assign win[0] = req[0] & (matrix[0][1] | ~req[1]) & (matrix[0][2] | ~req[2]) & (matrix[0][3] | ~req[3]);
    assign win[1] = req[1] & (matrix[1][0] | ~req[0]) & (matrix[1][2] | ~req[2]) & (matrix[1][3] | ~req[3]);
    assign win[2] = req[2] & (matrix[2][0] | ~req[0]) & (matrix[2][1] | ~req[1]) & (matrix[2][3] | ~req[3]);
    assign win[3] = req[3] & (matrix[3][0] | ~req[0]) & (matrix[3][1] | ~req[1]) & (matrix[3][2] | ~req[2]);

    assign grant = win;

    // 矩阵状态更新逻辑
    integer i, j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位时，赋予默认的严格优先级 (0 > 1 > 2 > 3)
            matrix[0] <= 4'b1110; 
            matrix[1] <= 4'b1100;
            matrix[2] <= 4'b1000;
            matrix[3] <= 4'b0000;
        end else if (|grant) begin // 只有在有端口被授权时才更新
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    if (grant[i]) begin
                        // 如果端口 i 胜出，i行清零(除对角线)，i列置一
                        matrix[i][j] <= 1'b0; 
                        matrix[j][i] <= 1'b1;
                    end
                end
                // 修正对角线保持为0
                matrix[i][i] <= 1'b0;
            end
        end
    end

endmodule

```




