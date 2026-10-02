`timescale 1ns / 1ps

`ifndef MEM_LATENCY_TB
`define MEM_LATENCY_TB 5
`endif

`ifndef DCACHE_BYPASS_TB
`define DCACHE_BYPASS_TB 0
`endif

module CORE_OOO_tb;
    reg clk, rst;
    wire halt;

    CORE_OOO #(.MEM_LATENCY(`MEM_LATENCY_TB), .DCACHE_BYPASS(`DCACHE_BYPASS_TB)) dut(.clk(clk), .rst(rst), .halt(halt));

    always #5 clk = ~clk;

    integer i, errors, cycles, retired, trace_fd;
    reg [31:0] ref_reg [0:31];
    reg [31:0] ref_mem [0:8191];
    reg halted;

    integer dispatch_count, commit_count, store_write_count, committed_store_count;
    integer invariant_violations;
    integer cache_hits, cache_misses;
    integer load_hits, load_misses, store_hits, store_misses;
    integer clean_evictions, dirty_evictions, writeback_words, line_fills;
    integer rob_full_cycles, iq_full_cycles;
    integer rob_occ_sum, rob_occ_max;
    integer mem_outstanding_cycles;

    // See CPU_tb.v for why a write-back cache needs this: a dirty line
    // can still be resident in L1 at halt, so dut.mem.memory[] alone
    // would report a false mismatch for its newest value.
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

    always @(posedge clk) begin
        if (rst) begin
            halted <= 1'b0;
        end else begin
            cycles = cycles + 1;
            if (halt) halted <= 1'b1;

            if (dispatch_count !== commit_count + dut.rob_count) begin
                $display("INVARIANT VIOLATION at cycle %0d: dispatch_count=%0d != commit_count=%0d + rob_count=%0d",
                    cycles, dispatch_count, commit_count, dut.rob_count);
                invariant_violations = invariant_violations + 1;
            end

            if (dut.cdb_valid && dut.rob_ready[dut.cdb_tag]) begin
                $display("INVARIANT VIOLATION at cycle %0d: double writeback to rob tag %0d", cycles, dut.cdb_tag);
                invariant_violations = invariant_violations + 1;
            end

            if (dut.dispatch_fire) dispatch_count = dispatch_count + 1;

            if (dut.dc_req_valid && dut.dc_req_ready && dut.dc_req_write)
                store_write_count = store_write_count + 1;

            if (!dut.dcache.BYPASS && dut.dcache.state == 2'd0 && dut.dcache.req_valid) begin
                if (dut.dcache.req_write) begin
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

            if (dut.rob_full) rob_full_cycles = rob_full_cycles + 1;
            if (!dut.iq_has_free) iq_full_cycles = iq_full_cycles + 1;
            if (dut.mem_owner_valid) mem_outstanding_cycles = mem_outstanding_cycles + 1;

            rob_occ_sum = rob_occ_sum + dut.rob_count;
            if (dut.rob_count > rob_occ_max) rob_occ_max = dut.rob_count;

            if (dut.commit_fire) begin
                commit_count = commit_count + 1;
                if (dut.rob_type[dut.head] == 2'd2) committed_store_count = committed_store_count + 1;
                retired = retired + 1;
                $fwrite(trace_fd, "%0d %08x %08x %0d %02x %08x %0d %08x %08x %0d\n",
                    cycles, dut.rob_pc[dut.head], dut.rob_inst[dut.head],
                    dut.rob_we[dut.head], dut.rob_dest[dut.head], dut.rob_value[dut.head],
                    (dut.rob_type[dut.head]==2'd2), dut.rob_mem_addr[dut.head], dut.rob_mem_wdata[dut.head],
                    dut.rob_halt[dut.head]);
            end
        end
    end

    initial begin
        clk = 0;
        rst = 1;
        cycles = 0;
        retired = 0;
        dispatch_count = 0;
        commit_count = 0;
        store_write_count = 0;
        committed_store_count = 0;
        invariant_violations = 0;
        cache_hits = 0;
        cache_misses = 0;
        load_hits = 0;
        load_misses = 0;
        store_hits = 0;
        store_misses = 0;
        clean_evictions = 0;
        dirty_evictions = 0;
        writeback_words = 0;
        line_fills = 0;
        rob_full_cycles = 0;
        iq_full_cycles = 0;
        mem_outstanding_cycles = 0;
        rob_occ_sum = 0;
        rob_occ_max = 0;
        trace_fd = $fopen("retire_trace.log", "w");
        repeat (3) @(posedge clk);
        rst = 0;

        while (!halted) begin
            @(posedge clk);
            #1;
        end

        errors = 0;
        $readmemh("reference_reg.mem", ref_reg);
        $readmemh("reference_mem.mem", ref_mem);

        for (i = 0; i < 32; i = i + 1) begin
            if (dut.committed_rf[i] !== ref_reg[i]) begin
                $display("MISMATCH reg[%0d]: got %08x expected %08x", i, dut.committed_rf[i], ref_reg[i]);
                errors = errors + 1;
            end
        end

        for (i = 0; i < 8192; i = i + 1) begin
            if (mem_expected(i) !== ref_mem[i]) begin
                $display("MISMATCH mem[%0d]: got %08x expected %08x", i, mem_expected(i), ref_mem[i]);
                errors = errors + 1;
            end
        end

        if (store_write_count !== committed_store_count) begin
            $display("INVARIANT VIOLATION: store_write_count=%0d != committed_store_count=%0d (duplicate or missing D-cache write)",
                store_write_count, committed_store_count);
            invariant_violations = invariant_violations + 1;
        end

        $display("cycles = %0d, retired = %0d", cycles, retired);
        $display("cache_hits = %0d, cache_misses = %0d", cache_hits, cache_misses);
        $display("load_hits = %0d, load_misses = %0d, store_hits = %0d, store_misses = %0d", load_hits, load_misses, store_hits, store_misses);
        $display("clean_evictions = %0d, dirty_evictions = %0d, writeback_words = %0d, line_fills = %0d", clean_evictions, dirty_evictions, writeback_words, line_fills);
        $display("rob_full_cycles = %0d, iq_full_cycles = %0d, mem_outstanding_cycles = %0d", rob_full_cycles, iq_full_cycles, mem_outstanding_cycles);
        $display("rob_occupancy_avg_x1000 = %0d, rob_occupancy_max = %0d", (rob_occ_sum*1000)/cycles, rob_occ_max);
        $display("invariants: dispatch=%0d commit=%0d store_writes=%0d committed_stores=%0d violations=%0d",
            dispatch_count, commit_count, store_write_count, committed_store_count, invariant_violations);
        if (errors == 0 && invariant_violations == 0)
            $display("PASS: architectural state matches reference");
        else
            $display("FAIL: %0d mismatches, %0d invariant violations", errors, invariant_violations);

        $fclose(trace_fd);
        $finish;
    end

    initial begin
        #2000000;
        $display("TIMEOUT: halt never asserted");
        $fclose(trace_fd);
        $finish;
    end
endmodule
