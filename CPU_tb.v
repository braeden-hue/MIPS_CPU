`timescale 1ns / 1ps

module CPU_tb;
    reg clk, rst;
    wire halt;

    CPU dut(.clk(clk), .rst(rst), .halt(halt));

    always #5 clk = ~clk;

    integer i, errors, cycles;
    reg [31:0] ref_reg [0:31];
    reg [31:0] ref_mem [0:8191];

    always @(posedge clk) if (!rst) cycles = cycles + 1;

    initial begin
        clk = 0;
        rst = 1;
        cycles = 0;
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
            if (dut.mem.memory[i] !== ref_mem[i]) begin
                $display("MISMATCH mem[%0d]: got %08x expected %08x", i, dut.mem.memory[i], ref_mem[i]);
                errors = errors + 1;
            end
        end

        $display("cycles = %0d", cycles);
        if (errors == 0)
            $display("PASS: architectural state matches reference");
        else
            $display("FAIL: %0d mismatches", errors);

        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT: halt never asserted");
        $finish;
    end
endmodule
