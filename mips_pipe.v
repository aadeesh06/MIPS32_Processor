module pipe_mips32(clk1, clk2);
    input clk1 , clk2;                // two phase clock

    reg [31:0] PC, IF_ID_IR, IF_ID_NPC; 
    reg [31:0] ID_EX_IR, ID_EX_NPC, ID_EX_A, ID_EX_B, ID_EX_Imm;
    reg [2:0] ID_EX_type, EX_MEM_type, MEM_WB_type;
    reg [31:0] EX_MEM_IR, EX_MEM_ALUOut, EX_MEM_B;
    reg        EX_MEM_cond;
    reg [31:0] MEM_WB_IR, MEM_WB_ALUOut, MEM_WB_LMD;
    reg [31:0] Reg [0:31];  // register bank (32 x 32) 
    // there are 32 registers from 0 to 31 each of 32 bits
    reg [31:0] Mem [0:1023]; // 1024 x 32 memory

    // there are 1024 words in memory each of 32 bits

    reg HALTED, TAKEN_BRANCH;

    // below are the opcodes of the instructions. We are using parameters so that the code is readable
    
    parameter ADD = 6'b000000, SUB = 6'b000001, AND = 6'b000010, OR = 6'b000011;
    parameter SLT = 6'b000100, MUL = 6'b000101, HLT = 6'b111111, LW = 6'b001000;
    parameter SW = 6'b001001, ADDI = 6'b001010, SUBI = 6'b001011, SLTI = 6'b001100;
    parameter BNEQZ = 6'b001101 , BEQZ = 6'b001110;

    // below parameters indicate the type of instruction that is executed. 
    // whether it is register - register instruction, or load instruction etc.

    parameter RR_ALU = 3'b000, RM_ALU = 3'b001, LOAD = 3'b010, STORE = 3'b011, BRANCH = 3'b100, HALT = 3'b101;

    // below are the five stages of processor  

    always @(posedge clk1)        // IF STAGE
        if(HALTED == 0)
        begin
             if(((EX_MEM_IR[31: 26] == BEQZ) && (EX_MEM_cond == 1)) || ((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_cond == 0)))
             begin
                    IF_ID_IR        <= #2 Mem[EX_MEM_ALUOut];
                    TAKEN_BRANCH    <= #2 1'b1; 
                    IF_ID_NPC       <= #2 EX_MEM_ALUOut + 1;
                    PC              <= #2 EX_MEM_ALUOut + 1; 
             end
             else 
             begin
                IF_ID_IR            <= #2 Mem[PC];
                IF_ID_NPC           <= #2 PC + 1;
                PC                  <= #2 PC + 1;
             end
        end
    always @(posedge clk2)   // ID STAGE
        if(HALTED == 0)
        begin
                if(IF_ID_IR[25:21] == 5'b00000)
                    ID_EX_A <= 0;
                else
                    ID_EX_A <= #2 Reg[IF_ID_IR[25:21]]; // "rs"
                
                if(IF_ID_IR[20:16] == 5'b00000)
                    ID_EX_B <= 0;
                else 
                    ID_EX_B <= #2 Reg[IF_ID_IR[20:16]]; // "rt"

                ID_EX_NPC   <= #2 IF_ID_NPC;
                ID_EX_IR    <= #2 IF_ID_IR;
                ID_EX_Imm   <= #2 {{16{IF_ID_IR[15]}}, {IF_ID_IR[15:0]}};   // sign extension
                // the signed bit is replicated in sign extension, so we take the 15th bit and replicate it 16 times and then concatenate with the bits 15 to 0.
                
                case(IF_ID_IR[31:26])
                    ADD, SUB, AND, OR, SLT, MUL : ID_EX_type <= #2 RR_ALU;
                    ADDI, SUBI, SLTI            : ID_EX_type <= #2 RM_ALU;
                    LW                          : ID_EX_type <= #2 LOAD;
                    SW                          : ID_EX_type <= #2 STORE;
                    BEQZ, BNEQZ                 : ID_EX_type <= #2 BRANCH;
                    HLT                         : ID_EX_type <= #2 HALT;
                    default                     : ID_EX_type <= #2 HALT; // INVALID OPCODE
                endcase
        end
    always @(posedge clk1)      // EX STAGE
        if(HALTED == 0)
        begin
                //below three register values are forwaded to next stage
                EX_MEM_type         <= #2 ID_EX_type;  
                EX_MEM_IR           <= #2 ID_EX_IR;
                TAKEN_BRANCH        <= #2 0;

                case(ID_EX_type)  // check for type of instruction
                    RR_ALU      :   begin
                                        case(ID_EX_IR[31:26]) // "opcode checking"
                                            ADD     : EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_B;
                                            SUB     : EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_B;
                                            AND     : EX_MEM_ALUOut <= #2 ID_EX_A & ID_EX_B;
                                            OR      : EX_MEM_ALUOut <= #2 ID_EX_A | ID_EX_B;
                                            SLT     : EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_B;
                                            MUL     : EX_MEM_ALUOut <= #2 ID_EX_A * ID_EX_B;
                                            default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                                        endcase
                                    end 

                    RM_ALU      :   begin 
                                        case(ID_EX_IR[31:26])
                                            ADDI    : EX_MEM_ALUOut <= #2 ID_EX_A + ID_EX_Imm;
                                            SUBI    : EX_MEM_ALUOut <= #2 ID_EX_A - ID_EX_Imm;
                                            SLTI    : EX_MEM_ALUOut <= #2 ID_EX_A < ID_EX_Imm;
                                            default : EX_MEM_ALUOut <= #2 32'hxxxxxxxx;
                                        endcase
                                    end
                    
                    LOAD, STORE :   begin 
                                        EX_MEM_ALUOut   <= #2 ID_EX_A + ID_EX_Imm; // this will give us address of memory which will be stored in ALUOut.
                                        EX_MEM_B        <= #2 ID_EX_B;              // value of B is forwarded to next stage
                                    end
                    
                    BRANCH      :   begin 
                                        EX_MEM_ALUOut   <= #2 ID_EX_NPC + ID_EX_Imm;  // calculating the target address if branch has to be taken
                                        EX_MEM_cond     <= #2 (ID_EX_A == 0);
                                    end

                endcase
        end

        always @(posedge clk2)              // MEM STAGE
            if(HALTED == 0)
            begin
                    MEM_WB_type     <= #2 EX_MEM_type; 
                    MEM_WB_IR       <= #2 EX_MEM_IR;
                    case(EX_MEM_type)
                        RR_ALU, RM_ALU  : MEM_WB_ALUOut         <= #2 EX_MEM_ALUOut;
                        LOAD            : MEM_WB_LMD            <= #2 Mem[EX_MEM_ALUOut];
                        STORE           : if(TAKEN_BRANCH == 0)             // disable write
                                            Mem[EX_MEM_ALUOut]  <= #2 EX_MEM_B;
                    endcase
            end

        always @(posedge clk1)      // WB STAGE
        begin
                if(TAKEN_BRANCH == 0)           // disable write if branch taken
                    case(MEM_WB_type)
                        RR_ALU  : Reg[MEM_WB_IR[15:11]]     <= #2 MEM_WB_ALUOut;  // "rd" 
                        RM_ALU  : Reg[MEM_WB_IR[20:16]]     <= #2 MEM_WB_ALUOut;  // "rt"
                        LOAD    : Reg[MEM_WB_IR[20:16]]     <= #2 MEM_WB_LMD;     // "rt"
                        HALT    : HALTED                    <= #2 1'b1;
                    endcase
        end
        
endmodule