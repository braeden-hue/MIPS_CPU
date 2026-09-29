# MIPS Microarchitecture Extension Roadmap

## 목표와 기준선

> 이상적인 1-cycle memory를 사용하는 5-stage in-order MIPS 코어를 cycle-accurate memory hierarchy와 ROB 기반 speculative OoO core로 확장하고, 각 구조가 CPI·IPC·memory traffic에 미치는 영향을 정량 평가한다.

취업 포트폴리오가 목적이므로 기능 수보다 검증 완성도, 재현 가능한 수치, 설계 선택의 근거를 우선한다. 현재 기준선은 5-stage pipeline, forwarding/load-use stall, 64-entry BTB, 256-entry 2-bit PHT, ID-stage branch resolution/misprediction flush, RF 내부 forwarding이다. `MEM.v`는 I/D가 공유하는 8192-word flat memory이며 latency와 hit/miss는 없다.

## 공통 설계 원칙

- 기존 코어는 `core_inorder`, 새 코어는 `core_ooo`로 분리한다.
- 두 코어는 동일한 predictor, memory hierarchy, benchmark 및 통계 인터페이스를 공유한다.
- 공통 retire event: `valid, pc, inst, rd_we/addr/data, mem_we/addr/data/mask, exception, halt`.
- 현재 WB에는 원래 PC/inst가 없으므로 Phase 0에서 관찰용 metadata를 전달한다.
- 각 Phase의 완료 조건: directed/random test, golden trace와 final state 일치, assertion 0건, regression 없음, 성능·traffic 측정 재현.

## 실험 방법론 — 통제 비교

현재 course testcase 6의 `279 cycles`는 지연 없는 flat memory에서 얻은 기준선이다. Phase 1에서 메모리 지연을 추가하면 절대 cycle 수가 증가할 수 있으므로, 이 수치와 이후 cache/OoO 수치를 직접 비교해 성능 개선률로 보고하지 않는다. **같은 프로그램과 동일한 메모리 타이밍에서 어떤 구조가 stall을 줄였는가**를 질문으로 삼는다.

| 비교 | 고정 조건 | 관찰할 차이 |
|---|---|---|
| 지연 인지형 in-order, cache bypass ↔ 같은 코어 + blocking L1 | ISA 프로그램·입력·predictor·하위 메모리 지연 | cache hit/miss, miss stall, 요청 수, CPI |
| 같은 cache를 쓰는 in-order ↔ 최소 ROB/LSQ OoO | ISA 프로그램·입력·predictor·cache 설정·하위 메모리 지연 | 독립 작업 중첩, commit 기준 IPC, stall 원인 |
| blocking D-cache ↔ non-blocking D-cache | 같은 코어·프로그램·cache 용량/매핑·하위 메모리 지연 | 동시 miss, MSHR 점유, memory-level parallelism |

각 비교에는 `cycles`, `retired`, `CPI = cycles / retired`, IPC, branch/mispredict, I/D hit/miss, 하위 메모리 요청/traffic, stall 원인을 기록한다. stall 사유는 단일한 exclusive 집계 규칙을 정하고 중복 event는 별도 counter로 센다. 시작/종료 시점, warm/cold cache, 초기 memory/predictor 상태, clock 정의도 고정한다. **retire trace와 최종 register/memory state의 일치가 성능 비교의 전제**다. 다른 명령을 실행한 결과라면 cycle 차이를 성능 개선으로 해석하지 않는다.

원래 flat-memory 코어와의 비교는 correctness 회귀 및 역사적 기준선으로만 보존한다. Phase 1 이후의 통제 실험에는 동일한 지연 모델을 쓰는 cache-bypass 경로를 둔다.

## 첫 완성 목표

1. **Phase 0:** retire trace, golden model, counter 및 작은 공개 benchmark를 마련한다.
2. **Phase 1:** 지연 인지형 memory와 cache-bypass 기준선을 검증한다.
3. **Phase 2 최소 구성:** 작은 blocking L1 D-cache를 구현하고 필요하면 같은 인터페이스에 I-cache를 추가한다. 이 단계에서 cache 유무를 비교한다.
4. **Phase 4 + Phase 5 최소 구성:** single-issue ROB 기반 OoO, 정확한 in-order commit, branch squash, 필요한 만큼의 보수적 LSQ를 구현한다. store의 architectural visibility와 미해결 older store에 대한 load 제약을 먼저 검증한다.
5. **첫 결과:** 동일한 cache/latency/predictor에서 in-order와 OoO를 비교하고, 독립 작업을 실제로 겹쳤다는 timeline과 retire/final-state 검증을 함께 제시한다.

