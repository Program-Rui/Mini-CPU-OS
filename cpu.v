`define WORD_SIZE 16    // data and address word size
`include "opcodes.v"

module cpu (
    output reg readM,                     // read from memory
    output wire writeM,                   // write to memory
    output reg [`WORD_SIZE-1:0] address,  // current address
    inout [`WORD_SIZE-1:0] data,          // data bus
    input irq,                            // Interrupt
    input inputReady,                     // memory ready signal
    input reset_n,                        // active-low RESET
    input clk,                            // clock
    output reg [`WORD_SIZE-1:0] num_inst, // instruction count
    output [`WORD_SIZE-1:0] output_port   // WWD output
);

    // --- 內部訊號 ---
    reg [`WORD_SIZE-1:0] PC;           // Program Counter
    reg [`WORD_SIZE-1:0] nextPC;       // Next Program Counter
    reg [`WORD_SIZE-1:0] instruction;
    reg [`WORD_SIZE-1:0] dataReg;
    reg [`WORD_SIZE-1:0] epc;          // 備份 PC 的 reg

    // 定義 ISR 入口地址 (假設是 250)
    localparam ISR_ADDR = 16'd20;
    
    // --- 狀態機定義  ---
    // 0: FETCH (發出讀取指令請求)
    // 1: WAIT_INST (等待記憶體回傳指令)
    // 2: EXECUTE (執行指令 / 計算 / 更新 PC / 算出記憶體位址)
    // 3: WAIT_DATA (如果是 LWD，等待記憶體回傳資料)
    // 4: MEM_WRITE (如果是 SWD，等待位址穩定後寫入)
    // 5: INTERRUPT (進入 ISR)
    reg [2:0] state; 
    localparam S_FETCH     = 3'd0;
    localparam S_WAIT_INST = 3'd1;
    localparam S_EXEC      = 3'd2;
    localparam S_WAIT_DATA = 3'd3;
    localparam S_MEM_WRITE = 3'd4; 
    localparam S_INTERRUPT = 3'd5; 

    // --- Control Module 連線 ---
    wire RegDst, Jump, Branch, MemRead, MemtoReg, MemWrite, ALUSrc, RegWrite, OpenPort;
    wire [3:0] ALUOp;
    
    // --- Datapath 連線 ---
    wire [`WORD_SIZE-1:0] ReadData1, ReadData2;
    wire bcond;
    wire [`WORD_SIZE-1:0] ALUResult;

    // Control Unit
    Control control(
        .opcode(instruction[15:12]),
        .func(instruction[5:0]),
        .RegDst(RegDst),
        .Jump(Jump),
        .Branch(Branch),
        .MemRead(MemRead),
        .MemtoReg(MemtoReg),
        .ALUOp(ALUOp),
        .MemWrite(MemWrite),
        .ALUSrc(ALUSrc),
        .RegWrite(RegWrite),
        .OpenPort(OpenPort)
    );
                    
    // Register File
    RF rf(
        .write(RegWrite & (state == S_EXEC || state == S_WAIT_DATA)), 
        .clk(clk),
        .reset_n(reset_n),
        .addr1(instruction[11:10]),
        .addr2(instruction[9:8]),
        .addr3(RegDst ? instruction[7:6] : instruction[9:8]),
        .data1(ReadData1),
        .data2(ReadData2),
        .data3(MemtoReg ? data : ALUResult) 
    );
          
    // ALU
    ALU alu(
        .A(ReadData1),
        .B(ALUSrc ? {{8{instruction[7]}}, instruction[7:0]} : ReadData2),
        .OP(ALUOp),
        .C(ALUResult),
        .bcond(bcond)
    );
    
    // --- Next PC Logic ---
    always @(*) begin
        if (Jump) 
            nextPC = {PC[15:12], instruction[11:0]};
        else if (Branch & bcond) 
            nextPC = (PC+1) + {{8{instruction[7]}}, instruction[7:0]}; 
        else 
            nextPC = PC + 1;
    end
    
    // --- 輸出埠 ---
    assign output_port = OpenPort ? ReadData1 : {`WORD_SIZE{1'bz}};

    // ---  寫入控制訊號 ---
    // 只有在專門的寫入狀態 (S_MEM_WRITE) 才拉高 writeM
    // 這樣可以確保 address 已經穩定了
    assign writeM = (state == S_MEM_WRITE);

    // ---  資料匯流排控制 ---
    // 同樣，只有在寫入狀態才把資料推出去
    assign data = (state == S_MEM_WRITE) ? ReadData2 : {`WORD_SIZE{1'bz}};

    // --- 主狀態機 (FSM) ---
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            PC <= 0;
            num_inst <= 0;
            state <= S_FETCH;
            readM <= 0;
            instruction <= 0;
            dataReg <= 0;
            address <= 0;
            epc <= 0;
        end else begin
            case (state)
                // 1. Fetch
                S_FETCH: begin
                    address <= PC;
                    readM <= 1;
                    state <= S_WAIT_INST;
                end

                // 2. Wait Instruction
                S_WAIT_INST: begin
                    if (inputReady) begin
                        instruction <= data;
                        readM <= 0;
                        state <= S_EXEC;
                        num_inst <= num_inst + 1;
                    end
                end

                // 3. Execute / Calculate Address
                S_EXEC: begin
                    if (instruction[15:12] == `IRET) begin // 新增 IRET 處理
                        PC <= epc;          // 恢復 PC
                        
                        // IRET 結束後通常不允許馬上再中斷，直接回 Fetch
                        state <= S_FETCH;   
                    end
                    else if (MemRead) begin  // LWD
                        address <= ALUResult; // 更新地址
                        readM <= 1;           // 發出讀取
                        state <= S_WAIT_DATA; // 去等資料
                    end 
                    else if (MemWrite) begin // SWD
                        address <= ALUResult; // 更新地址 (這時候還沒寫入!)
                        state <= S_MEM_WRITE; // 跳去寫入狀態
                    end
                    else begin // 其他指令
                        PC <= nextPC;
                        // 檢查中斷 (原本是直接回 S_FETCH)
                        if (irq) state <= S_INTERRUPT; 
                        else     state <= S_FETCH;
                    end
                end

                // 4. Wait Data (LWD 專用)
                S_WAIT_DATA: begin
                    if (inputReady) begin
                        dataReg <= data;
                        readM <= 0;
                        PC <= nextPC;
                        // 檢查中斷
                        if (irq) state <= S_INTERRUPT; 
                        else     state <= S_FETCH;
                    end
                end

                // 5.  Memory Write (SWD 專用)
                S_MEM_WRITE: begin
                    // 在這個狀態下，address 已經是 ALUResult 了 (因為是從 S_EXEC 傳過來的)
                    // writeM 訊號會被上面的 assign 自動拉高
                    // data 訊號會被上面的 assign 自動送出
                    
                    
                    PC <= nextPC;     // 更新 PC
                    // 檢查中斷
                    if (irq) state <= S_INTERRUPT; 
                    else     state <= S_FETCH;
                end
                // 6. Interrupt Entry (進入中斷)
                S_INTERRUPT: begin
                    epc <= PC;         // 1. 備份當前的 PC (已經是 nextPC 了)
                    PC <= ISR_ADDR;    // 2. 強制跳轉到 ISR (250)
                    state <= S_FETCH;  // 3. 開始執行 ISR 的第一行指令
                end
                
                default: state <= S_FETCH;
            endcase
        end
    end

endmodule