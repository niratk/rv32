package rv32_pkg;
  localparam int XLEN = 32;
  localparam int INSTR_WIDTH = 32;

  // RV32G (RV32I + MAFD + Zicsr + Zifencei) major opcodes.
  // An individual instruction is selected by the opcode together with fields
  // such as funct3, funct7, funct5, funct2, and the immediate value.
  typedef enum logic [6:0] {
    OPCODE_LOAD     = 7'b0000011,  // Integer load
    OPCODE_LOAD_FP  = 7'b0000111,  // Floating-point load
    OPCODE_MISC_MEM = 7'b0001111,  // FENCE, FENCE.I, and memory-ordering hints
    OPCODE_OP_IMM   = 7'b0010011,  // Integer immediate operation
    OPCODE_AUIPC    = 7'b0010111,  // Add upper immediate to PC
    OPCODE_STORE    = 7'b0100011,  // Integer store
    OPCODE_STORE_FP = 7'b0100111,  // Floating-point store
    OPCODE_AMO      = 7'b0101111,  // Atomic memory operation
    OPCODE_OP       = 7'b0110011,  // Integer register-register operation
    OPCODE_LUI      = 7'b0110111,  // Load upper immediate
    OPCODE_MADD     = 7'b1000011,  // Floating-point fused multiply-add
    OPCODE_MSUB     = 7'b1000111,  // Floating-point fused multiply-subtract
    OPCODE_NMSUB    = 7'b1001011,  // Negated fused multiply-subtract
    OPCODE_NMADD    = 7'b1001111,  // Negated fused multiply-add
    OPCODE_OP_FP    = 7'b1010011,  // Floating-point operation
    OPCODE_BRANCH   = 7'b1100011,  // Conditional branch
    OPCODE_JALR     = 7'b1100111,  // Indirect jump and link
    OPCODE_JAL      = 7'b1101111,  // PC-relative jump and link
    OPCODE_SYSTEM   = 7'b1110011   // Environment and CSR operation
  } opcode_t;

  typedef enum logic [2:0] {
    TYPE_I,
    TYPE_S,
    TYPE_B,
    TYPE_J,
    TYPE_U
  } imm_src_t;
  typedef enum logic [3:0] {
    ALU_ADD,
    ALU_SUB,
    ALU_SLT,
    ALU_OR,
    ALU_AND,
    ALU_SLTU,
    ALU_XOR,
    ALU_SLL,
    ALU_SRA,
    ALU_SRL
  } alu_type_t;
  typedef enum logic [1:0] {
    PC_PLUS4,
    PC_TARGET,
    PC_ALU
  } pc_src_t;
  typedef enum logic [1:0] {
    RESULT_ALU,
    RESULT_MEM,
    RESULT_IMM,
    RESULT_PCPLUS4
  } result_src_t;
  typedef enum logic {
    ALU_SRC_R1,
    ALU_SRC_PC
  } alu_src_1_t;
  typedef enum logic {
    ALU_SRC_R2,
    ALU_SRC_IMM
  } alu_src_2_t;
endpackage

interface instr_mem_if;

  logic [rv32_pkg::XLEN-1:0] addr;
  logic [rv32_pkg::XLEN-1:0] read_data;

  modport cpu(output addr, input read_data);
  modport cpu_dp(output addr, input read_data);

  modport mem(input addr, output read_data);

endinterface

interface data_mem_if;

  logic [rv32_pkg::XLEN-1:0] addr;
  logic [rv32_pkg::XLEN-1:0] write_data, read_data;
  logic we;

  modport cpu(input read_data, output addr, write_data, we);

  modport mem(input addr, write_data, we, output read_data);

  modport cpu_ctrl(output we);

  modport cpu_dp(input read_data, output addr, write_data);

endinterface

interface dp_ctrl_if;

  rv32_pkg::opcode_t op;
  logic [2:0] funct3;
  logic funct7b5;
  logic branch_taken;

  rv32_pkg::pc_src_t pc_src;
  rv32_pkg::result_src_t result_src;
  rv32_pkg::alu_type_t alu_ctrl;
  rv32_pkg::alu_src_1_t alu_src_1;
  rv32_pkg::alu_src_2_t alu_src_2;
  rv32_pkg::imm_src_t imm_src;
  logic reg_write;

  modport dp(
      output op, funct3, funct7b5, branch_taken,
      input pc_src, result_src, alu_ctrl, alu_src_1, alu_src_2, imm_src, reg_write
  );
  modport ctrl(
      input op, funct3, funct7b5, branch_taken,
      output pc_src, result_src, alu_ctrl, alu_src_1, alu_src_2, imm_src, reg_write
  );

