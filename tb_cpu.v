`timescale 1ns / 1ps
`include "opcodes.v" 

module tb_cpu;

    // --- 1. 訊號宣告 ---
    reg clk;
    reg reset_n;
    reg inputReady;                    
    wire [`WORD_SIZE-1:0] data;
    reg irq;        
    wire readM;
    wire writeM;                        
    wire [`WORD_SIZE-1:0] address;
    wire [`WORD_SIZE-1:0] num_inst;
    wire [`WORD_SIZE-1:0] output_port; 

    // Testbench 內部的記憶體與驅動變數
    reg [`WORD_SIZE-1:0] data_driver;
    reg [`WORD_SIZE-1:0] memory [0:255];

    parameter timer = 50 ; //中斷 timer cycle

    // --- 2. 實例化 CPU ---
    cpu uut (
        .readM(readM),
        .writeM(writeM), 
        .address(address), 
        .data(data), 
        .irq(irq),
        .inputReady(inputReady), 
        .reset_n(reset_n), 
        .clk(clk), 
        .num_inst(num_inst),
        .output_port(output_port)
    );

    // --- 3. 雙向埠處理 ---
    assign data = (readM) ? data_driver : 16'bz; 

    // --- 4. 時脈產生 (10ns 週期) ---
    always #5 clk = ~clk;

    // --- 5. 模擬記憶體握手 (Handshake) ---
    always @(posedge clk) begin
        if (!reset_n) begin
            inputReady <= 0;
            data_driver <= 0;
        end
        else begin
            if (readM && !inputReady) begin
                data_driver <= memory[address]; 
                inputReady <= 1;
            end
            else if (!readM && inputReady) begin
                inputReady <= 0;
                data_driver <= 16'bz;
            end
            if (writeM) begin
                memory[address] <= data; 
                $display("[Memory Write] Addr: %d, Data: %d", address, data); // 方便 Debug
            end
        end
    end

    // Wave
    initial begin
        $dumpfile("wave.vcd");  
        $dumpvars(0, tb_cpu);       
    end

    // TEST
    initial begin
        // Inital
        clk = 0;
        reset_n = 0;
        irq = 0;
        inputReady = 0;
        data_driver = 16'bz;

        // --- 初始化記憶體為 0 ---
        begin : init_mem
            integer i;
            for(i=0; i<256; i=i+1) memory[i] = 0;
        end

        // --- 載入指令檔 ---
        // 這裡會讀取 assember 產生的 program.hex
        $readmemh("assember/program.hex", memory);
        $display("Simulation Start... Program loaded from program.hex");

        // 釋放 Reset
        #10 reset_n = 1;

        // Simulate Time
        /*
        #(timer*10); 
        // 觸發中斷 (Trigger Interrupt)
        $display("!!! IRQ TRIGGERED !!! Time: %t", $time);
        irq = 1;        // 拉高訊號
        #20;            // 維持一下 (確保 CPU 在某個 cycle 抓到)
        irq = 0;        // 放開訊號 (不然 CPU 會一直重複進中斷)
        */
        #3000;

        begin : dump_mem
            integer file_id;
            integer k;
            
            file_id = $fopen("memory.txt", "w");
            
            if (file_id) begin
                $display("Exporting memory to memory.txt...");
                
                // 2. 迴圈讀取 memory 並寫入檔案
                for (k = 0; k < 256; k = k + 1) begin
                    // 格式說明: %h (16進位), %d (10進位)
                    // 這裡我寫成: "位址(Hex) : 資料(Hex)"
                    $fdisplay(file_id, "Addr: %d | Data: %h", k[7:0], memory[k]);
                end
                
                // 3. 關閉檔案
                $fclose(file_id);
                $display("Export finished!");
            end else begin
                $display("Error: Could not open memory.txt for writing.");
            end
        end
        // ===
        
        $display("Simulation Finished.");
        $finish;
    end

    initial begin
        // 設定時間格式
        $timeformat(-9, 0, " ns", 5);

        // --- 啟動監視器 ---
        // 當以下任何變數改變時，印出數值
        // 請注意：uut.pc 和 uut.instr 必須對應你 cpu.v 裡面真正的變數名稱
        $monitor("Time: %t | PC: %d | Inst: %h |state: %d |Output: %d | R1: %d | R2: %d | R3: %d", 
                 $time, 
                 uut.PC,              // 偷看 CPU 內部的 PC
                 uut.data,            // 偷看 CPU 的 data
                 uut.state,
                 output_port,         // 外部的 Output Port
                 uut.rf.register[31:16],        // R1 
                 uut.rf.register[47:32],        // R2
                 uut.rf.register[63:48],        // R3
                 );
    end

endmodule