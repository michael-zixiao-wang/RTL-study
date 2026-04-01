# 跨时钟域


跨时钟域（Clock Domain Crossing, CDC）是数字集成电路设计中最核心、也最容易引发灾难性 Bug 的难点。只要信号从一个时钟驱动的寄存器，传递到另一个非同源、非同频或非同相的时钟驱动的寄存器，CDC 问题就会发生。

CDC 的核心原因是亚稳态。当异步信号到达目标触发器时，极大概率会违背建立时间或保持时间。此时，触发器的输出会处于非 0 非 1 的震荡状态，进而导致整个状态机逻辑崩溃。

## 单比特CDC

单比特信号通常是控制信号（如使能、中断、状态标志）。处理它的核心原则是：滤除亚稳态，并确保信号能被目标时钟捕获。

1. 慢时钟域到快时钟域

- 核心现象： 快时钟一定能“看”到慢时钟发出的信号。唯一的风险是信号跳变沿刚好落在快时钟的采样违例窗口内，引发亚稳态。
- 终极解法：两级同步器。
- 架构逻辑： 在目标时钟域连续打两拍。第一级触发器大概率会捕获到亚稳态，但在整整一个快时钟周期的时间内，亚稳态大概率会衰减并稳定（0 或 1）。第二级触发器再去采样时，就能得到干净的数字电平。
> **绝不允许在两级同步器之间插入任何组合逻辑。**

2. 快时钟域到慢时钟域

- 核心现象： 快时钟发出的单脉冲可能极其短促。慢时钟的采样沿可能刚好从脉冲的“头尾间隙”漏过去，导致信号丢失。

- 解法 A：开环脉冲同步器
    - 原理： 在发送端（快时钟域），将这个短促的单脉冲转换为一个电平翻转信号。只要有脉冲，电平就翻转一次。
    - 接收端： 这个翻转的电平信号足够长，慢时钟域用标准的“两级同步器”将其捕获。捕获后，再加一级触发器进行异或（边缘检测），将其还原为一个慢时钟域的单脉冲。

- 解法 B：闭环握手
    - 原理： 发送端拉高请求信号（REQ）并保持。接收端用两级同步器捕获 REQ，处理完毕后，向发送端发回一个应答信号（ACK）。发送端捕获到 ACK 后，才允许将 REQ 拉低。
    - 优缺点： 绝对安全，不会丢脉冲，但耗时极长（至少需要穿梭两个时钟域一来一回的时间）。

## 多比特CDC

多比特信号通常是数据总线或配置向量。处理它的核心痛点不仅是亚稳态，更是时钟偏斜导致的数据重组错误。

**绝对不能将多比特信号直接挂上多个并行的“两级同步器”**。因为布线延迟不同，各个 bit 摆脱亚稳态的时间也不同。原本发送的是 0000 变 1111，目标端可能在中间周期采到 0101 这种致命的乱码状态。

1. 数据锁定与MUX同步 (Data MUX / Data Hold)
    - 适用场景： 带有有效标志（Valid）的数据流。
    - 解法：
        - 发送端将多比特数据放在总线上，并保持绝对静止。
        - 发送端发出一个单比特的 valid 信号。
        - 接收端使用“两级同步器”只去同步这个单比特的 valid。
        - 当接收端看到同步后的 valid_sync 拉高时，此时多比特数据已经在总线上稳定了足够久，完全满足建立时间。接收端直接用一个 MUX 或寄存器将数据安全采入。

2. 全握手协议 (Full Handshake)
    - 适用场景： 离散的多比特控制命令跨域。
    - 解法： 在 MUX 同步的基础上增加闭环反馈。发送端数据保持，发送 REQ；接收端同步 REQ，采样数据，并发回 ACK；发送端同步 ACK 后，才能改变数据总线并发起下一次传输。

3. 格雷码同步
    - 适用场景： 严格按照顺序递增或递减的计数器（典型如异步 FIFO 的读写指针）。
    - 解法： 将二进制计数器转换为格雷码。格雷码每次跳变只有 1 个 bit 发生翻转。因此可以直接跨域**并使用并行的两级同步器**。即使采样出现亚稳态偏差，采到的要么是前一个值，要么是当前值，绝不会出现乱码。