Phase 3의 2-way L1/L2 및 write-back/buffer 확대와 Phase 6의 non-blocking cache/MSHR는 **첫 완성 목표 이후의 확장**이다. 캐시 계층·write path·ROB/LSQ·MSHR를 모두 추가한 뒤 처음 비교하면 성능 차이의 원인을 분리하기 어렵고 검증 범위도 지나치게 커진다.

## 벤치마크 역할 분리

- **Course testcase 6:** 기존 `279 cycles`와 architectural state를 보존하는 correctness regression. 프로그램과 reference image가 공개되지 않았으므로 재현 가능한 대표 성능 benchmark로 쓰지 않는다.
- **Cache 확인용:** 직접 작성한 짧은 순차 접근, 동일 working set 반복 접근, stride/conflict 접근. 각 프로그램은 동일한 명령·입력으로 cache-bypass 및 cache-on을 실행한다.
- **OoO 확인용:** 긴 load 뒤 그 결과와 무관한 ALU 연산이 이어지는 프로그램과 dependent load chain을 각각 작성한다. 전자는 overlap을, 후자는 overlap 기회가 적을 때의 한계를 보여 준다.
- **향후 MSHR 확인용:** 서로 다른 line으로 가는 독립 load들과 같은 line 재요청을 분리해 사용한다.

독립 명령이 거의 없는 프로그램에서 ROB 추가만으로 cycle 수가 줄지 않아도 설계 실패는 아니다. 해당 benchmark의 의존성 구조와 miss 동작을 설명하고, 어떤 병목이 실제로 남았는지 counter로 확인한다. 모든 성능용 프로그램의 source, 초기 데이터, 빌드 방법과 golden 결과를 공개할 수 있는 자체 작성 자료로 유지한다.

## Phase 0 — 검증 및 측정 인프라

- Python sequential MIPS interpreter를 golden model로 작성한다.
- RTL retire trace와 golden trace, register/memory final state를 자동 비교한다.
- directed test와 seed 기반 random test, assertion/invariant를 구축한다.
- `cycles`, `retired`, branch/mispredict와 stall 원인을 계측한다.
- stall 원인은 data hazard, branch operand, I/D/L2 miss, memory backpressure, ROB/IQ/LSQ/MSHR full로 구분한다. 중복 event와 exclusive stall-cycle 집계 규칙도 명시한다.
- baseline CPI와 branch prediction on/off 결과를 보존한다.

## Phase 1 — Latency-aware memory

```text
req_valid, req_ready, req_addr, req_write, req_wdata, req_wmask, req_id
resp_valid, resp_rdata, resp_error, resp_id
```

- 처음에는 fixed latency(예: 20 cycles), non-pipelined, one outstanding request.
- I/D arbitration은 결정적 D-side 우선으로 시작하고 starvation을 검사한다.
- request/response를 분리해 Phase 6의 multiple outstanding transaction으로 확장한다.
- latency 1/5/20에서 architectural result가 같고 stall 수가 예상과 맞아야 완료한다.

## Phase 2 — Blocking L1

L1 D-cache 후 L1 I-cache 순서로 구현한다. 첫 기준은 direct-mapped, 1-cycle hit, blocking, one outstanding miss, write-through/no-write-allocate다. 기준 구현을 검증한 뒤 제한된 parameter/variant로 WT/NWA, WT/WA, WB/WA와 direct-mapped/2-way를 비교한다. I/D hit rate, CPI, miss stall, write traffic, dirty eviction, AMAT를 측정한다.

## Phase 3 — 2-way L1/L2와 write path (첫 완성 목표 이후)

- split 2-way L1 I/D(1-bit true LRU), unified 2-way L2, fixed-latency memory.
- write-back/write-allocate.
- committed store buffer와 dirty eviction buffer를 별도 구조로 두고 full/backpressure/drain을 정의한다.
- 동일-line write merging은 두 buffer 검증 후 실험 기능으로 추가한다.

| 구조 | 역할 |
|---|---|
| Committed store buffer | commit된 store의 L1 반영 대기 |
| Dirty eviction buffer | 축출된 dirty line의 하위 writeback 대기 |
| Write merging | 동일 line 대상 대기 write 병합 |

## Phase 4 — ROB 기반 single-issue OoO

ROB는 후속 기능이 아니라 처음부터 OoO의 중심으로 설계한다.

```text
Fetch/Decode → Rename/Dispatch → ROB+IQ allocation
→ OoO Issue/Execute → Tagged Writeback → ROB in-order Commit
```

