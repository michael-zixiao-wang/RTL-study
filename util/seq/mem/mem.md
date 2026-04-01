# 只读存储器 (ROM)
ROM 通常用于存放处理器的启动代码（Bootloader）或固化的查找表（如正弦波表、解码表）。

```sv
module sync_rom #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  en,
    input  wire [ADDR_WIDTH-1:0] addr,
    output reg  [DATA_WIDTH-1:0] rdata
);

    // 声明二维数组
    reg [DATA_WIDTH-1:0] rom [0:(1<<ADDR_WIDTH)-1];

    // 利用 initial 块配合系统函数加载数据
    // 注意：在 ASIC/FPGA 综合中，加载内存的 initial 块是完全可综合的！
    initial begin
        // 从外部 hex 文件加载数据到 rom 数组
        $readmemh("firmware.hex", rom); 
    end

    // 同步读逻辑 (必须打一拍)
    always @(posedge clk) begin
        if (en) begin
            rdata <= rom[addr];
        end
    end

endmodule
```

> 以上是同步ROM，当然读逻辑也可以完全是组合逻辑。但是如果是在FPGA中，推荐使用同步逻辑，原因如下。

- 综合行为： 只要你写了时钟沿触发的读操作（posedge clk），综合工具（如 Vivado）就会自动识别并例化底层的 Block ROM 资源。很多新手为了省事，把 ROM 的输出写成异步读（assign rdata = rom[addr]）。这会导致综合工具放弃使用 Block ROM，转而消耗海量的 LUT（查找表）来搭建这个纯组合逻辑网络，造成布线拥塞。

# 随机存取存储器 (RAM)

在设计 Cache、FIFO 或主存控制器时，我们必须使用 RAM。这里给出最常用的两种 RAM 写法，它们的核心法则是：**必须同步读、同步写，绝对不能复位存储阵列**！**(否则FPGA会被迫使用LUT和触发器生成的RAM)**

## 单端口 RAM (Single-Port RAM)
只有一套地址线。同一个周期内，要么读，要么写。

```sv
module single_port_ram #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  we,   // 写使能 (1:写, 0:读)
    input  wire [ADDR_WIDTH-1:0] addr, // 共享地址线
    input  wire [DATA_WIDTH-1:0] din,
    output reg  [DATA_WIDTH-1:0] dout
);

    // 声明深度为 1024 的内存阵列
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // 绝对不要对大容量 mem 数组写复位逻辑 (for 循环清零)！
    // 因为真实的 SRAM 宏单元底层是没有硬件清零复位引脚的。
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end else begin
            dout      <= mem[addr]; // 读操作延迟一个周期输出
        end
    end

endmodule
```

## 简单双端口 RAM (Simple Dual-Port RAM / 伪双端口)

一套专门的写端口，一套专门的读端口。这是构建 FIFO 缓冲队列的绝对主力。

```sv
module simple_dual_port_ram #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    input  wire                  clk,
    
    // 写端口
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    
    // 读端口
    input  wire                  re,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [DATA_WIDTH-1:0] rdata
);

    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // 写操作
    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
    end

    // 读操作
    always @(posedge clk) begin
        if (re) begin
            rdata <= mem[raddr];
        end
    end

endmodule

```
核心分析（读写冲突策略）： 上面的代码在 EDA 工具眼里，默认是 "Read-First"（先读后写） 或者具有不确定性。当 waddr == raddr 且同时读写时，由于非阻塞赋值 <=, rdata 读出的是当前时钟沿到来前老地址里的旧数据。

如果你需要 "Write-First"（先写后读，即读出最新写入的数据），你需要通过代码显式引导综合工具：

```sv
// Write-First (写穿透) 逻辑写法
always @(posedge clk) begin
    if (we) begin
        mem[waddr] <= wdata;
    end
    if (re) begin
        if (we && (waddr == raddr)) begin
            rdata <= wdata; // 发生碰撞时，把写数据直接旁路输出
        end else begin
            rdata <= mem[raddr];
        end
    end
end
```

## 真双端口RAM（True Dual-Port RAM, TDPRAM）

与简单双端口 RAM（伪双端口，一读一写）不同，真双端口 RAM 拥有两套完全独立且对称的接口（Port A 和 Port B）。每个端口都拥有自己的时钟、地址线、数据输入线、数据输出线和读写控制信号。

```sv
module true_dual_port_ram #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
)(
    // ================= 端口 A (Port A) =================
    input  wire                  clka,
    input  wire                  ena,   // Port A 使能
    input  wire                  wea,   // Port A 写使能
    input  wire [ADDR_WIDTH-1:0] addra, // Port A 地址
    input  wire [DATA_WIDTH-1:0] dina,  // Port A 写入数据
    output reg  [DATA_WIDTH-1:0] douta, // Port A 读出数据

    // ================= 端口 B (Port B) =================
    input  wire                  clkb,
    input  wire                  enb,   // Port B 使能
    input  wire                  web,   // Port B 写使能
    input  wire [ADDR_WIDTH-1:0] addrb, // Port B 地址
    input  wire [DATA_WIDTH-1:0] dinb,  // Port B 写入数据
    output reg  [DATA_WIDTH-1:0] doutb  // Port B 读出数据
);

    // 声明共享的内存阵列 (1024 x 32-bit)
    // 警告：仿真器允许两个 always 块同时写同一个变量，但真实硬件中会发生碰撞！
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // 端口 A 的逻辑控制 (完全由 clka 驱动)
    always @(posedge clka) begin
        if (ena) begin
            if (wea) begin
                mem[addra] <= dina;
            end
            // 默认行为：Read-First (读出的是旧数据)
            // 如果需要 Write-First，可以参考前面单端口 RAM 的前馈写法
            douta <= mem[addra]; 
        end
    end

    // 端口 B 的逻辑控制 (完全由 clkb 驱动)
    always @(posedge clkb) begin
        if (enb) begin
            if (web) begin
                mem[addrb] <= dinb;
            end
            doutb <= mem[addrb];
        end
    end

endmodule
```