4. 异步FIFO
    - 适用场景： 源源不断的突发（Burst）流式数据，频率极高，不能容忍握手带来的停顿等待。
    - 解法： 它是 CDC 技术的集大成者。内部使用双口 RAM 存储数据本身（避开总线 CDC），然后仅将读写指针转换为格雷码进行跨时钟域传递，以此来计算空满状态。


# 两级同步器

这是所有 CDC 处理的基础，专门用于处理单比特的电平信号跨时钟域。
```sv
module sync_2stage (
    input  wire clk_dest,  // 目标时钟域
    input  wire rst_n,     // 目标时钟域的异步复位同步释放信号
    input  wire async_in,  // 来自源时钟域的异步信号
    output wire sync_out   // 同步到目标时钟域的信号
);

    reg sync_reg1;
    reg sync_reg2;

    always @(posedge clk_dest or negedge rst_n) begin
        if (!rst_n) begin
            sync_reg1 <= 1'b0;
            sync_reg2 <= 1'b0;
        end else begin
            // 第一级：极大概率捕获到亚稳态，利用一整个周期让其衰减稳定
            sync_reg1 <= async_in; 
            // 第二级：采样稳定后的信号，输出给下游逻辑
            sync_reg2 <= sync_reg1;
        end
    end

    assign sync_out = sync_reg2;

endmodule
```


- 适用场景： 慢时钟域到快时钟域的单比特信号传递；或者跨域的配置信号（如长按的复位、使能开关）。
- 优点： 面积开销极小（仅需两个 D 触发器），延迟低（2 个目标时钟周期）。
- 致命缺点（快到慢的漏采问题）： 如果源时钟域（快）发出的脉冲宽度小于目标时钟域（慢）的一个时钟周期，目标时钟极大概率会从脉冲的头尾间隙漏过去，导致信号彻底丢失。

# 脉冲同步器

为了解决“快到慢”时，短促脉冲被漏采的问题，脉冲同步器利用了 **“翻转”**机制。

```sv
module sync_pulse (
    input  wire clk_src,   // 发送端时钟 (快)
    input  wire rst_src_n,
    input  wire pulse_in,  // 源时钟域的单脉冲

    input  wire clk_dest,  // 接收端时钟 (慢)
    input  wire rst_dest_n,
    output wire pulse_out  // 目标时钟域恢复出的单脉冲
);

    // ================= 发送端 (源时钟域) =================
    reg toggle_reg;
    always @(posedge clk_src or negedge rst_src_n) begin
        if (!rst_src_n) begin
            toggle_reg <= 1'b0;
        end else if (pulse_in) begin
            // 核心魔术：把转瞬即逝的脉冲，变成一个长久的电平翻转
            toggle_reg <= ~toggle_reg;
        end
    end

    // ================= 接收端 (目标时钟域) =================
    reg sync_reg1, sync_reg2, sync_reg3;
    always @(posedge clk_dest or negedge rst_dest_n) begin
        if (!rst_dest_n) begin
            {sync_reg3, sync_reg2, sync_reg1} <= 3'b000;
        end else begin
            // 1. 先用两级同步器把翻转电平同步过来
            sync_reg1 <= toggle_reg;
            sync_reg2 <= sync_reg1;
            // 2. 第三级用于边缘检测 (Edge Detection)
            sync_reg3 <= sync_reg2;
        end
    end

    // 异或操作：只要相邻两个周期的电平不同，就代表源端发过一次脉冲
    assign pulse_out = sync_reg2 ^ sync_reg3;

endmodule

```

- 适用场景： 单比特脉冲的“快到慢”跨域传递（如中断触发脉冲、单步计数使能）。
- 优点： 无视时钟频率差异，绝对安全地将脉冲送到对岸。
- 限制约束： 发送端的连续两个 pulse_in 之间必须有足够的间隔（通常要求大于 2 到 3 个慢时钟周期），否则连续翻转太快，慢时钟依然无法正确采样出 Toggle 电平。

# 握手协议同步器

