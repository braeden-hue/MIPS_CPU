module FORWARD(
    input  [4:0]  id_ex_rs, id_ex_rt,
    input         ex_mem_RegWrite, ex_mem_valid,
    input  [4:0]  ex_mem_wr_addr,
    input         mem_wb_RegWrite, mem_wb_valid,
    input  [4:0]  mem_wb_wr_addr,
    output [1:0]  ForwardA,
    output [1:0]  ForwardB
);
    assign ForwardA = ex_mem_valid && ex_mem_RegWrite && ex_mem_wr_addr!=0 && ex_mem_wr_addr==id_ex_rs ? 2'b01
             : mem_wb_valid && mem_wb_RegWrite && mem_wb_wr_addr!=0 && mem_wb_wr_addr==id_ex_rs ? 2'b10
             : 2'b00;
    assign ForwardB = ex_mem_valid && ex_mem_RegWrite && ex_mem_wr_addr!=0 && ex_mem_wr_addr==id_ex_rt ? 2'b01
             : mem_wb_valid && mem_wb_RegWrite && mem_wb_wr_addr!=0 && mem_wb_wr_addr==id_ex_rt ? 2'b10
             : 2'b00;
endmodule