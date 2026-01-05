// sim OK
module RF(
    input write,          // Allow writing Signal
    input clk,
    input reset_n,
    input [1:0] addr1,    // 讀取 Reg 1（rs)
    input [1:0] addr2,    // 讀取 Reg 2（rt）
    input [1:0] addr3,    // 寫入 Reg 3（rd 或 rt）
    output [15:0] data1,  // rs value
    output [15:0] data2,  // rt value
    input [15:0] data3    // Now write data
    );

    // 4x16-bits register file (part-select)
    reg [63:0] register; 

    /*
    register[63:48] == register[16*3+: 16] (addr is 2'b11)
    register[47:32] == register[16*2+: 16] (addr is 2'b10)
    register[31:16] == register[16*1+: 16] (addr is 2'b01)
    register[15: 0] == register[16*0+: 16] (addr is 2'b00)
    */
    
    always @(posedge clk, negedge reset_n) begin
        // Asynchronous active low reset.
    	if (!reset_n) register <= 64'b0;
    	// Synchronous data write.
    	else if (write) register[16*addr3+: 16] <= data3;
    end
    
    // Asynchronous data read
    assign data1 = register[16*addr1+: 16];
    assign data2 = register[16*addr2+: 16];
    
endmodule