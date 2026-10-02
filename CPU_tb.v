`timescale 1ns / 1ps

`ifndef MEM_LATENCY_TB
`define MEM_LATENCY_TB 5
`endif

`ifndef DCACHE_BYPASS_TB
`define DCACHE_BYPASS_TB 0
`endif

module CPU_tb;
    reg clk, rst;
    wire halt;

    CPU #(.MEM_LATENCY(`MEM_LATENCY_TB), .DCACHE_BYPASS(`DCACHE_BYPASS_TB)) dut(.clk(clk), .rst(rst), .halt(halt));

    always #5 clk = ~clk;

    integer i, errors, cycles, retired, trace_fd;
    integer stall_total, stall_load_use, stall_branch_operand, stall_overlap, stall_memory;
    integer cache_hits, cache_misses, cache_store_passthrough;
    integer load_hits, load_misses, store_hits, store_misses;
    integer clean_evictions, dirty_evictions, writeback_words, line_fills;
    reg [31:0] ref_reg [0:31];
    reg [31:0] ref_mem [0:8191];

    // A write-back cache can leave a dirty line resident in L1 at halt,
    // so comparing dut.mem.memory[] directly would report a false
    // mismatch for any word whose newest value is still only in the
    // cache. This mirrors the cache's own index/offset/tag arithmetic
    // (word_addr == word index here, since addr = {i,2'b00}) to check
    // the cache first and fall back to backing memory otherwise.
    function [31:0] mem_expected;
        input integer idx;
        reg [4:0] set;
        reg [1:0] off;
        reg [22:0] tg;
        begin
            set = idx[6:2];
            off = idx[1:0];
            tg  = idx[29:7];
            if (dut.dcache.valid[set][0] && dut.dcache.dirty[set][0] && dut.dcache.tag[set][0]==tg)
                mem_expected = dut.dcache.data[set][0][off];
            else if (dut.dcache.valid[set][1] && dut.dcache.dirty[set][1] && dut.dcache.tag[set][1]==tg)
                mem_expected = dut.dcache.data[set][1][off];
            else
                mem_expected = dut.mem.memory[idx];
        end
    endfunction

    // Exclusive partition (each stall cycle counted in exactly one bucket,
    // so stall_memory + stall_load_use + stall_branch_operand ==
    // stall_total): memory_stall takes priority because it is what the
    // pipeline actually freezes on (PC..EX/MEM); within the remaining
    // cycles, load_use takes priority over branch_operand since it
    // reflects a real data dependency, not just a missing forwarding
    // path. stall_overlap is an informational count of non-memory-stall
    // cycles where both a load-use and a branch-operand hazard held at
    // once; it is a subset of stall_load_use, not added on top of it.
    always @(posedge clk) begin
        if (!rst) begin
            cycles = cycles + 1;
            if (dut.pipeline_freeze) begin
                stall_total = stall_total + 1;
                if (dut.memory_stall)
                    stall_memory = stall_memory + 1;
                else if (dut.stall_load_use)
                    stall_load_use = stall_load_use + 1;
                else if (dut.stall_hazard_ex || dut.stall_hazard_mem)
                    stall_branch_operand = stall_branch_operand + 1;
                if (!dut.memory_stall && dut.stall_load_use && (dut.stall_hazard_ex || dut.stall_hazard_mem))
                    stall_overlap = stall_overlap + 1;
            end
            if (!dut.dcache.BYPASS && dut.dcache.state == 2'd0 && dut.req_valid) begin
                if (dut.req_write) begin
                    if (dut.dcache.hit) store_hits = store_hits + 1;
                    else store_misses = store_misses + 1;
                end
                else begin
                    if (dut.dcache.hit) begin load_hits = load_hits + 1; cache_hits = cache_hits + 1; end
                    else begin load_misses = load_misses + 1; cache_misses = cache_misses + 1; end
                end
                if (!dut.dcache.hit) begin
                    if (dut.dcache.valid[dut.dcache.index][dut.dcache.victim_way] && dut.dcache.dirty[dut.dcache.index][dut.dcache.victim_way])
                        dirty_evictions = dirty_evictions + 1;
                    else if (dut.dcache.valid[dut.dcache.index][dut.dcache.victim_way])
                        clean_evictions = clean_evictions + 1;
                end
            end
            if (!dut.dcache.BYPASS && dut.dcache.state == 2'd1 && dut.dcache.bk_resp_valid)
                writeback_words = writeback_words + 1;
            if (!dut.dcache.BYPASS && dut.dcache.state == 2'd2 && dut.dcache.bk_resp_valid && dut.dcache.fill_idx == 2'd3)
                line_fills = line_fills + 1;
            if (dut.mem_wb_valid) begin
                retired = retired + 1;
                $fwrite(trace_fd, "%0d %08x %08x %0d %02x %08x %0d %08x %08x %0d\n",
                    cycles, dut.mem_wb_pc, dut.mem_wb_inst,
                    dut.mem_wb_RegWrite, dut.wr_addr, dut.wr_data,
                    dut.mem_wb_MemWrite, dut.mem_wb_mem_addr, dut.mem_wb_mem_wdata,
                    dut.mem_wb_halt);
            end
        end
    end

    initial begin
        clk = 0;
        rst = 1;
        cycles = 0;
        retired = 0;
        stall_total = 0;
        stall_load_use = 0;
        stall_branch_operand = 0;
        stall_overlap = 0;
        stall_memory = 0;
        cache_hits = 0;
        cache_misses = 0;
        cache_store_passthrough = 0;
        load_hits = 0;
        load_misses = 0;
        store_hits = 0;
        store_misses = 0;
        clean_evictions = 0;
        dirty_evictions = 0;
        writeback_words = 0;
        line_fills = 0;
        trace_fd = $fopen("retire_trace.log", "w");
        repeat (3) @(posedge clk);
        rst = 0;

        wait (halt);
        @(posedge clk);
        #1;

        errors = 0;
        $readmemh("reference_reg.mem", ref_reg);
        $readmemh("reference_mem.mem", ref_mem);

        for (i = 0; i < 32; i = i + 1) begin
            if (dut.rf.register_file[i] !== ref_reg[i]) begin
                $display("MISMATCH reg[%0d]: got %08x expected %08x", i, dut.rf.register_file[i], ref_reg[i]);
                errors = errors + 1;
            end
        end

        for (i = 0; i < 8192; i = i + 1) begin
            if (mem_expected(i) !== ref_mem[i]) begin
                $display("MISMATCH mem[%0d]: got %08x expected %08x", i, mem_expected(i), ref_mem[i]);
                errors = errors + 1;
            end
        end

        $display("cycles = %0d, retired = %0d", cycles, retired);
        $display("stall_total = %0d (memory = %0d, load_use = %0d, branch_operand = %0d, overlap = %0d)",
            stall_total, stall_memory, stall_load_use, stall_branch_operand, stall_overlap);
        if (stall_memory + stall_load_use + stall_branch_operand !== stall_total)
            $display("WARNING: exclusive stall buckets do not sum to stall_total (accounting bug)");
        $display("cache_hits = %0d, cache_misses = %0d, store_passthrough = %0d", cache_hits, cache_misses, cache_store_passthrough);
        $display("load_hits = %0d, load_misses = %0d, store_hits = %0d, store_misses = %0d", load_hits, load_misses, store_hits, store_misses);
        $display("clean_evictions = %0d, dirty_evictions = %0d, writeback_words = %0d, line_fills = %0d", clean_evictions, dirty_evictions, writeback_words, line_fills);
        if (errors == 0)
            $display("PASS: architectural state matches reference");
        else
            $display("FAIL: %0d mismatches", errors);

        $fclose(trace_fd);
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT: halt never asserted");
        $fclose(trace_fd);
        $finish;
    end
endmodule