当我们需要跨域传递**多比特数据（如 32 位配置寄存器）**时，并行的两级同步器会因为布线延迟差（Skew）导致数据错乱。此时必须使用闭环握手协议。以下是精简代码示例（这里精简了状态机，保留核心握手逻辑以示原理）

```sv
module sync_handshake #(
    parameter WIDTH = 32
)(
    input  wire clk_tx, rst_tx_n,
    input  wire req_in,
    input  wire [WIDTH-1:0] data_in,
    output reg  ready_tx, // 告诉上游：我空闲了，可以发下一个

    input  wire clk_rx, rst_rx_n,
    output reg  valid_rx,
    output reg  [WIDTH-1:0] data_out
);

    reg req_tx;
    wire ack_tx_sync; // 接收端发回来的 ack，同步到 TX 域
    
    reg ack_rx;
    wire req_rx_sync; // 发送端的 req，同步到 RX 域
    
    reg [WIDTH-1:0] data_hold; // 数据锁定寄存器

    // 例化单比特两级同步器同步控制信号
    sync_2stage u_sync_req (.clk_dest(clk_rx), .rst_n(rst_rx_n), .async_in(req_tx), .sync_out(req_rx_sync));
    sync_2stage u_sync_ack (.clk_dest(clk_tx), .rst_n(rst_tx_n), .async_in(ack_rx), .sync_out(ack_tx_sync));

    // ================= 发送端 (TX) =================
    always @(posedge clk_tx or negedge rst_tx_n) begin
        if (!rst_tx_n) begin
            req_tx   <= 1'b0;
            ready_tx <= 1'b1;
        end else begin
            if (req_in && ready_tx) begin
                data_hold <= data_in; // 锁定多比特数据，保持绝对静止！
                req_tx    <= 1'b1;    // 发起请求
                ready_tx  <= 1'b0;    // 变忙
            end else if (ack_tx_sync) begin
                req_tx    <= 1'b0;    // 收到应答后撤销请求
            end else if (!req_tx && !ack_tx_sync) begin
                ready_tx  <= 1'b1;    // 一次完整握手结束，恢复空闲
            end
        end
    end

    // ================= 接收端 (RX) =================
    always @(posedge clk_rx or negedge rst_rx_n) begin
        if (!rst_rx_n) begin
            ack_rx   <= 1'b0;
            valid_rx <= 1'b0;
        end else begin
            if (req_rx_sync && !ack_rx) begin
                // 因为 req 已经同步并拉高，说明 data_hold 已经稳定很久了
                // 此时直接采样多比特数据，绝对满足 Setup/Hold time！
                data_out <= data_hold; 
                valid_rx <= 1'b1;
                ack_rx   <= 1'b1;     // 发回确认
            end else if (!req_rx_sync) begin
                ack_rx   <= 1'b0;     // 发送端撤销了，我也撤销应答
                valid_rx <= 1'b0;
            end else begin
                valid_rx <= 1'b0;     // 数据仅有效一拍
            end
        end
    end

endmodule
```

- 适用场景： 多比特的离散控制命令、寄存器配置总线传递。
- 优点： 100% 绝对安全的数据完整性（Data Coherency）。
- 缺点（吞吐量极其低下）： 传递一个数据，需要经历 Req发 -> Req同步 -> 采数据/Ack发 -> Ack同步 -> Req撤 -> Ack撤。一来一回通常需要消耗十几个时钟周期，完全无法应对连续的数据流。

# 异步FIFO
这是解决多比特、极高吞吐量数据跨时钟域的最通用方案。它利用格雷码（Gray Code）单 bit 翻转的物理特性，巧妙避开了多比特同步的 Skew 问题。

## 异步FIFO代码详解

首先给出一个专门用于格雷码同步的并行两级同步器：
```sv
// -----------------------------------------------------------------------------
// Module: sync_2stage_array
// Description: 参数化的多比特两级同步器（仅限格雷码等单比特跳变信号跨域使用）
// -----------------------------------------------------------------------------
module sync_2stage_array #(
    parameter WIDTH = 4
)(
    input  wire             clk_dest, // 目标时钟
    input  wire             rst_dest_n, // 目标时钟域的复位
    input  wire [WIDTH-1:0] async_in, // 来自源时钟域的格雷码
    output reg  [WIDTH-1:0] sync_out  // 同步后的格雷码
);

    reg [WIDTH-1:0] sync_reg1;

    always @(posedge clk_dest or negedge rst_dest_n) begin
        if (!rst_dest_n) begin
            sync_reg1 <= {WIDTH{1'b0}};
            sync_out  <= {WIDTH{1'b0}};
        end else begin
            sync_reg1 <= async_in;
            sync_out  <= sync_reg1;
        end
    end

endmodule
```

