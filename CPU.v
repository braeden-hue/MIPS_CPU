`timescale 1ns / 1ps


module CPU(
	input		clk,
	input		rst,
	output 		halt
	);

	reg [1:0]  btb_type      [0:63];
	reg [23:0] btb_tag		 [0:63];
	reg [31:0] btb_target    [0:63];

	reg [1:0]  pht 			 [0:255];

	reg [31:0] if_id_inst, if_id_pc4; reg if_id_valid; reg if_id_halt;
	reg [31:0] if_id_pc, if_id_predict_target;
	reg 	   if_id_predict_taken;
	reg [31:0] id_ex_pc4, id_ex_data1, id_ex_data2, id_ex_ext_imm;
	reg [4:0]  id_ex_rs, id_ex_rt, id_ex_rd, id_ex_shamt;
	reg [1:0]  id_ex_MemtoReg, id_ex_ALUSrcB, id_ex_RegDst;
	reg [3:0]  id_ex_alu_func;
	reg 	   id_ex_ALUSrcA, id_ex_MemWrite, id_ex_RegWrite, id_ex_valid, id_ex_halt;

	reg [31:0] ex_mem_pc4, ex_mem_alu_result, ex_mem_data2;
	reg [4:0]  ex_mem_wr_addr;
	reg [1:0]  ex_mem_MemtoReg;
	reg 	   ex_mem_MemWrite, ex_mem_RegWrite, ex_mem_valid, ex_mem_halt;

	reg [31:0] mem_wb_pc4, mem_wb_alu_result, mem_wb_mem_data;
	reg [4:0]  mem_wb_wr_addr;
	reg [1:0]  mem_wb_MemtoReg;
	reg 	   mem_wb_RegWrite, mem_wb_valid, mem_wb_halt;

	reg [31:0] PC;

	wire [31:0] 	if_inst;

	wire			stall;
	wire			flush;
	wire			branch_taken;
	wire [31:0] 	branch_target;
	wire [31:0] 	jump_target;

	wire [5:0]		opcode;
	wire [4:0]		rs;
	wire [4:0]		rt;
	wire [4:0]		rd;
	wire [4:0]		shamt;
	wire [5:0]		funct;
	wire [15:0]		immi;
	wire [25:0]		immj;
	wire [3:0] 		alu_func;

	wire			Branch;
	wire			B_NE;
	wire			Jump;
	wire			JumpLink;
	wire			JumpReg;
	wire [1:0]		RegDst;
	wire [1:0]		MemtoReg;
	wire 			MemWrite;
	wire			ALUSrcA;
	wire			RegWrite;
	wire [1:0]		ALUSrcB;
	wire			ExtOp;

	wire [31:0]		ext_imm;
	wire [4:0] 		ex_wr_addr = (id_ex_RegDst == 2'b01) ? id_ex_rd :
								 (id_ex_RegDst == 2'b10) ? 5'd31 : id_ex_rt;

	wire [4:0]		rd_addr1;
	wire [4:0]		rd_addr2;
	wire [31:0]		rd_data1;
	wire [31:0]		rd_data2;
	wire [4:0]		wr_addr;
	wire [31:0]		wr_data;

	wire [31:0]		mem_read_data;

	wire [31:0]		operand1;
	wire [31:0]		operand2;
	wire [31:0]		alu_result;

	wire [1:0] 		ForwardA, ForwardB;
	wire [31:0]		forward_data1, forward_data2;

	wire [5:0] 		wbtb_idx;
	wire [23:0] 	wbtb_tag_compare;
	wire 			wbtb_hit;

	wire [7:0] 		wpht_idx;
	wire 			wpht_taken;

	wire 			bp_predict_taken;
	wire [31:0] 	bp_predict_target;

	wire 			actual_taken;
	wire [31:0] 	actual_target;
	wire 			miss;

	wire [31:0] 	correct_target;
	wire [5:0] 		update_btb_index;
	wire [7:0] 		update_pht_index;

	assign flush = miss;
	assign halt = mem_wb_halt && mem_wb_valid;
	assign opcode = if_id_inst[31:26];
	assign rs = if_id_inst[25:21];
	assign rt = if_id_inst[20:16];
	assign rd = if_id_inst[15:11];
	assign shamt = if_id_inst[10:6];
	assign funct = if_id_inst[5:0];
	assign immi = if_id_inst[15:0];
	assign immj = if_id_inst[25:0];
	assign ext_imm = ExtOp ? {{16{immi[15]}}, immi} : {16'b0, immi};

	assign wbtb_idx = PC[7:2];
	assign wbtb_tag_compare = PC[31:8];
	assign wbtb_hit = (btb_type[wbtb_idx] != 2'b00) && (btb_tag[wbtb_idx] == wbtb_tag_compare);

	assign wpht_idx = PC[9:2];
	assign wpht_taken = pht[wpht_idx][1];

	assign rd_addr1 = rs;
	assign rd_addr2 = rt;

	assign branch_taken = Branch && (B_NE ? (rd_data1 != rd_data2) : (rd_data1 == rd_data2));
	assign branch_target = if_id_pc4 + {{14{immi[15]}}, immi, 2'b00};

	assign jump_target = JumpReg ? rd_data1 : {if_id_pc4[31:28], immj, 2'b00};

	assign forward_data1 = (ForwardA==2'b01) ? ex_mem_alu_result :
					(ForwardA==2'b10) ? wr_data : id_ex_data1;
	assign forward_data2 = (ForwardB==2'b01) ? ex_mem_alu_result :
						(ForwardB==2'b10) ? wr_data : id_ex_data2;
	assign operand1 = id_ex_ALUSrcA ? {27'b0, id_ex_shamt} : forward_data1;
	assign operand2 = (id_ex_ALUSrcB == 2'b00) ? forward_data2 : id_ex_ext_imm;

	assign wr_addr = mem_wb_wr_addr;
	assign wr_data = (mem_wb_MemtoReg == 2'b01) ? mem_wb_mem_data :
					 (mem_wb_MemtoReg == 2'b10) ? mem_wb_pc4 : mem_wb_alu_result;

	assign bp_predict_taken = wbtb_hit && ((btb_type[wbtb_idx] == 2'b10) || wpht_taken);
	assign bp_predict_target = btb_target[wbtb_idx];

	assign actual_taken = branch_taken || Jump || JumpReg;
	assign actual_target = (Jump || JumpReg) ? jump_target : branch_target;
	assign miss = if_id_valid && (actual_taken != if_id_predict_taken);
	assign correct_target = actual_taken ? actual_target : if_id_pc4;

	assign update_btb_index = if_id_pc[7:2];
	assign update_pht_index = if_id_pc[9:2];

	always @(posedge clk) begin
		if (rst)			  	  PC <= 0;
		else if(stall) 	 	  	  PC <= PC;
		else if(miss) 	 		  PC <= correct_target;
		else if(bp_predict_taken) PC <= bp_predict_target;
		else 				  	  PC <= PC + 4;

		if(rst) begin
			if_id_inst <= 32'b0;
			if_id_pc4 <= 32'b0;
			if_id_valid <= 1'b0;
			if_id_halt <= 1'b0;
		end
		else if(stall) begin
		end
		else if(flush) begin
			if_id_inst <= 32'b0;
			if_id_pc4 <= 32'b0;
			if_id_valid <= 1'b0;
			if_id_halt <= 1'b0;
		end
		else begin
			if_id_pc <= PC;
			if_id_inst <= if_inst;
			if_id_pc4 <= PC + 4;
			if_id_valid <= 1'b1;
			if_id_halt <= (if_inst == 32'b0);
			if_id_predict_taken <= bp_predict_taken;
			if_id_predict_target <= bp_predict_target;
		end
	end

	integer i;
	always @(posedge clk) begin
		if(rst) begin
			for (i=2'd0; i<64;  i=i+1) btb_type[i] <= 2'b00;
			for (i=2'd0; i<256; i=i+1) pht[i]      <= 2'b01;
		end
		else begin
			if(Branch && if_id_valid) begin
				btb_type  [update_btb_index] <= 2'b01;
				btb_tag   [update_btb_index] <= if_id_pc[31:8];
				btb_target[update_btb_index] <= branch_target;
				if(branch_taken)
					pht[update_pht_index] <= (pht[update_pht_index]==2'b11) ? 2'b11
											: pht[update_pht_index] + 1;
				else
					pht[update_pht_index] <= (pht[update_pht_index]==2'b00) ? 2'b00
											: pht[update_pht_index] - 1;
			end
			if(Jump && if_id_valid) begin
				btb_type  [update_btb_index] <= 2'b10;
				btb_tag   [update_btb_index] <= if_id_pc[31:8];
				btb_target[update_btb_index] <= jump_target;
			end
		end
	end

	always @(posedge clk) begin
		if(rst || stall) begin
		  id_ex_valid    <= 1'b0;
          id_ex_RegWrite <= 1'b0;
          id_ex_MemWrite <= 1'b0;
          id_ex_halt     <= 1'b0;
          id_ex_ALUSrcA  <= 1'b0;
          id_ex_ALUSrcB  <= 2'b0;
          id_ex_alu_func <= 4'b0;
          id_ex_RegDst   <= 2'b0;
          id_ex_MemtoReg <= 2'b0;
          id_ex_rs       <= 5'b0;
          id_ex_rt       <= 5'b0;
          id_ex_rd       <= 5'b0;
          id_ex_shamt    <= 5'b0;
          id_ex_pc4      <= 32'b0;
          id_ex_data1    <= 32'b0;
          id_ex_data2    <= 32'b0;
          id_ex_ext_imm  <= 32'b0;
		end
		else begin
		  id_ex_valid    <= if_id_valid;
          id_ex_RegWrite <= RegWrite && if_id_valid;
          id_ex_MemWrite <= MemWrite && if_id_valid;
          id_ex_halt     <= if_id_halt;
          id_ex_ALUSrcA  <= ALUSrcA;
          id_ex_ALUSrcB  <= ALUSrcB;
          id_ex_alu_func <= alu_func;
          id_ex_RegDst   <= RegDst;
          id_ex_MemtoReg <= MemtoReg;
          id_ex_rs       <= rs;
          id_ex_rt       <= rt;
          id_ex_rd       <= rd;
          id_ex_shamt    <= shamt;
          id_ex_pc4      <= if_id_pc4;
          id_ex_data1    <= rd_data1;
          id_ex_data2    <= rd_data2;
          id_ex_ext_imm  <= ext_imm;
		end
	end

	always @(posedge clk) begin
		if(rst) begin
          ex_mem_pc4        <= 32'b0;
          ex_mem_alu_result <= 32'b0;
          ex_mem_data2      <= 32'b0;
          ex_mem_wr_addr    <= 5'b0;
          ex_mem_MemWrite   <= 1'b0;
          ex_mem_RegWrite   <= 1'b0;
          ex_mem_MemtoReg   <= 2'b0;
          ex_mem_valid      <= 1'b0;
          ex_mem_halt       <= 1'b0;
		end
		else begin
          ex_mem_pc4        <= id_ex_pc4;
          ex_mem_alu_result <= alu_result;
          ex_mem_data2      <= forward_data2;
          ex_mem_wr_addr    <= ex_wr_addr;
          ex_mem_MemWrite   <= id_ex_MemWrite;
          ex_mem_RegWrite   <= id_ex_RegWrite;
          ex_mem_MemtoReg   <= id_ex_MemtoReg;
          ex_mem_valid      <= id_ex_valid;
          ex_mem_halt       <= id_ex_halt;
		end
	end

	always @(posedge clk) begin
		if(rst) begin
          mem_wb_pc4        <= 32'b0;
          mem_wb_alu_result <= 32'b0;
          mem_wb_mem_data   <= 32'b0;
          mem_wb_wr_addr    <= 5'b0;
          mem_wb_RegWrite   <= 1'b0;
          mem_wb_MemtoReg   <= 2'b0;
          mem_wb_valid      <= 1'b0;
          mem_wb_halt       <= 1'b0;
		end
		else begin
          mem_wb_pc4        <= ex_mem_pc4;
          mem_wb_alu_result <= ex_mem_alu_result;
          mem_wb_mem_data   <= mem_read_data;
          mem_wb_wr_addr    <= ex_mem_wr_addr;
          mem_wb_RegWrite   <= ex_mem_RegWrite;
          mem_wb_MemtoReg   <= ex_mem_MemtoReg;
          mem_wb_valid      <= ex_mem_valid;
          mem_wb_halt       <= ex_mem_halt;
		end
	end

	CTRL ctrl (
      .opcode      (opcode),
      .funct       (funct),
	  .Branch 	   (Branch),
	  .B_NE 	   (B_NE),
	  .Jump 	   (Jump),
	  .JumpLink    (JumpLink),
	  .JumpReg 	   (JumpReg),
      .RegDst      (RegDst),
      .ALUSrcA     (ALUSrcA),
      .ALUSrcB     (ALUSrcB),
      .ExtOp       (ExtOp),
      .MemtoReg    (MemtoReg),
      .MemWrite    (MemWrite),
      .RegWrite    (RegWrite),
      .alu_func    (alu_func)
	);
	HAZARD hazard (
		.if_id_rs		  (if_id_inst[25:21]),
		.if_id_rt 		  (if_id_inst[20:16]),
		.id_ex_RegWrite   (id_ex_RegWrite),
		.id_ex_wr_addr    (ex_wr_addr),
		.id_ex_valid 	  (id_ex_valid),
		.id_ex_MemtoReg   (id_ex_MemtoReg),
		.ex_mem_RegWrite  (ex_mem_RegWrite),
		.ex_mem_wr_addr   (ex_mem_wr_addr),
		.ex_mem_valid 	  (ex_mem_valid),
		.Branch			  (Branch),
		.stall 			  (stall)
	);
	RF rf (
		.clk     (clk),
        .rst     (rst),
        .rd_addr1(rd_addr1),
        .rd_addr2(rd_addr2),
        .rd_data1(rd_data1),
        .rd_data2(rd_data2),
        .RegWrite(mem_wb_RegWrite),
        .wr_addr (wr_addr),
        .wr_data (wr_data)
	);

	MEM mem (
		.clk (clk),
		.rst (rst),
		.inst_addr (PC),
		.inst (if_inst),
		.MemWrite (ex_mem_MemWrite),
		.mem_write_data (ex_mem_data2),
		.mem_read_data (mem_read_data),
		.mem_addr(ex_mem_alu_result)
	);

	ALU alu (
		.operand1  (operand1),
        .operand2  (operand2),
        .shamt     (id_ex_shamt),
        .funct     (id_ex_alu_func),
        .alu_result(alu_result)
	);
	FORWARD forward(
		.id_ex_rs		 (id_ex_rs),
		.id_ex_rt		 (id_ex_rt),
		.ex_mem_RegWrite (ex_mem_RegWrite),
		.ex_mem_wr_addr  (ex_mem_wr_addr),
		.ex_mem_valid    (ex_mem_valid),
		.mem_wb_RegWrite (mem_wb_RegWrite),
		.mem_wb_wr_addr  (mem_wb_wr_addr),
		.mem_wb_valid    (mem_wb_valid),
		.ForwardA        (ForwardA),
		.ForwardB        (ForwardB)
	);
endmodule