- single-issue fetch/decode/dispatch/commit, 여러 instruction in flight.
- 8~16-entry ROB, 8-entry unified IQ, RAT와 committed map/state 분리.
- 1-cycle integer ALU와 multi-cycle MUL 하나, tagged writeback/CDB.
- branch recovery, younger entry squash, precise exception 골격.
- Phase 5 전이라도 ROB-LSQ ID, store commit 권한, squash 인터페이스를 확정한다.

완료 기준은 completion 순서가 달라도 commit 결과가 golden model과 일치하고 잘못된 경로의 architectural side effect가 없는 것이다.

## Phase 5 — Conservative LSQ

- Load/Store Queue, store-to-load forwarding.
- store는 ROB head에서 commit된 뒤에만 architectural visibility를 얻는다.
- 주소 미확정 older store가 있으면 younger load를 issue하지 않는다.
- blocking miss 중 독립 ALU 실행은 허용한다.
- squash 시 speculative load와 uncommitted store를 제거한다.
- speculative load, violation replay, selective replay는 제외한다.

같은 주소, 부분 overlap, 다른 주소, branch squash, cache miss 혼합 test로 검증한다.

## Phase 6 — Non-blocking D-cache와 MSHR (첫 완성 목표 이후)

목표는 miss 뒤의 독립 ALU뿐 아니라 다른 독립 memory access도 진행시키는 것이다.

- L1 D-cache를 non-blocking으로 확장하고 I-cache는 우선 blocking으로 유지한다.
- 2~4-entry parameterized MSHR와 line-address lookup.
- 서로 다른 line의 multiple outstanding miss.
- 같은 line secondary miss를 기존 MSHR에 병합(hit-under-miss 포함).
- 각 waiter의 ROB/LSQ destination을 보존하고 refill 후 wakeup/writeback.
- MSHR full일 때만 새 독립 miss에 backpressure.
- refill/hit port arbitration과 eviction/L2 request 충돌 처리.
- squash된 load의 response는 architectural state에 반영하지 않지만 유효 refill은 허용한다.
- `req_id/resp_id`로 response를 식별한다. memory의 out-of-order response는 parameter로 선택한다.

초기 제외 범위: critical-word-first, early restart, banked/multiport array, memory-order replay.

필수 invariant:

- cache line당 primary MSHR는 하나뿐이다.
- accepted miss는 정확히 한 번 완료 또는 폐기된다.
- 모든 waiter 처리 후에만 MSHR를 재할당한다.
- generation/tag 검사로 stale response가 재사용된 ROB/LSQ entry를 깨우지 못한다.
- dirty data는 refill/eviction 순서와 무관하게 유실되지 않는다.

비교 실험: blocking/non-blocking, MSHR 1/2/4개, merging on/off, memory latency별 IPC·occupancy, in-order/OoO의 memory-level parallelism. 완료 기준은 독립 miss 동시 진행, same-line 요청 병합, MSHR full·squash·refill 충돌에서 golden model 및 request/response 보존 assertion을 모두 만족하는 것이다.

## Phase 6 이후 선택 확장

- TLB/VIPT: 4 KiB page, 8-entry fully associative I/D TLB, hardware refill, L1 VIPT/L2 PIPT. exception/restart가 필요하므로 별도 milestone.
- Multicore/MSI: 2-core private L1/shared L2. coherence 검증 규모가 커서 별도 프로젝트 수준.
- 기타: dual issue, speculative load/replay, larger L2/pseudo-LRU.

## 포트폴리오 결과 (단계별 공개)

첫 완성 목표까지의 결과와 후속 확장 결과를 구분하며, 미구현 항목을 완료 성과로 소개하지 않는다.


- baseline CPI와 branch prediction on/off.
- latency별 CPI/IPC, cache size/associativity별 miss rate.
- write policy별 traffic/dirty eviction.
- in-order/OoO IPC, ROB 크기별 성능, forwarding 효과.
- blocking/non-blocking 비교, MSHR 수·merging에 따른 IPC/요청 수.
- cache miss 중 독립 ALU 및 memory instruction 진행 timeline.
- 가능하면 LUT/FF/area와 timing.

권장 benchmark: array sum, matrix multiply, memcpy, pointer chasing, branch-heavy loop, independent multi-stream load, same-line repeated access.

## 다음 작업(아직 구현하지 않음)

1. 지원 ISA와 corner case 고정.
2. retire 인터페이스와 trace 포맷 확정.
3. Python golden model 의미 명세.
4. counter event와 중복 집계 정책 확정.
5. Phase별 test matrix와 완료 기준 체크리스트 작성.
6. 이후 Phase 0 구현 시작.
