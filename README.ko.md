Read this in: [English](README.md) | **한국어**

# MIPS 5단계 파이프라인 CPU

Verilog로 구현한 5단계 in-order 파이프라인 MIPS CPU이며, 동적 분기 예측 기능이 추가되어 있습니다.

## Pipeline 구조

`IF -> ID -> EX -> MEM -> WB`, single-issue, in-order 방식.

## 구현된 기능

- **Forwarding**: EX/MEM, MEM/WB 단계의 결과를 ALU operand로 전달하고(`FORWARD.v`), 레지스터 파일은 같은 사이클에 동일 레지스터를 write/read하는 경우를 내부적으로 해결합니다(`RF.v`).
- **Hazard 처리**: load-use stall과 분기 피연산자 hazard로 축소했으며(`HAZARD.v`), 그 외 RAW hazard는 stall 대신 forwarding으로 해결합니다.
- **동적 분기 예측**: 64-entry direct-mapped Branch Target Buffer(BTB) + 256-entry 2-bit saturating counter Pattern History Table(PHT).
- **조기 분기 해석(Early branch resolution)**: 분기/점프 target을 ID 단계에서 계산·비교하며, 오예측 시 다음 사이클에 flush 및 PC 재지정을 수행합니다.

## 지원 명령어

- R-type: `ADDU SUBU AND OR XOR NOR SLL SRL SRA SLT SLTU JR`
- I-type: `LW SW ADDIU SLTI SLTIU LUI ANDI ORI XORI BEQ BNE`
- J-type: `J JAL`

## 모듈 구성

| 파일 | 역할 |
|---|---|
| `CPU.v` | 최상위 파이프라인 datapath 및 파이프라인 레지스터 |
| `CTRL.v` | 메인 제어 유닛 |
| `ALU.v` | 산술/논리 연산 유닛 |
| `RF.v` | 내부 write/read forwarding을 지원하는 32x32-bit 레지스터 파일 |
| `MEM.v` | 명령어/데이터 통합 메모리 모델 |
| `FORWARD.v` | EX/MEM, MEM/WB operand forwarding 유닛 |
| `HAZARD.v` | load-use 및 분기 피연산자 hazard/stall 감지 |
| `GLOBAL.v` | opcode/funct/ALU-op 매크로 정의 |

## 시뮬레이션

Icarus Verilog(`iverilog` / `vvp`) 기준으로 작성되었습니다. 테스트벤치와 테스트 프로그램은 이 저장소에 포함되어 있지 않으며, `MEM.v`와 `RF.v`는 시뮬레이션 시 `initial_mem.mem` / `initial_reg.mem` `$readmemh` 이미지가 필요합니다.

## 검증 상태

시뮬레이션으로만 검증되었으며, FPGA 합성이나 보드 구동은 아직 수행되지 않았습니다.
