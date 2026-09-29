Read this in: [English](README.md) | **한국어**

# MIPS 5단계 파이프라인 CPU

Verilog로 구현한 single-issue, in-order MIPS CPU입니다. 기본적인 5단계 파이프라인에서 출발해 데이터 forwarding, 필요한 경우에만 동작하는 hazard stall, ID 단계 분기 판정, 동적 분기 예측을 추가했습니다.

파이프라인은 `IF -> ID -> EX -> MEM -> WB` 순서로 동작합니다. 현재 메모리는 명령어와 데이터가 32 KiB flat 배열을 공유하고 read가 조합 논리로 끝나는 단순한 모델입니다. 캐시와 가변 메모리 지연은 아직 구현하지 않았습니다.

## 설계에서 확장한 부분

Forwarding unit은 EX/MEM과 MEM/WB 단계의 결과를 ALU 입력으로 우회시킵니다. 같은 사이클에 동일 레지스터를 write/read하는 경우는 register file 내부에서 처리합니다. 이에 따라 hazard unit은 모든 데이터 의존성을 일괄 정지시키지 않고, load-use 의존성과 아직 값이 준비되지 않은 branch operand에 대해서만 stall을 발생시킵니다.

분기 결과는 ID 단계에서 판정합니다. 64-entry direct-mapped BTB가 예상 target을 제공하고, 256-entry 2-bit saturating counter table이 조건 분기의 방향을 예측합니다. 실제 결과가 예측과 다르면 PC를 올바른 주소로 돌리고 뒤따르던 명령어를 flush합니다.

지원하는 명령어는 다음과 같습니다.

- R-type: `ADDU SUBU AND OR XOR NOR SLL SRL SRA SLT SLTU JR`
- I-type: `LW SW ADDIU SLTI SLTIU LUI ANDI ORI XORI BEQ BNE`
- J-type: `J JAL`

`CPU.v`에는 datapath, pipeline register, branch predictor state가 들어 있습니다. `CTRL.v`는 명령어를 해석하고, `ALU.v`, `RF.v`, `MEM.v`는 각각 연산·레지스터·메모리를 담당합니다. Forwarding과 stall 판단은 `FORWARD.v`, `HAZARD.v`로 분리했으며 opcode와 function code는 `GLOBAL.v`에 정의했습니다.

## 검증

### Icarus Verilog

[`CPU_tb.v`](CPU_tb.v)는 CPU를 `halt`까지 실행한 뒤 32개 레지스터와 8,192개 메모리 word를 reference dump와 비교하는 self-checking testbench입니다. 전체 어셈블리 프로그램과 reference image는 수업 자료이므로 저장소에 포함하지 않았으며, 아래에는 무작위 testcase 하나의 일부를 예시로 제시합니다.

아래 결과는 Icarus Verilog로 수업 testcase 6을 실행한 기록입니다.

```console
$ iverilog -o cpu_sim CPU.v CTRL.v ALU.v RF.v MEM.v FORWARD.v HAZARD.v CPU_tb.v
$ cd testcase/testcase6
$ vvp ../../cpu_sim
cycles = 279
PASS: architectural state matches reference
```

**`cycles = 279`**는 branch 48개, jump 56개, load 96개, store 32개가 섞인 이 프로그램을 forwarding, load-use stall, BTB/PHT 예측까지 모두 활성화한 상태로 끝까지 실행한 실측 사이클 수입니다. Testbench는 timeout 없이 `halt`에 도달했고, 전체 레지스터와 메모리 비교에서 mismatch를 출력하지 않았습니다. 이어지는 MARS 교차 검증에서는 최종 `PASS` 문구만 제시하지 않고, 실제로 어떤 architectural state가 만들어졌는지 확인합니다.

### MARS ISA 교차 검증

같은 프로그램을 MARS에서도 실행해 ISA 수준에서 결과를 교차 확인했습니다. Testcase 6은 네 값을 메모리에 저장한 뒤 두 값씩 `$t0`, `$t1`으로 읽어 같은 값의 조합을 찾습니다. 일치한 조합으로 분기할 때마다 경로별 immediate를 `$t4`에 누적합니다.

첫 그룹은 offset 0과 8에 같은 값을 저장합니다. 두 위치를 읽으면 두 번째 비교가 참이 되어 `eq_0_0_2`로 분기합니다.

```diff
  li    $t0, 1141988164
  sw    $t0, 0($gp)            # 첫 번째 비교 후보
  li    $t0, -1333632164
  sw    $t0, 4($gp)
  li    $t0, 1141988164
  sw    $t0, 8($gp)            # offset 0과 같은 값

+ lw    $t0, 0($gp)            # 첫 값을 다시 읽음
+ lw    $t1, 8($gp)            # 같은 값을 다시 읽음
+ beq   $t0, $t1, eq_0_0_2    # 동일하므로 해당 경로 선택

  eq_0_0_2:
+ addiu $t4, $t4, 26827        # 선택된 경로의 값을 누적
```

마지막 그룹도 같은 구조입니다. 동일한 두 값의 10진수 표현은 `-674818380`, 32비트 16진수 표현은 `0xd7c716b4`이므로 실행 후 `$t0`, `$t1`에 이 값이 남습니다. 같은 값을 찾지 못하면 `$a0`에 5를 기록하는 `error` 경로로 이동합니다. 실제 결과의 `$a0 = 0`은 오류 경로를 실행하지 않았음을 뜻하고, `$v0 = 5`는 마지막 명령에 도달했다는 표시입니다.

```diff
  random_7:
  li    $t0, -674818380
  sw    $t0, 0($gp)
  li    $t0, -674818380
  sw    $t0, 8($gp)

+ lw    $t0, 0($gp)
+ lw    $t1, 8($gp)
+ beq   $t0, $t1, eq_7_0_2    # 마지막 동일 값 조합

  eq_7_0_2:
+ addiu $t4, $t4, -366        # $t4에 더하는 마지막 값
+ j     random_8              # error 표시를 건너뜀

  error:
+ li    $a0, 5                # 동일 값이 없을 때만 기록
  random_8:
+ li    $v0, 5                # 프로그램의 마지막 명령
```

실행 전에는 일반 목적 레지스터가 0으로 초기화되어 있습니다. 화면에 보이는 `$gp`, `$sp`는 테스트 프로그램의 계산 결과가 아니라 MARS가 가상 주소 공간에 맞춰 제공하는 기본값입니다.

MARS 실행 전:

![주석을 추가한 MARS 실행 전 레지스터 상태](docs/mars_before_ko_annotated.png)

MARS 실행 후:

![주석을 추가한 MARS 실행 후 레지스터 상태](docs/mars_after_ko_annotated.png)

실행 후 `$a0 = 0`은 오류 경로를 건너뛰었음을 확인하고, `$v0 = 5`는 마지막 명령까지 도달했음을 보여줍니다. `$t0`, `$t1`에는 예상한 마지막 비교 값이 남고, `$t4 = 0x3457`은 테스트 전체에서 선택된 분기 경로의 누적 결과입니다. 이 프로그램 계산값은 RTL reference dump와 일치합니다. `$gp`, `$sp`가 RTL 환경과 다른 것은 두 시뮬레이터의 초기 메모리 배치가 다르기 때문입니다.

## 현재 범위

현재까지는 시뮬레이션으로 검증했으며 FPGA 합성이나 실제 보드 구동은 진행하지 않았습니다. 이후 개발 방향은 [`plan.md`](plan.md)에 정리되어 있습니다. retire trace 기반 검증과 latency-aware memory를 먼저 구축한 뒤 cache hierarchy와 out-of-order core로 확장할 계획입니다.