冲突分析：

- 读-读冲突 (Read-Read)： 绝对安全。两个端口同时读同一个地址，都能拿到正确的数据。
- 读-写冲突 (Read-Write)： 端口 A 在写地址 0x10，端口 B 在读地址 0x10。结果： 内存里最终存入的是 A 写入的新数据。但 B 读出来的是什么？这取决于底层宏单元的物理特性。可能读出旧数据，可能读出新数据，也可能读出未知的乱码。在工程中，必须在外部避免这种同时刻的同址读写。
- 写-写冲突 (Write-Write)： 最致命的碰撞。端口 A 和端口 B 同时向地址 0x10 写入不同的数据。结果： 底层 SRAM 的交叉耦合锁存器会被来自两边的不同电压强行拉扯，导致物理层面的数据彻底损坏。该地址最终存储的值将是未知的。

工程解决策略： 
为了防止写-写冲突，通常需要在 TDPRAM 外围设计一个仲裁器 (Arbiter)。当检测到 addra == addrb 且 wea 和 web 同时为高时，强制拉低其中一个端口的 en，或者引入优先级机制（如 A 端口优先级高于 B 端口）。

优缺点分析：
- 优点： 
    - 数据从 A 口（时钟域 A）写入，从 B 口（时钟域 B）读出，天然实现了海量数据的跨时钟域 (CDC) 传输。
    - 极高的带宽和无与伦比的灵活性。你可以把它当成两个独立的单端口 RAM 用，也可以当成异步 FIFO 的核心存储池，或者用来做高效的矩阵转置运算（按行写入 A 端口，按列读取 B 端口）。
- 缺点：
    - 在芯片物理版图上，普通的单端口 SRAM 记忆单元通常由 6 个晶体管组成；而真双端口的 Bitcell 为了支持两套独立的读写字线和位线，通常需要 8 个晶体管甚至10个晶体管。

> 在数字 IC 设计的资源分配中有一条铁律：能用单端口（SPRAM）解决的，绝不用简单双端口（SDPRAM）；能用简单双端口解决的，绝不用真双端口（TDPRAM）。

# 寄存器组(Register File, RF)

寄存器堆是处理器数据通路的核心。以经典的 RISC-V 架构为例，通常需要 32 个寄存器，支持同时读出两个源操作数（rs1, rs2），并写入一个目的操作数（rd）。

**架构要求：同步写，异步读。** 因为在 CPU 流水线的译码（Decode）阶段，我们需要在半个周期内根据指令直接拿到数据，等不了时钟沿。

```sv
module register_file #(
    parameter ADDR_WIDTH = 5,
    parameter DATA_WIDTH = 64
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // 写端口 (Write Port)
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    
    // 读端口 1 (Read Port 1)
    input  wire [ADDR_WIDTH-1:0] raddr1,
    output wire [DATA_WIDTH-1:0] rdata1,
    
    // 读端口 2 (Read Port 2)
    input  wire [ADDR_WIDTH-1:0] raddr2,
    output wire [DATA_WIDTH-1:0] rdata2
);
    // 声明 32 个 64 位的寄存器数组
    reg [DATA_WIDTH-1:0] rf [0:(1<<ADDR_WIDTH)-1];
    // 同步写逻辑
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1) begin
                rf[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (we && (waddr != 0)) begin
            // 经典考点：0 号寄存器恒为 0，不能被改写
            rf[waddr] <= wdata;
        end
    end
    // 异步读逻辑 (纯组合逻辑)
    // 经典考点：内部前馈 (Bypass/Forwarding)
    // 如果读写同一个地址，直接将要写的数据透传给读端口，解决数据冒险
    assign rdata1 = (raddr1 == 0) ? {DATA_WIDTH{1'b0}} : 
                    ((we && (waddr == raddr1)) ? wdata : rf[raddr1]);
                    
    assign rdata2 = (raddr2 == 0) ? {DATA_WIDTH{1'b0}} : 
                    ((we && (waddr == raddr2)) ? wdata : rf[raddr2]);
endmodule
```

- 优点： 读数据零延迟，完美适配单周期译码；自带旁路逻辑，解决了读写同一地址时的“读旧值还是读新值”的冲突。
- 缺点： **由于存在“异步读”的需求，EDA 工具绝对不可能把它综合成 SRAM 宏单元。**它在底层会被 100% 展开成 32×64 = 2048 个标准的 D 触发器，以及由巨大的多路选择器（MUX）构成的读出网络。
- 工程结论： 寄存器堆只能做得很小。如果容量变大，面积和连线延迟会呈指数级上升