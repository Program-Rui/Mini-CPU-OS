import sys

# --- 定義 ISA 編碼 ---
OPCODES = {
    'ADI': 0x4, 'ORI': 0x5, 'LHI': 0x6, 'LWD': 0x7, 'SWD': 0x8,
    'BNE': 0x0, 'BEQ': 0x1, 'BGZ': 0x2, 'BLZ': 0x3,
    'JMP': 0x9, 'JAL': 0xA, 'IRET': 0xE,
    'R-TYPE': 0xF 
}

FUNCS = {
    'ADD': 0x00, 'SUB': 0x01, 'AND': 0x02, 'ORR': 0x03,
    'NOT': 0x04, 'TCP': 0x05, 'SHL': 0x06, 'SHR': 0x07,
    'JPR': 0x19, 'JRL': 0x1A, 'RWD': 0x1B, 'WWD': 0x1C,
    'HLT': 0x1D, 'ENI': 0x1E, 'DSI': 0x1F
}

# --- 工具函式 ---
def reg_to_int(r_str):
    # 將 "$r1", "r1", "$1", "1" 都轉為整數
    # 增加錯誤處理，避免轉換失敗
    try:
        return int(r_str.lower().replace('$r', '').replace('r', '').replace('$', ''))
    except ValueError:
        print(f"Warning: Invalid register name '{r_str}', defaulting to 0")
        return 0

