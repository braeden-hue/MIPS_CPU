
module HAZARD(
    input [4:0]     if_id_rs,
    input [4:0]     if_id_rt,

    input           id_ex_RegWrite,
    input [4:0]     id_ex_wr_addr,
    input           id_ex_valid, 
    
    input           ex_mem_RegWrite,
    input [4:0]     ex_mem_wr_addr,
    input           ex_mem_valid,
    input [1:0]     id_ex_MemtoReg,
    input           Branch,


    output          stall
    );

    wire load_use = id_ex_valid && id_ex_RegWrite && (id_ex_wr_addr != 0)
                    && (id_ex_MemtoReg == 2'b01)
                    && (id_ex_wr_addr==if_id_rs || id_ex_wr_addr==if_id_rt);

    wire hazard_ex = Branch && id_ex_valid && id_ex_RegWrite && (id_ex_wr_addr != 5'd0)
                    && (id_ex_wr_addr == if_id_rs || id_ex_wr_addr == if_id_rt);    

    wire hazard_mem = Branch && ex_mem_valid && ex_mem_RegWrite && (ex_mem_wr_addr != 5'd0)
                    && (ex_mem_wr_addr == if_id_rs || ex_mem_wr_addr == if_id_rt);
                    
    assign stall = load_use || hazard_ex || hazard_mem;
endmodule