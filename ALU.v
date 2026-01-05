module ALU(
    input signed [15:0] A,
    input signed [15:0] B,
    input        [3:0]  OP,
    output reg   [15:0] C,
    output              bcond    // Branch判斷結果 : True(1) / False(0)
    );
    
    always @(*) begin
        case (OP)
            0:  C = A + B;          // ADD, ADI, LWD, SWD (ADD
            1:  C = A - B;          // SUB (SUB)
            2:  C = A & B;          // AND (AND)
            3:  C = A | B;          // ORR, ORI (OR)
            4:  C = ~A;             // NOT(1補數)
            5:  C = ~A + 1'b1;      // TCP(2補數，取負數)
            6:  C = A << 1;         // SHL(乘2)
            7:  C = A >>> 1;        // SHR(除2)
            8:  C = {B[7:0], 8'b0}; // LHI(載入高位立即值)B低4位至C的高4位

            9:  C = A - B;          // BNE(不相等): 先算 A-B，若結果不為0則不相等
            10: C = A - B;          // BEQ(相等): 先算 A-B，若結果為0則相等
            11: C = A;              // BGZ(大於0): 把 A 傳出去，檢查 C 是否 > 0
            12: C = A;              // BLZ(小於0): 把 A 傳出去，檢查 C 是否 < 0
            default: C = 16'bz;
        endcase
    end
    
    assign bcond = OP==9  ? (C!=0) :        // BNE
                   OP==10 ? (C==0) :        // BEQ
                   OP==11 ? (C>0)  :        // BGZ                
                   OP==12 ? (C<0)  : 0;     // BLZ
    
endmodule