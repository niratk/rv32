# risc-v-like CPU

SystemVerilog で記述した、RV32I の一部を実装対象とする CPU です。

## 実装対象の命令

| 命令                  | opcode    | funct3 | funct7    | 動作                                                           |
| --------------------- | --------- | ------ | --------- | -------------------------------------------------------------- |
| `add rd, rs1, rs2`    | `0110011` | `000`  | `0000000` | `rd = rs1 + rs2`                                               |
| `sub rd, rs1, rs2`    | `0110011` | `000`  | `0100000` | `rd = rs1 - rs2`                                               |
| `sll rd, rs1, rs2`    | `0110011` | `001`  | `0000000` | `rd = rs1 << rs2[4:0]`                                         |
| `slt rd, rs1, rs2`    | `0110011` | `010`  | `0000000` | 符号付き比較で `rs1 < rs2` なら `rd = 1`、それ以外は `0`       |
| `sltu rd, rs1, rs2`   | `0110011` | `011`  | `0000000` | 符号なし比較で `rs1 < rs2` なら `rd = 1`、それ以外は `0`       |
| `xor rd, rs1, rs2`    | `0110011` | `100`  | `0000000` | `rd = rs1 ^ rs2`                                               |
| `srl rd, rs1, rs2`    | `0110011` | `101`  | `0000000` | `rd = rs1 >> rs2[4:0]`（論理右シフト）                         |
| `sra rd, rs1, rs2`    | `0110011` | `101`  | `0100000` | `rd = rs1 >> rs2[4:0]`（算術右シフト）                         |
| `or rd, rs1, rs2`     | `0110011` | `110`  | `0000000` | `rd = rs1 \| rs2`                                              |
| `and rd, rs1, rs2`    | `0110011` | `111`  | `0000000` | `rd = rs1 & rs2`                                               |
| `addi rd, rs1, imm`   | `0010011` | `000`  | -         | `rd = rs1 + sext(imm)`                                         |
| `slti rd, rs1, imm`   | `0010011` | `010`  | -         | 符号付き比較で `rs1 < sext(imm)` なら `rd = 1`、それ以外は `0` |
| `sltiu rd, rs1, imm`  | `0010011` | `011`  | -         | 符号なし比較で `rs1 < sext(imm)` なら `rd = 1`、それ以外は `0` |
| `xori rd, rs1, imm`   | `0010011` | `100`  | -         | `rd = rs1 ^ sext(imm)`                                         |
| `ori rd, rs1, imm`    | `0010011` | `110`  | -         | `rd = rs1 \| sext(imm)`                                        |
| `andi rd, rs1, imm`   | `0010011` | `111`  | -         | `rd = rs1 & sext(imm)`                                         |
| `slli rd, rs1, shamt` | `0010011` | `001`  | `0000000` | `rd = rs1 << shamt`                                            |
| `srli rd, rs1, shamt` | `0010011` | `101`  | `0000000` | `rd = rs1 >> shamt`（論理右シフト）                            |
| `srai rd, rs1, shamt` | `0010011` | `101`  | `0100000` | `rd = rs1 >> shamt`（算術右シフト）                            |
| `lui rd, imm`         | `0110111` | -      | -         | `rd = imm[31:12] << 12`                                        |
| `auipc rd, imm`       | `0010111` | -      | -         | `rd = PC + (imm[31:12] << 12)`                                 |
| `jal rd, imm`         | `1101111` | -      | -         | `rd = PC + 4; PC = PC + sext(imm)`                             |
| `jalr rd, imm(rs1)`   | `1100111` | `000`  | -         | `rd = PC + 4; PC = (rs1 + sext(imm)) & ~1`                     |
| `lw rd, imm(rs1)`     | `0000011` | `010`  | -         | `rd = Mem[rs1 + sext(imm)]`                                    |
| `sw rs2, imm(rs1)`    | `0100011` | `010`  | -         | `Mem[rs1 + sext(imm)] = rs2`                                   |
| `beq rs1, rs2, imm`   | `1100011` | `000`  | -         | `rs1 == rs2` なら `PC = PC + sext(imm)`                        |
| `bne rs1, rs2, imm`   | `1100011` | `001`  | -         | `rs1 != rs2` なら `PC = PC + sext(imm)`                        |
| `blt rs1, rs2, imm`   | `1100011` | `100`  | -         | 符号付き比較で `rs1 < rs2` なら `PC = PC + sext(imm)`          |
| `bge rs1, rs2, imm`   | `1100011` | `101`  | -         | 符号付き比較で `rs1 >= rs2` なら `PC = PC + sext(imm)`         |
| `bltu rs1, rs2, imm`  | `1100011` | `110`  | -         | 符号なし比較で `rs1 < rs2` なら `PC = PC + sext(imm)`          |
| `bgeu rs1, rs2, imm`  | `1100011` | `111`  | -         | 符号なし比較で `rs1 >= rs2` なら `PC = PC + sext(imm)`         |

byte/halfword の load/store、CSR、例外、割り込み、RV32I 以外の拡張命令は対象外です。

## アーキテクチャ上の前提と制約

- XLEN と命令長はともに 32 bit です。
- 命令メモリとデータメモリは独立した Harvard 構成のインターフェースです。
- 命令メモリおよび `lw` のデータ読み出しは、アドレスに対して同一サイクルで値が得られる組み合わせ読み出しを想定しています。ready/valid や wait-state はありません。
- データメモリには byte enable がなく、32 bit word の読み書きだけを想定しています。misaligned access の検出や処理はありません。
- PC は Low-active synchronous reset (`rst_n`) により `0x0000_0008` に初期化され、通常は 4 byte ずつ進む想定です。
- レジスタファイルは 32 本、各 32 bit です。`x0` への書き込みは禁止しています。
- 不正命令、未対応命令、算術オーバーフロー、メモリアクセス違反に対する trap はありません。

## 現在の実装状態

上記は実装対象の命令セットです。現状の `core.sv` には次の未完了箇所があり、CPU 全体としての命令実行はまだ保証されません。

- トップモジュールからデータパスへ `clk` と `rst_n` が接続されていません。
- ALU 結果と `rs2` がデータメモリの `addr` / `write_data` に接続されていません。
- 命令デコードは opcode と一部の funct フィールドだけで選択しているため、未対応の load/store や不正な OP/OP-IMM/BRANCH/JALR encoding が、対応命令として誤実行される可能性があります。
- 一部ctrlとdpの責務分担が雑かもしれない