在继续说明前，还需要解释一下**全局复位信号的跨域分配**问题。面对一个全局的外部异步复位信号（如按键 ext_rst_n），绝对不能直接连到异步 FIFO 的写端和读端。正确的做法是：在写时钟域（wclk）用异步复位同步释放电路生成 wrst_n；在读时钟域（rclk）用同样的电路生成 rrst_n。让两个时钟域各自拥有绝对安全的本地复位网络。

```sv
// -----------------------------------------------------------------------------
// Module: async_fifo
// Description: 工业级标准异步 FIFO (Cummings 架构)
// -----------------------------------------------------------------------------
module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 4   // 深度固定为 2^ADDR_WIDTH (即 16)
)(
    // ================= 写时钟域 (Write Domain) =================
    input  wire                  wclk,
    input  wire                  wrst_n, // 必须是写时钟域的同步释放复位
    input  wire                  winc,   // 写请求 (Push)
    input  wire [DATA_WIDTH-1:0] wdata,  // 写数据
    output wire                  wfull,  // 写满标志
    
    // ================= 读时钟域 (Read Domain) =================
    input  wire                  rclk,
    input  wire                  rrst_n, // 必须是读时钟域的同步释放复位
    input  wire                  rinc,   // 读请求 (Pop)
    output wire [DATA_WIDTH-1:0] rdata,  // 读数据
    output wire                  rempty  // 读空标志
);

    // ================= 1. 内部参数与信号声明 =================
    localparam DEPTH     = 1 << ADDR_WIDTH;
    localparam PTR_WIDTH = ADDR_WIDTH + 1; // 指针多出 1 bit 用于判断折返

    // 内存阵列
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 二进制指针与格雷码指针 (写域)
    reg [PTR_WIDTH-1:0] wptr_bin;
    reg [PTR_WIDTH-1:0] wptr_gray;
    
    // 二进制指针与格雷码指针 (读域)
    reg [PTR_WIDTH-1:0] rptr_bin;
    reg [PTR_WIDTH-1:0] rptr_gray;

    // 跨域同步后的格雷码指针
    wire [PTR_WIDTH-1:0] rq2_wptr_gray; // 同步到读域的写指针
    wire [PTR_WIDTH-1:0] wq2_rptr_gray; // 同步到写域的读指针

    // ================= 2. 底层双口 RAM 读写逻辑 =================
    // 写操作 (严格在写域进行，满时不写)
    wire is_push = winc && !wfull;
    always @(posedge wclk) begin
        if (is_push) begin
            // 寻址时强行截断最高位
            mem[wptr_bin[ADDR_WIDTH-1:0]] <= wdata; 
        end
    end

    // 读操作 (严格在读域进行，空时不读)
    // 注意：这里实现的是标准 FIFO (非 FWFT)，数据有一拍读延迟
    wire is_pop = rinc && !rempty;
    reg [DATA_WIDTH-1:0] rdata_reg;
    always @(posedge rclk) begin
        if (is_pop) begin
            rdata_reg <= mem[rptr_bin[ADDR_WIDTH-1:0]];
        end
    end
    assign rdata = rdata_reg;

    // ================= 3. 写域：指针更新与格雷码转换 =================
    wire [PTR_WIDTH-1:0] next_wptr_bin  = wptr_bin + is_push;
    // 【核心】二进制转格雷码：当前值与其右移一位的值做异或
    wire [PTR_WIDTH-1:0] next_wptr_gray = next_wptr_bin ^ (next_wptr_bin >> 1);

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wptr_bin  <= {PTR_WIDTH{1'b0}};
            wptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            wptr_bin  <= next_wptr_bin;
            // 【极其关键】必须把组合逻辑生成的格雷码打一拍寄存后，再送去跨时钟域！
            // 防止组合逻辑毛刺被另一个时钟域采到。
            wptr_gray <= next_wptr_gray; 
        end
    end

    // ================= 4. 读域：指针更新与格雷码转换 =================
    wire [PTR_WIDTH-1:0] next_rptr_bin  = rptr_bin + is_pop;
    wire [PTR_WIDTH-1:0] next_rptr_gray = next_rptr_bin ^ (next_rptr_bin >> 1);

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rptr_bin  <= {PTR_WIDTH{1'b0}};
            rptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            rptr_bin  <= next_rptr_bin;
            rptr_gray <= next_rptr_gray;
        end
    end

    // ================= 5. 格雷码指针跨时钟域同步 =================
    // 写指针 -> 读时钟域 (用于判断空)
    sync_2stage_array #(.WIDTH(PTR_WIDTH)) sync_w2r (
        .clk_dest   (rclk),
        .rst_dest_n (rrst_n),
        .async_in   (wptr_gray),
        .sync_out   (rq2_wptr_gray)
    );

    // 读指针 -> 写时钟域 (用于判断满)
    sync_2stage_array #(.WIDTH(PTR_WIDTH)) sync_r2w (
        .clk_dest   (wclk),
        .rst_dest_n (wrst_n),
        .async_in   (rptr_gray),
        .sync_out   (wq2_rptr_gray)
    );

    // ================= 6. 终极奥义：空满判断逻辑 =================
    // 判空 (在读时钟域)：读指针追上了写指针。每一位格雷码都完全相同。
    assign rempty = (rptr_gray == rq2_wptr_gray);

    // 判满 (在写时钟域)：写指针比读指针多跑了一圈。
    // 在格雷码的数学特性中，表现为：最高两位相反，其余低位完全相同。
    assign wfull  = (wptr_gray == { ~wq2_rptr_gray[PTR_WIDTH-1:PTR_WIDTH-2], 
                                     wq2_rptr_gray[PTR_WIDTH-3:0] });

endmodule
```