endinterface

module cpu (
    input logic clk,
    rst_n,
    data_mem_if data_mem,
    instr_mem_if instr_mem
);

  dp_ctrl_if dp_ctrl ();
  dp u_dp (
      .data_mem (data_mem),
      .instr_mem(instr_mem),
      .dp_ctrl  (dp_ctrl)
  );
  ctrl u_ctrl (
      .data_mem(data_mem),
      .dp_ctrl (dp_ctrl)
  );

endmodule

module dp (
    // from ext
    input logic clk,
    input logic rst_n,
    data_mem_if.cpu_dp data_mem,
    instr_mem_if.cpu_dp instr_mem,
    dp_ctrl_if.dp dp_ctrl
);

  logic [rv32_pkg::XLEN-1:0] imm_ext;
  logic [rv32_pkg::XLEN-1:0] result;
  logic [rv32_pkg::XLEN-1:0] alu_result;

  localparam logic [rv32_pkg::XLEN-1:0] PC_INIT = 'h8;

  logic [rv32_pkg::XLEN-1:0] pc;
  logic [rv32_pkg::XLEN-1:0] pc_next;
  assign instr_mem.addr = pc;

  always_comb begin
    case (dp_ctrl.result_src)
      rv32_pkg::RESULT_ALU: result = alu_result;
      rv32_pkg::RESULT_MEM: begin
        case (dp_ctrl.funct3)
          3'b000:  result = {{24{data_mem.read_data[7]}}, data_mem.read_data[7:0]};
          3'b001:  result = {{16{data_mem.read_data[15]}}, data_mem.read_data[15:0]};
          3'b010:  result = data_mem.read_data;
          3'b100:  result = {24'b0, data_mem.read_data[7:0]};
          3'b101:  result = {16'b0, data_mem.read_data[15:0]};
          default: result = 32'b0;
        endcase
      end
      rv32_pkg::RESULT_IMM: result = imm_ext;
      rv32_pkg::RESULT_PCPLUS4: result = pc + 4;
      default: result = alu_result;
    endcase
  end

  logic [rv32_pkg::XLEN-1:0] rf_rd1, rf_rd2;
  logic [rv32_pkg::XLEN-1:0] alu_s1, alu_s2;
  always_comb begin
    case (dp_ctrl.alu_src_1)
      rv32_pkg::ALU_SRC_PC: alu_s1 = pc;
      rv32_pkg::ALU_SRC_R1: alu_s1 = rf_rd1;
      default: alu_s1 = rf_rd1;
    endcase

    case (dp_ctrl.alu_src_2)
      rv32_pkg::ALU_SRC_IMM: alu_s2 = imm_ext;
      rv32_pkg::ALU_SRC_R2: alu_s2 = rf_rd2;
      default: alu_s2 = rf_rd2;
    endcase
  end

  assign dp_ctrl.op = rv32_pkg::opcode_t'(instr_mem.read_data[6:0]);
  assign dp_ctrl.funct3 = instr_mem.read_data[14:12];
  assign dp_ctrl.funct7b5 = instr_mem.read_data[30];

  assign data_mem.addr = alu_result;
  always_comb begin
    case (dp_ctrl.funct3)
      3'b000:  data_mem.write_data = {24'b0, rf_rd2[7:0]};
      3'b001:  data_mem.write_data = {16'b0, rf_rd2[15:0]};
      3'b010:  data_mem.write_data = rf_rd2;
      default: data_mem.write_data = '0;
    endcase
  end

  always_comb begin
    case (dp_ctrl.funct3)
      3'b000:  dp_ctrl.branch_taken = (rf_rd1 == rf_rd2);
      3'b001:  dp_ctrl.branch_taken = (rf_rd1 != rf_rd2);
      3'b100:  dp_ctrl.branch_taken = ($signed(rf_rd1) < $signed(rf_rd2));
      3'b101:  dp_ctrl.branch_taken = ($signed(rf_rd1) >= $signed(rf_rd2));
      3'b110:  dp_ctrl.branch_taken = rf_rd1 < rf_rd2;
      3'b111:  dp_ctrl.branch_taken = rf_rd1 >= rf_rd2;
      default: dp_ctrl.branch_taken = 1'b0;
    endcase
  end

  rf u_rf (
      .clk(clk),
      .rs1(instr_mem.read_data[19:15]),
      .rs2(instr_mem.read_data[24:20]),
      .rd (instr_mem.read_data[11:7]),
      .wd (result),
      .we (dp_ctrl.reg_write),
      .rd1(rf_rd1),
      .rd2(rf_rd2)
  );
  ext u_ext (
      .instr  (instr_mem.read_data[31:7]),
      .imm_src(dp_ctrl.imm_src),
      .imm_ext(imm_ext)
  );
  alu u_alu (
      .s1(alu_s1),
      .s2(alu_s2),
      .alu_ctrl(dp_ctrl.alu_ctrl),
      .result(alu_result)
  );

  always_comb begin
    case (dp_ctrl.pc_src)
      rv32_pkg::PC_TARGET: pc_next = pc + imm_ext;
      rv32_pkg::PC_PLUS4:  pc_next = pc + 4;
      rv32_pkg::PC_ALU:    pc_next = {alu_result[31:1], 1'b0};
      default:             pc_next = pc + 4;
    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc <= PC_INIT;
    end else begin
      pc <= pc_next;
    end
  end
endmodule

module ctrl (
    data_mem_if.cpu_ctrl data_mem,
    dp_ctrl_if.ctrl dp_ctrl
);

  typedef enum logic [1:0] {
    PC_MODE_BRANCH,
    PC_MODE_JUMP,
    PC_MODE_JALR,
    PC_MODE_SEQ
  } pc_mode_t;

  pc_mode_t pc_mode;
  logic [1:0] aluop;

  always_comb begin
    case (pc_mode)
      PC_MODE_BRANCH:
      dp_ctrl.pc_src = dp_ctrl.branch_taken ? rv32_pkg::PC_TARGET : rv32_pkg::PC_PLUS4;
      PC_MODE_JALR: dp_ctrl.pc_src = rv32_pkg::PC_ALU;
      PC_MODE_JUMP: dp_ctrl.pc_src = rv32_pkg::PC_TARGET;
      PC_MODE_SEQ: dp_ctrl.pc_src = rv32_pkg::PC_PLUS4;
      default: dp_ctrl.pc_src = rv32_pkg::PC_PLUS4;
    endcase
  end

  always_comb begin
    case (dp_ctrl.op)
      rv32_pkg::OPCODE_LOAD: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_I;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_MEM;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b00;
      end
      rv32_pkg::OPCODE_STORE: begin
        dp_ctrl.reg_write = 1'b0;
        dp_ctrl.imm_src = rv32_pkg::TYPE_S;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b1;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;  // dont care
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b00;
      end
      rv32_pkg::OPCODE_OP: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_I;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_R2;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b10;
      end
      rv32_pkg::OPCODE_BRANCH: begin
        dp_ctrl.reg_write = 1'b0;
        dp_ctrl.imm_src = rv32_pkg::TYPE_B;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_R2;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;
        pc_mode = PC_MODE_BRANCH;
        aluop = 2'b01;
      end
      rv32_pkg::OPCODE_OP_IMM: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_I;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b10;
      end
      rv32_pkg::OPCODE_LUI: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_U;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_IMM;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b00;
      end
      rv32_pkg::OPCODE_AUIPC: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_U;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_PC;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b00;
      end
      rv32_pkg::OPCODE_JAL: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_J;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_R2;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_PCPLUS4;
        pc_mode = PC_MODE_JUMP;
        aluop = 2'b00;
      end
      rv32_pkg::OPCODE_JALR: begin
        dp_ctrl.reg_write = 1'b1;
        dp_ctrl.imm_src = rv32_pkg::TYPE_I;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_IMM;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_PCPLUS4;
        pc_mode = PC_MODE_JALR;
        aluop = 2'b00;
      end
      default: begin  // ???
        dp_ctrl.reg_write = 1'b0;
        dp_ctrl.imm_src = rv32_pkg::TYPE_I;
        dp_ctrl.alu_src_1 = rv32_pkg::ALU_SRC_R1;
        dp_ctrl.alu_src_2 = rv32_pkg::ALU_SRC_R2;
        data_mem.we = 1'b0;
        dp_ctrl.result_src = rv32_pkg::RESULT_ALU;
        pc_mode = PC_MODE_SEQ;
        aluop = 2'b00;
      end
    endcase

    case (aluop)
      2'b00: dp_ctrl.alu_ctrl = rv32_pkg::ALU_ADD;
      2'b01: dp_ctrl.alu_ctrl = rv32_pkg::ALU_SUB;
      2'b10:
      case (dp_ctrl.funct3)
        3'b000:
        dp_ctrl.alu_ctrl = {dp_ctrl.op[5],dp_ctrl.funct7b5} == 2'b11 ? rv32_pkg::ALU_SUB : rv32_pkg::ALU_ADD;
        3'b001: dp_ctrl.alu_ctrl = rv32_pkg::ALU_SLL;
        3'b010: dp_ctrl.alu_ctrl = rv32_pkg::ALU_SLT;
        3'b011: dp_ctrl.alu_ctrl = rv32_pkg::ALU_SLTU;
        3'b100: dp_ctrl.alu_ctrl = rv32_pkg::ALU_XOR;
        3'b101: dp_ctrl.alu_ctrl = dp_ctrl.funct7b5 ? rv32_pkg::ALU_SRA : rv32_pkg::ALU_SRL;
        3'b110: dp_ctrl.alu_ctrl = rv32_pkg::ALU_OR;
        3'b111: dp_ctrl.alu_ctrl = rv32_pkg::ALU_AND;
        default: dp_ctrl.alu_ctrl = rv32_pkg::ALU_ADD;  // ???
      endcase
      default: dp_ctrl.alu_ctrl = rv32_pkg::ALU_ADD;  // ???
    endcase
  end

endmodule

module rf (
    input logic clk,
    input logic [4:0] rs1,
    rs2,
    rd,
    input logic we,
    input logic [rv32_pkg::XLEN-1:0] wd,
    output logic [rv32_pkg::XLEN-1:0] rd1,
    rd2
);

  logic [rv32_pkg::XLEN-1:0] regs[0:31];
  assign rd1 = regs[rs1];
  assign rd2 = regs[rs2];

  always_ff @(posedge clk) begin
    if (we && rd != 0) regs[rd] <= wd;
    regs[0] <= '0;
  end

endmodule

module ext (
    input logic [31:7] instr,
    input rv32_pkg::imm_src_t imm_src,
    output logic [rv32_pkg::XLEN-1:0] imm_ext
);

  always_comb begin
    case (imm_src)
      rv32_pkg::TYPE_I: imm_ext = {{20{instr[31]}}, instr[31:20]};
      rv32_pkg::TYPE_S: imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      rv32_pkg::TYPE_B: imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
      rv32_pkg::TYPE_J: imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
      rv32_pkg::TYPE_U: imm_ext = {instr[31:12], 12'b0};
      default: imm_ext = '0;
    endcase
  end

endmodule

module alu (
    input logic [rv32_pkg::XLEN-1:0] s1,
    s2,
    input rv32_pkg::alu_type_t alu_ctrl,
    output logic [rv32_pkg::XLEN-1:0] result
);

  always_comb begin
    case (alu_ctrl)
      rv32_pkg::ALU_ADD: result = s1 + s2;
      rv32_pkg::ALU_SUB: result = s1 - s2;
      rv32_pkg::ALU_AND: result = s1 & s2;
      rv32_pkg::ALU_OR: result = s1 | s2;
      rv32_pkg::ALU_SLT: result = {31'b0, ($signed(s1) < $signed(s2))};
      rv32_pkg::ALU_SLTU: result = {31'b0, s1 < s2};
      rv32_pkg::ALU_XOR: result = s1 ^ s2;
      rv32_pkg::ALU_SLL: result = s1 << s2[4:0];
      rv32_pkg::ALU_SRL: result = s1 >> s2[4:0];
      rv32_pkg::ALU_SRA: result = $signed(s1) >>> s2[4:0];
      default: result = 'h0cc;
    endcase
  end

endmodule