def parse_line(line, labels, current_addr, pass_num):
    # 1. 去除註解 (// 或 ;) 與前後空白
    line = line.split('//')[0].split(';')[0].strip()
    if not line:
        return None

    # 2. 處理 Label (例如 "START:")
    if line.endswith(':'):
        label_name = line[:-1]
        if pass_num == 1:
            labels[label_name] = current_addr
        return None

    # 3. 強化分割邏輯：把 ',' '(' ')' 都換成空白，支援 LWD $r1, 10($r2) 格式
    clean_line = line.replace(',', ' ').replace('(', ' ').replace(')', ' ')
    parts = [x.strip() for x in clean_line.split()]
    
    if not parts:
        return None
        
    opcode_name = parts[0].upper()
    
    # --- 初始化變數 (避免 UnboundLocalError) ---
    op = 0
    rs = 0
    rt = 0
    rd = 0
    func = 0
    imm = 0
    address = 0
    machine_code = 0

    try:
        # ================= Special IRET 處理 =================
        if opcode_name == 'IRET':
            op = OPCODES['IRET']
            # IRET 格式: [Opcode 4bit] [000000000000]
            machine_code = (op << 12)
        # ================= R-Type 處理 =================
        if opcode_name in FUNCS:
            op = OPCODES['R-TYPE']
            func = FUNCS[opcode_name]
            
            # 根據指令不同，讀取不同數量的參數
            if opcode_name in ['ADD', 'SUB', 'AND', 'ORR', 'SHL', 'SHR']: 
                # ADD Rd, Rs, Rt
                rd = reg_to_int(parts[1])
                rs = reg_to_int(parts[2])
                rt = reg_to_int(parts[3])
            elif opcode_name in ['NOT', 'TCP']:
                # NOT Rd, Rs
                rd = reg_to_int(parts[1])
                rs = reg_to_int(parts[2])
            elif opcode_name == 'WWD':
                # WWD Rs
                rs = reg_to_int(parts[1])
            elif opcode_name == 'RWD':
                # RWD Rd
                rd = reg_to_int(parts[1])
            
            # 組合機器碼
            machine_code = (op << 12) | (rs << 10) | (rt << 8) | (rd << 6) | func

        # ================= I-Type 處理 =================
        elif opcode_name in OPCODES and opcode_name not in ['JMP', 'JAL']:
            op = OPCODES[opcode_name]
            
            if opcode_name in ['ADI', 'ORI']:
                # ADI Rt, Rs, Imm
                rt = reg_to_int(parts[1])
                rs = reg_to_int(parts[2])
                imm = int(parts[3], 0) # 支援 0xFF 或 10
            
            elif opcode_name in ['LWD', 'SWD']:
                # 支援兩種寫法：
                # 1. LWD Rt, Rs, Imm  (parts=['LWD', 'Rt', 'Rs', 'Imm'])
                # 2. LWD Rt, Imm(Rs)  (parts=['LWD', 'Rt', 'Imm', 'Rs']) 因為我們把()取代成空白了
                
                rt = reg_to_int(parts[1])
                
                # 判斷是哪種格式：看第三個參數是不是暫存器
                str_p2 = parts[2].lower()
                if 'r' in str_p2 or '$' in str_p2:
                    # 格式: LWD Rt, Rs, Imm
                    rs = reg_to_int(parts[2])
                    imm = int(parts[3], 0)
                else:
                    # 格式: LWD Rt, Imm(Rs)
                    imm = int(parts[2], 0)
                    rs = reg_to_int(parts[3])

            elif opcode_name in ['BNE', 'BEQ', 'BGZ', 'BLZ']:
                # BNE Rs, Rt, Label (BGZ/BLZ 只有 Rs, Label)
                rs = reg_to_int(parts[1])
                
                # 區分有兩個暫存器還是一個
                target = ""
                if opcode_name in ['BNE', 'BEQ']:
                    rt = reg_to_int(parts[2])
                    target = parts[3]
                else:
                    target = parts[2]
                
                # 計算 Offset
                if pass_num == 2:
                    if target in labels:
                        # Offset = Label - (PC + 1)
                        offset = labels[target] - (current_addr + 1)
                        imm = offset & 0xFF 
                    else:
                        try:
                            imm = int(target, 0) & 0xFF
                        except:
                            print(f"Error: Label '{target}' not found at line: {line}")
                            imm = 0
            
            machine_code = (op << 12) | (rs << 10) | (rt << 8) | (imm & 0xFF)

        # ================= J-Type 處理 =================
        elif opcode_name in ['JMP', 'JAL']:
            op = OPCODES[opcode_name]
            target = parts[1]
            
            if pass_num == 2:
                if target in labels:
                    address = labels[target]
                else:
                    try:
                        address = int(target, 0)
                    except:
                        print(f"Error: Label '{target}' not found")
                        address = 0
            
            machine_code = (op << 12) | (address & 0xFFF)

        else:
            print(f"Error: Unknown Instruction '{opcode_name}'")
            return None

    except IndexError:
        print(f"Error: Missing operands in line: '{line}'")
        return None
    except ValueError:
        print(f"Error: Invalid operand format in line: '{line}'")
        return None

    return machine_code

# --- 主程式 ---
def assemble(filename):
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found.")
        return

    labels = {}
    
    print(f"Assembling {filename}...")

    # Pass 1: 記錄 Labels
    addr = 0
    for line in lines:
        if parse_line(line, labels, addr, 1) is not None:
            addr += 1
            
    # Pass 2: 產生機器碼
    output_hex = []
    addr = 0
    for i, line in enumerate(lines):
        code = parse_line(line, labels, addr, 2)
        if code is not None:
            # 印出詳細資訊方便除錯
            # print(f"Addr {addr:02X}: {line.strip():<20} -> {code:04X}")
            output_hex.append(f"{code:04X}")
            addr += 1
            
    # 寫入 hex 檔案
    output_file = "program.hex"
    with open(output_file, "w") as f:
        for h in output_hex:
            f.write(h + "\n")
    
    print(f"Success! Output saved to {output_file}")
    print(f"Total instructions: {len(output_hex)}")

# 執行
if __name__ == "__main__":
    # 如果有命令列參數就用參數，否則預設 test.asm
    file_to_assemble = sys.argv[1] if len(sys.argv) > 1 else "inst.asm"
    assemble(file_to_assemble)