- 适用场景： 海量流式数据流（如 AXI 数据通道、ADC 采样流、视频像素流）的跨频率域桥接。
- 优点： 读写两端完全独立，只要不空不满，就可以在每个时钟周期背靠背地写入和读出，吞吐量达到理论极限的 1 Word / Cycle。
- 缺点： 面积占用巨大。需要消耗双口 RAM，外加两套格雷码转换逻辑和几十个同步触发器。

## 异步FIFO的其他问题

1. 为什么要用格雷码跨时钟域？
普通二进制计数器（如 0111 变 1000）有多位同时跳变，如果被另一个时钟域采到亚稳态，数值可能变成 1111 这种毫无逻辑的错误地址。而格雷码每次加 1，物理上只有 1 根线发生电平翻转。就算这 1 根线产生了亚稳态采样错误，结果也只是停留在上一个值或者更新为当前值，这在 FIFO 的指针逻辑中是绝对安全的。

2. 为什么写出格雷码前必须打一拍？
代码中 wptr_gray <= next_wptr_gray 这行非常关键。next_wptr_gray 是由异或门（组合逻辑）算出来的，组合逻辑天然存在毛刺（Glitch）。如果直接把组合逻辑连到同步器，另一个时钟域可能会采到毛刺。跨时钟域的信号，其源头必须是干净的寄存器（DFF）输出。

3. 假空与假满（悲观设计原则）
- 假满： 判满是在写时钟域进行的。它拿当前的写指针，去比较同步过来的读指针 wq2_rptr_gray。由于同步器需要消耗 2 到 3 个周期，这意味着写域看到的读指针，永远是“过去的历史”。有可能读端已经抽走了几个数据，但写端还没看到，所以提前报了 wfull。这会损失一点点总线带宽，但绝对不会导致数据溢出被覆盖。极其安全。
- 假空： 判空是在读时钟域进行的。同理，它拿当前的读指针，去比较同步过来的写指针 rq2_wptr_gray。写端明明刚写入了数据，但读端还没看到，提前报了 rempty。这只会让读端稍微等两拍，但绝对不会导致读出未知的垃圾数据。极其安全。