Read this in: **English** | [한국어](README.ko.md)

# MIPS 5-Stage Pipelined CPU

A 5-stage in-order pipelined MIPS CPU implemented in Verilog, extended with a dynamic branch predictor.

## Pipeline

`IF -> ID -> EX -> MEM -> WB`, single-issue, in-order.

## Implemented features

- **Forwarding**: EX/MEM and MEM/WB stage results are forwarded into the ALU operands (`FORWARD.v`), and the register file resolves a same-cycle write/read to the same register internally (`RF.v`).
- **Hazard detection**: reduced to load-use stalls and branch-operand hazards (`HAZARD.v`); every other RAW hazard is resolved by forwarding instead of stalling.
- **Dynamic branch prediction**: 64-entry direct-mapped Branch Target Buffer (BTB) + 256-entry 2-bit saturating-counter Pattern History Table (PHT).
- **Early branch resolution**: branch/jump targets are computed and compared in the ID stage, with next-cycle misprediction flush and PC redirection.

## Supported instruction subset

- R-type: `ADDU SUBU AND OR XOR NOR SLL SRL SRA SLT SLTU JR`
- I-type: `LW SW ADDIU SLTI SLTIU LUI ANDI ORI XORI BEQ BNE`
- J-type: `J JAL`

## Modules

| File | Role |
|---|---|
| `CPU.v` | Top-level pipeline datapath and pipeline registers |
| `CTRL.v` | Main control unit |
| `ALU.v` | Arithmetic/logic unit |
| `RF.v` | 32x32-bit register file with internal write/read forwarding |
| `MEM.v` | Unified instruction/data memory model |
| `FORWARD.v` | EX/MEM and MEM/WB operand forwarding unit |
| `HAZARD.v` | Load-use and branch-operand hazard/stall detection |
| `GLOBAL.v` | Opcode/funct/ALU-op macro definitions |

## Simulation

Written for Icarus Verilog (`iverilog` / `vvp`). Testbenches and test programs are not included in this repository; `MEM.v` and `RF.v` expect `initial_mem.mem` / `initial_reg.mem` `$readmemh` images to be supplied at simulation time.

## Status

Verified in simulation only. No FPGA synthesis or board bring-up has been performed yet.
