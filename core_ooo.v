`timescale 1ns / 1ps
`include "GLOBAL.v"

module CORE_OOO #(
	parameter ROB_ENTRIES = 16,
	parameter IQ_ENTRIES = 8,
	parameter MEM_LATENCY = 5,
	parameter DCACHE_BYPASS = 1'b0
	) (
	input  clk,
	input  rst,
	output halt
	);

	localparam ROB_TAG_W = $clog2(ROB_ENTRIES);
	localparam IQ_IDX_W  = $clog2(IQ_ENTRIES);
	localparam TYPE_ALU = 2'd0, TYPE_LOAD = 2'd1, TYPE_STORE = 2'd2;

	initial begin
		if ((ROB_ENTRIES & (ROB_ENTRIES-1)) != 0) begin
			$display("ERROR: ROB_ENTRIES=%0d must be a power of two (age_dist relies on fixed-width wraparound subtraction)", ROB_ENTRIES);
			$finish;
		end
	end

	reg [31:0] PC;

	reg [1:0]  btb_type   [0:63];
	reg [23:0] btb_tag    [0:63];
	reg [31:0] btb_target [0:63];
	reg [1:0]  pht        [0:255];

	wire [31:0] if_inst;
	wire [5:0]  opcode = if_inst[31:26];
	wire [4:0]  rs     = if_inst[25:21];
	wire [4:0]  rt     = if_inst[20:16];
	wire [4:0]  rd     = if_inst[15:11];
	wire [4:0]  shamt_f= if_inst[10:6];
	wire [5:0]  funct  = if_inst[5:0];
	wire [15:0] immi   = if_inst[15:0];
	wire [25:0] immj   = if_inst[25:0];
	wire [31:0] pc4    = PC + 4;

	wire Branch, B_NE, Jump, JumpLink, JumpReg;
	wire [1:0] RegDst, MemtoReg_c, ALUSrcB_c;
	wire ALUSrcA_c, ExtOp, MemWrite_c, RegWrite_c;
	wire [3:0] alu_func;

	CTRL ctrl (
		.opcode(opcode), .funct(funct),
		.Branch(Branch), .B_NE(B_NE), .Jump(Jump), .JumpLink(JumpLink), .JumpReg(JumpReg),
		.RegDst(RegDst), .ALUSrcA(ALUSrcA_c), .ALUSrcB(ALUSrcB_c), .ExtOp(ExtOp),
		.MemtoReg(MemtoReg_c), .MemWrite(MemWrite_c), .RegWrite(RegWrite_c), .alu_func(alu_func)
	);

	wire [31:0] ext_imm = ExtOp ? {{16{immi[15]}}, immi} : {16'b0, immi};
	wire is_halt_word = (if_inst == 32'b0);

	wire is_rtype  = (opcode == `OP_RTYPE);
	wire is_jr     = is_rtype && (funct == `FUNCT_JR);
	wire is_shift  = is_rtype && (funct==`FUNCT_SLL || funct==`FUNCT_SRL || funct==`FUNCT_SRA);
	wire is_alureg = is_rtype && !is_jr;
	wire is_lw     = (opcode == `OP_LW);
	wire is_sw     = (opcode == `OP_SW);
	wire is_beq    = (opcode == `OP_BEQ);
	wire is_bne    = (opcode == `OP_BNE);
	wire is_branch = is_beq || is_bne;
	wire is_j      = (opcode == `OP_J);
	wire is_jal    = (opcode == `OP_JAL);
	wire is_cf     = is_branch || is_j || is_jal || is_jr;
	wire is_mem    = is_lw || is_sw;

	wire is_imm_arith = (opcode==`OP_ADDIU) || (opcode==`OP_SLTI) || (opcode==`OP_SLTIU);
	wire is_imm_logic = (opcode==`OP_ANDI) || (opcode==`OP_ORI) || (opcode==`OP_XORI);
	wire uses_rs = (is_alureg && !is_shift) || is_jr || is_lw || is_sw || is_branch || is_imm_arith || is_imm_logic;
	wire uses_rt = is_alureg || is_sw || is_branch;
	wire dest_is_rd = is_alureg;
	wire dest_is_rt = is_lw || is_imm_arith || is_imm_logic || (opcode==`OP_LUI);
	wire [4:0] dest_reg = is_jal ? 5'd31 : dest_is_rd ? rd : dest_is_rt ? rt : 5'd0;
	wire writes_dest = is_jal || dest_is_rd || dest_is_rt;

	wire use_imm_op2 = !is_alureg;
	wire [31:0] imm_for_addr = (is_lw || is_sw) ? {{16{immi[15]}}, immi} : ext_imm;

	reg [31:0] committed_rf [0:31];

	reg               rob_valid [0:ROB_ENTRIES-1];
	reg               rob_ready [0:ROB_ENTRIES-1];
	reg [1:0]         rob_type  [0:ROB_ENTRIES-1];
	reg [4:0]         rob_dest  [0:ROB_ENTRIES-1];
	reg [31:0]        rob_value [0:ROB_ENTRIES-1];
	reg [31:0]        rob_pc    [0:ROB_ENTRIES-1];
	reg [31:0]        rob_inst  [0:ROB_ENTRIES-1];
	reg               rob_halt  [0:ROB_ENTRIES-1];
	reg               rob_we    [0:ROB_ENTRIES-1];
	reg [31:0]        rob_mem_addr [0:ROB_ENTRIES-1];
	reg [31:0]        rob_mem_wdata[0:ROB_ENTRIES-1];
	reg               rob_addr_ready[0:ROB_ENTRIES-1];
	reg               rob_data_ready[0:ROB_ENTRIES-1];
	reg               rob_req_sent  [0:ROB_ENTRIES-1];
	reg               rob_resp_recv [0:ROB_ENTRIES-1];

	reg [ROB_TAG_W-1:0] head, tail;
	reg [ROB_TAG_W:0]   rob_count;
	wire rob_full  = (rob_count == ROB_ENTRIES);
	wire rob_empty = (rob_count == 0);

	reg               rat_busy [0:31];
	reg [ROB_TAG_W-1:0] rat_tag [0:31];

	reg                 iq_valid [0:IQ_ENTRIES-1];
	reg [ROB_TAG_W-1:0] iq_rob_idx [0:IQ_ENTRIES-1];
	reg [1:0]           iq_type  [0:IQ_ENTRIES-1];
	reg [3:0]           iq_alu_func[0:IQ_ENTRIES-1];
	reg                 iq_is_shift[0:IQ_ENTRIES-1];
	reg                 iq_use_imm[0:IQ_ENTRIES-1];
	reg [31:0]          iq_imm[0:IQ_ENTRIES-1];
	reg [4:0]           iq_shamt[0:IQ_ENTRIES-1];
	reg                 iq_src1_ready[0:IQ_ENTRIES-1];
	reg [31:0]          iq_src1_value[0:IQ_ENTRIES-1];
	reg [ROB_TAG_W-1:0] iq_src1_tag[0:IQ_ENTRIES-1];
	reg                 iq_src2_ready[0:IQ_ENTRIES-1];
	reg [31:0]          iq_src2_value[0:IQ_ENTRIES-1];
	reg [ROB_TAG_W-1:0] iq_src2_tag[0:IQ_ENTRIES-1];

	wire cdb_valid;
	wire [31:0] cdb_value;
	wire [ROB_TAG_W-1:0] cdb_tag;

	wire [31:0] iq_eff_src1_value[0:IQ_ENTRIES-1];
	wire        iq_eff_src1_ready[0:IQ_ENTRIES-1];
	wire [31:0] iq_eff_src2_value[0:IQ_ENTRIES-1];
	wire        iq_eff_src2_ready[0:IQ_ENTRIES-1];

	genvar gi;
	generate
		for (gi = 0; gi < IQ_ENTRIES; gi = gi + 1) begin : IQEFF
			assign iq_eff_src1_ready[gi] = iq_src1_ready[gi] || (cdb_valid && !iq_src1_ready[gi] && cdb_tag==iq_src1_tag[gi]);
			assign iq_eff_src1_value[gi] = iq_src1_ready[gi] ? iq_src1_value[gi] : cdb_value;
			assign iq_eff_src2_ready[gi] = iq_src2_ready[gi] || (cdb_valid && !iq_src2_ready[gi] && cdb_tag==iq_src2_tag[gi]);
			assign iq_eff_src2_value[gi] = iq_src2_ready[gi] ? iq_src2_value[gi] : cdb_value;
		end
	endgenerate

	function [ROB_TAG_W-1:0] age_dist;
		input [ROB_TAG_W-1:0] idx;
		begin
			age_dist = idx - head;
		end
	endfunction

	reg ex_valid;
	reg [ROB_TAG_W-1:0] ex_rob_idx;
	reg [3:0] ex_alu_func;
	reg [31:0] ex_op1, ex_op2;
	reg [4:0] ex_shamt;

	wire [31:0] ex_result;
	ALU alu (
		.operand1(ex_op1), .operand2(ex_op2), .shamt(ex_shamt),
		.funct(ex_alu_func), .alu_result(ex_result)
	);

	reg buffer_occupied;
	reg [31:0] buffer_value;
	reg [ROB_TAG_W-1:0] buffer_tag;

	reg mem_owner_valid;
	reg mem_owner_is_store;
	reg [ROB_TAG_W-1:0] mem_owner_tag;

	wire [31:0] dc_req_addr, dc_req_wdata;
	wire        dc_req_valid, dc_req_ready, dc_req_write;
	wire        dc_resp_valid, dc_resp_error;
	wire [31:0] dc_resp_rdata;

	wire [31:0] bk_req_addr, bk_req_wdata;
	wire        bk_req_valid, bk_req_ready, bk_req_write;
	wire [3:0]  bk_req_wmask;
	wire        bk_resp_valid, bk_resp_error;
	wire [31:0] bk_resp_rdata;

	DCACHE #(.BYPASS(DCACHE_BYPASS)) dcache (
		.clk(clk), .rst(rst),
		.req_valid(dc_req_valid), .req_ready(dc_req_ready), .req_addr(dc_req_addr),
		.req_write(dc_req_write), .req_wdata(dc_req_wdata), .req_wmask(4'hF),
		.resp_valid(dc_resp_valid), .resp_rdata(dc_resp_rdata), .resp_error(dc_resp_error),
		.bk_req_valid(bk_req_valid), .bk_req_ready(bk_req_ready), .bk_req_addr(bk_req_addr),
		.bk_req_write(bk_req_write), .bk_req_wdata(bk_req_wdata), .bk_req_wmask(bk_req_wmask),
		.bk_resp_valid(bk_resp_valid), .bk_resp_rdata(bk_resp_rdata), .bk_resp_error(bk_resp_error)
	);

	MEM #(.MEM_LATENCY(MEM_LATENCY)) mem (
		.clk(clk), .rst(rst), .inst_addr(PC), .inst(if_inst),
		.req_valid(bk_req_valid), .req_ready(bk_req_ready), .req_addr(bk_req_addr),
		.req_write(bk_req_write), .req_wdata(bk_req_wdata), .req_wmask(bk_req_wmask),
		.resp_valid(bk_resp_valid), .resp_rdata(bk_resp_rdata), .resp_error(bk_resp_error)
	);

	wire dcache_pending_load     = mem_owner_valid && !mem_owner_is_store && dc_resp_valid;
	wire dcache_same_cycle_load  = dc_req_valid && dc_req_ready && dc_resp_valid && !store_commit_want;
	wire dcache_same_cycle_store = dc_req_valid && dc_req_ready && dc_resp_valid && store_commit_want;

	// A same-cycle cache-hit load must NOT broadcast on the CDB combinationally
	// this same cycle: cdb_valid/cdb_tag feed IQ operand readiness, which feeds
	// issue_idx selection, which feeds dc_req_addr/dc_req_valid, which feeds
	// dc_resp_valid (hit) right back into dcache_same_cycle_load - a genuine
	// zero-delay combinational cycle (confirmed via testcase4 hang: a woken IQ
	// entry can flip issue_idx away from the hitting load, dropping dc_resp_valid,
	// dropping the CDB broadcast, re-waking the original load, repeat forever).
	// Registering the hit for one cycle breaks the loop at the cost of one extra
	// cycle of load-to-use latency on a cache hit.
	reg                 load_complete_valid;
	reg [ROB_TAG_W-1:0] load_complete_tag;
	reg [31:0]          load_complete_data;
	always @(posedge clk) begin
		if (rst) begin
			load_complete_valid <= 1'b0;
		end else begin
			load_complete_valid <= dcache_same_cycle_load;
			if (dcache_same_cycle_load) begin
				load_complete_tag  <= iq_rob_idx[issue_idx];
				load_complete_data <= dc_resp_rdata;
			end
		end
	end

	wire dcache_wants_cdb = dcache_pending_load || load_complete_valid;
	wire [ROB_TAG_W-1:0] dcache_cdb_tag   = dcache_pending_load ? mem_owner_tag : load_complete_tag;
	wire [31:0]          dcache_cdb_value = dcache_pending_load ? dc_resp_rdata : load_complete_data;

	assign cdb_valid = dcache_wants_cdb || buffer_occupied || ex_valid;
	assign cdb_value = dcache_wants_cdb ? dcache_cdb_value : buffer_occupied ? buffer_value : ex_result;
	assign cdb_tag   = dcache_wants_cdb ? dcache_cdb_tag   : buffer_occupied ? buffer_tag   : ex_rob_idx;

	reg        d_src1_ready, d_src2_ready;
	reg [31:0] d_src1_value, d_src2_value;
	reg [ROB_TAG_W-1:0] d_src1_tag, d_src2_tag;

	always @(*) begin
		if (!uses_rs) begin
			d_src1_ready = 1'b1; d_src1_value = 32'b0; d_src1_tag = {ROB_TAG_W{1'b0}};
		end else if (!rat_busy[rs]) begin
			d_src1_ready = 1'b1; d_src1_value = committed_rf[rs]; d_src1_tag = {ROB_TAG_W{1'b0}};
		end else if (cdb_valid && cdb_tag == rat_tag[rs]) begin
			d_src1_ready = 1'b1; d_src1_value = cdb_value; d_src1_tag = rat_tag[rs];
		end else if (rob_ready[rat_tag[rs]]) begin
			d_src1_ready = 1'b1; d_src1_value = rob_value[rat_tag[rs]]; d_src1_tag = rat_tag[rs];
		end else begin
			d_src1_ready = 1'b0; d_src1_value = 32'b0; d_src1_tag = rat_tag[rs];
		end

		if (!uses_rt) begin
			d_src2_ready = 1'b1; d_src2_value = 32'b0; d_src2_tag = {ROB_TAG_W{1'b0}};
		end else if (!rat_busy[rt]) begin
			d_src2_ready = 1'b1; d_src2_value = committed_rf[rt]; d_src2_tag = {ROB_TAG_W{1'b0}};
		end else if (cdb_valid && cdb_tag == rat_tag[rt]) begin
			d_src2_ready = 1'b1; d_src2_value = cdb_value; d_src2_tag = rat_tag[rt];
		end else if (rob_ready[rat_tag[rt]]) begin
			d_src2_ready = 1'b1; d_src2_value = rob_value[rat_tag[rt]]; d_src2_tag = rat_tag[rt];
		end else begin
			d_src2_ready = 1'b0; d_src2_value = 32'b0; d_src2_tag = rat_tag[rt];
		end
	end

	wire branch_needs_src1 = is_jr || is_branch;
	wire branch_needs_src2 = is_branch;
	wire barrier_ready = (!branch_needs_src1 || d_src1_ready) && (!branch_needs_src2 || d_src2_ready);

	wire [31:0] branch_target = pc4 + {{14{immi[15]}}, immi, 2'b00};
	wire [31:0] jump_target   = is_jr ? d_src1_value : {pc4[31:28], immj, 2'b00};
	wire branch_taken = is_branch && (B_NE ? (d_src1_value != d_src2_value) : (d_src1_value == d_src2_value));
	wire actual_taken  = branch_taken || is_j || is_jal || is_jr;
	wire [31:0] actual_target = (is_j || is_jal || is_jr) ? jump_target : branch_target;

	wire [5:0] btb_idx = PC[7:2];
	wire [23:0] btb_tagc = PC[31:8];
	wire btb_hit = (btb_type[btb_idx] != 2'b00) && (btb_tag[btb_idx] == btb_tagc);
	wire [7:0] pht_idx = PC[9:2];
	wire pht_taken = pht[pht_idx][1];
	wire predict_taken = btb_hit && ((btb_type[btb_idx]==2'b10) || pht_taken);
	wire [31:0] predict_target = btb_target[btb_idx];

	wire cf_mispredict = is_cf && barrier_ready && (actual_taken != predict_taken);
	wire [31:0] cf_correct_target = actual_taken ? actual_target : pc4;

	reg iq_has_free;
	reg [IQ_IDX_W-1:0] iq_free_idx;
	integer fi;
	always @(*) begin
		iq_has_free = 1'b0;
		iq_free_idx = {IQ_IDX_W{1'b0}};
		for (fi = 0; fi < IQ_ENTRIES; fi = fi + 1) begin
			if (!iq_has_free && !iq_valid[fi]) begin
				iq_has_free = 1'b1;
				iq_free_idx = fi[IQ_IDX_W-1:0];
			end
		end
	end

	wire dispatch_stall_barrier = is_cf && !barrier_ready;
	wire dispatch_stall_struct  = rob_full || (!is_cf && !iq_has_free);
	wire dispatch_fire = !dispatch_stall_barrier && !dispatch_stall_struct;

	wire dispatch_is_cf_commit = dispatch_fire && is_cf;
	wire dispatch_is_iq_alloc  = dispatch_fire && !is_cf && (writes_dest || is_mem);

	wire [31:0] cf_dest_value = is_jal ? pc4 : 32'b0;

	wire issue_eligible_alu [0:IQ_ENTRIES-1];
	wire issue_eligible_load[0:IQ_ENTRIES-1];
	wire issue_eligible_store[0:IQ_ENTRIES-1];
	wire [31:0] load_tentative_addr[0:IQ_ENTRIES-1];
	wire [1:0]  load_lsq_state[0:IQ_ENTRIES-1];
	wire [31:0] load_fwd_value[0:IQ_ENTRIES-1];

	localparam LSQ_BLOCKED=2'd0, LSQ_CLEAR=2'd1, LSQ_FORWARD=2'd2;

	generate
		for (gi = 0; gi < IQ_ENTRIES; gi = gi + 1) begin : ISSCHK
			assign load_tentative_addr[gi] = iq_eff_src1_value[gi] + iq_imm[gi];

			reg [1:0] lsq_state_r;
			reg [31:0] lsq_fwd_r;
			integer si;
			reg [ROB_TAG_W-1:0] scan_i;
			reg found_block, found_match;
			reg [31:0] match_val;
			reg match_data_ready;
			always @(*) begin
				found_block = 1'b0;
				found_match = 1'b0;
				match_val = 32'b0;
				match_data_ready = 1'b0;
				for (si = 0; si < ROB_ENTRIES; si = si + 1) begin
					scan_i = head + si[ROB_TAG_W-1:0];
					if (age_dist(scan_i) < age_dist(iq_rob_idx[gi])) begin
						if (rob_valid[scan_i] && rob_type[scan_i]==TYPE_STORE) begin
							if (!rob_addr_ready[scan_i]) begin
								found_block = 1'b1;
							end else if (rob_mem_addr[scan_i] == load_tentative_addr[gi]) begin
								found_match = 1'b1;
								match_data_ready = rob_data_ready[scan_i];
								match_val = rob_mem_wdata[scan_i];
							end
						end
					end
				end
				if (found_block) lsq_state_r = LSQ_BLOCKED;
				else if (found_match && match_data_ready) lsq_state_r = LSQ_FORWARD;
				else if (found_match && !match_data_ready) lsq_state_r = LSQ_BLOCKED;
				else lsq_state_r = LSQ_CLEAR;
				lsq_fwd_r = match_val;
			end
			assign load_lsq_state[gi] = lsq_state_r;
			assign load_fwd_value[gi] = lsq_fwd_r;

			assign issue_eligible_alu[gi]   = iq_valid[gi] && iq_type[gi]==TYPE_ALU
			                                && iq_eff_src1_ready[gi] && iq_eff_src2_ready[gi]
			                                && !ex_valid && !buffer_occupied;
			assign issue_eligible_store[gi] = iq_valid[gi] && iq_type[gi]==TYPE_STORE
			                                && iq_eff_src1_ready[gi] && iq_eff_src2_ready[gi];
			assign issue_eligible_load[gi]  = iq_valid[gi] && iq_type[gi]==TYPE_LOAD
			                                && iq_eff_src1_ready[gi]
			                                && (load_lsq_state[gi]==LSQ_CLEAR || load_lsq_state[gi]==LSQ_FORWARD)
			                                && (load_lsq_state[gi]==LSQ_FORWARD ? (!ex_valid && !buffer_occupied)
			                                                                    : (dc_req_ready && !store_commit_want && !buffer_occupied));
		end
	endgenerate

	reg issue_any;
	reg [IQ_IDX_W-1:0] issue_idx;
	reg [1:0] issue_kind;
	reg [ROB_TAG_W-1:0] best_dist;
	integer ii;
	always @(*) begin
		issue_any = 1'b0;
		issue_idx = {IQ_IDX_W{1'b0}};
		issue_kind = TYPE_ALU;
		best_dist = {ROB_TAG_W{1'b1}};
		for (ii = 0; ii < IQ_ENTRIES; ii = ii + 1) begin
			if (issue_eligible_alu[ii] && (!issue_any || age_dist(iq_rob_idx[ii]) < best_dist)) begin
				issue_any = 1'b1; issue_idx = ii[IQ_IDX_W-1:0]; issue_kind = TYPE_ALU;
				best_dist = age_dist(iq_rob_idx[ii]);
			end
			if (issue_eligible_store[ii] && (!issue_any || age_dist(iq_rob_idx[ii]) < best_dist)) begin
				issue_any = 1'b1; issue_idx = ii[IQ_IDX_W-1:0]; issue_kind = TYPE_STORE;
				best_dist = age_dist(iq_rob_idx[ii]);
			end
			if (issue_eligible_load[ii] && (!issue_any || age_dist(iq_rob_idx[ii]) < best_dist)) begin
				issue_any = 1'b1; issue_idx = ii[IQ_IDX_W-1:0]; issue_kind = TYPE_LOAD;
				best_dist = age_dist(iq_rob_idx[ii]);
			end
		end
	end

	wire issue_fire_alu   = issue_any && issue_kind==TYPE_ALU;
	wire issue_fire_store = issue_any && issue_kind==TYPE_STORE;
	wire issue_fire_load  = issue_any && issue_kind==TYPE_LOAD;
	wire issue_fire_load_fwd = issue_fire_load && load_lsq_state[issue_idx]==LSQ_FORWARD;
	wire issue_fire_load_mem = issue_fire_load && load_lsq_state[issue_idx]==LSQ_CLEAR;

	wire store_commit_want = rob_valid[head] && rob_type[head]==TYPE_STORE
	                        && rob_addr_ready[head] && rob_data_ready[head]
	                        && !rob_req_sent[head];

	assign dc_req_valid = store_commit_want || issue_fire_load_mem;
	assign dc_req_write = store_commit_want;
	assign dc_req_addr  = store_commit_want ? rob_mem_addr[head] : load_tentative_addr[issue_idx];
	assign dc_req_wdata = store_commit_want ? rob_mem_wdata[head] : 32'b0;

	wire commit_store_wait = rob_valid[head] && rob_type[head]==TYPE_STORE
	                        && (!rob_addr_ready[head] || !rob_data_ready[head] || !rob_resp_recv[head]);
	wire commit_fire = rob_valid[head] && !commit_store_wait
	                 && (rob_type[head]!=TYPE_STORE || rob_resp_recv[head])
	                 && (rob_type[head]==TYPE_STORE || rob_ready[head]);

	assign halt = commit_fire && rob_halt[head];

	always @(posedge clk) begin
		if (rst) begin
			PC <= 32'b0;
		end else if (dispatch_fire) begin
			if (is_cf) PC <= cf_correct_target;
			else PC <= pc4;
		end
	end

	integer bi;
	always @(posedge clk) begin
		if (rst) begin
			for (bi = 0; bi < 64; bi = bi + 1) btb_type[bi] <= 2'b00;
			for (bi = 0; bi < 256; bi = bi + 1) pht[bi] <= 2'b01;
		end else if (dispatch_fire && is_cf) begin
			if (is_branch) begin
				btb_type[btb_idx] <= 2'b01;
				btb_tag[btb_idx]  <= btb_tagc;
				btb_target[btb_idx] <= branch_target;
				if (branch_taken)
					pht[pht_idx] <= (pht[pht_idx]==2'b11) ? 2'b11 : pht[pht_idx]+1'b1;
				else
					pht[pht_idx] <= (pht[pht_idx]==2'b00) ? 2'b00 : pht[pht_idx]-1'b1;
			end else if (is_j || is_jal) begin
				btb_type[btb_idx] <= 2'b10;
				btb_tag[btb_idx]  <= btb_tagc;
				btb_target[btb_idx] <= jump_target;
			end
		end
	end

	wire [4:0] commit_dest_reg = rob_dest[head];

	integer ri;
	always @(posedge clk) begin
		if (rst) begin
			for (ri = 0; ri < ROB_ENTRIES; ri = ri + 1) begin
				rob_valid[ri] <= 1'b0;
			end
			head <= {ROB_TAG_W{1'b0}};
			tail <= {ROB_TAG_W{1'b0}};
			rob_count <= {(ROB_TAG_W+1){1'b0}};
		end else begin
			if (cdb_valid) begin
				rob_value[cdb_tag] <= cdb_value;
				rob_ready[cdb_tag] <= 1'b1;
			end

			if (issue_fire_store) begin
				rob_mem_addr[iq_rob_idx[issue_idx]]  <= iq_eff_src1_value[issue_idx] + iq_imm[issue_idx];
				rob_mem_wdata[iq_rob_idx[issue_idx]] <= iq_eff_src2_value[issue_idx];
				rob_addr_ready[iq_rob_idx[issue_idx]] <= 1'b1;
				rob_data_ready[iq_rob_idx[issue_idx]] <= 1'b1;
			end

			if (dc_req_valid && dc_req_ready && store_commit_want) begin
				rob_req_sent[head] <= 1'b1;
			end
			// The pending (multi-cycle) completion targets whichever ROB entry
			// was in flight when the request was accepted (mem_owner_tag), not
			// necessarily the current head - today a store is always blocking
			// at head so these coincide, but a future committed-store buffer or
			// multiple-outstanding store would make this distinction load-bearing.
			if (mem_owner_valid && mem_owner_is_store && dc_resp_valid) begin
				rob_resp_recv[mem_owner_tag] <= 1'b1;
			end
			if (dcache_same_cycle_store) begin
				rob_resp_recv[head] <= 1'b1;
			end

			if (commit_fire) begin
				rob_valid[head] <= 1'b0;
				head <= head + 1'b1;
			end

			if (dispatch_is_cf_commit) begin
				rob_valid[tail] <= 1'b1;
				rob_ready[tail] <= 1'b1;
				rob_type[tail]  <= TYPE_ALU;
				rob_dest[tail]  <= is_jal ? 5'd31 : 5'd0;
				rob_value[tail] <= cf_dest_value;
				rob_pc[tail]    <= PC;
				rob_inst[tail]  <= if_inst;
				rob_halt[tail]  <= 1'b0;
				rob_we[tail]    <= is_jal;
				rob_mem_addr[tail]  <= 32'b0;
				rob_mem_wdata[tail] <= 32'b0;
				tail <= tail + 1'b1;
			end else if (dispatch_is_iq_alloc) begin
				rob_valid[tail] <= 1'b1;
				rob_ready[tail] <= 1'b0;
				rob_type[tail]  <= is_lw ? TYPE_LOAD : is_sw ? TYPE_STORE : TYPE_ALU;
				rob_dest[tail]  <= dest_reg;
				rob_value[tail] <= 32'b0;
				rob_pc[tail]    <= PC;
				rob_inst[tail]  <= if_inst;
				rob_halt[tail]  <= is_halt_word;
				rob_we[tail]    <= writes_dest;
				rob_mem_addr[tail]  <= 32'b0;
				rob_mem_wdata[tail] <= 32'b0;
				rob_addr_ready[tail] <= 1'b0;
				rob_data_ready[tail] <= 1'b0;
				rob_req_sent[tail]   <= 1'b0;
				rob_resp_recv[tail]  <= 1'b0;
				tail <= tail + 1'b1;
			end

			case ({dispatch_fire, commit_fire})
				2'b10: rob_count <= rob_count + 1'b1;
				2'b01: rob_count <= rob_count - 1'b1;
				default: rob_count <= rob_count;
			endcase
		end
	end

	integer wi;
	initial $readmemh("initial_reg.mem", committed_rf);
	always @(posedge clk) begin
		if (rst) begin
			for (wi = 0; wi < 32; wi = wi + 1) begin
				rat_busy[wi] <= 1'b0;
			end
		end else begin
			if (commit_fire && rob_type[head]!=TYPE_STORE && commit_dest_reg!=0) begin
				committed_rf[commit_dest_reg] <= rob_value[head];
				if (rat_busy[commit_dest_reg] && rat_tag[commit_dest_reg]==head)
					rat_busy[commit_dest_reg] <= 1'b0;
			end
			if (dispatch_is_cf_commit && (is_jal) ) begin
				rat_busy[5'd31] <= 1'b1;
				rat_tag[5'd31]  <= tail;
			end
			else if (dispatch_is_iq_alloc && writes_dest && dest_reg != 5'd0) begin
				rat_busy[dest_reg] <= 1'b1;
				rat_tag[dest_reg]  <= tail;
			end
		end
	end

	integer qi;
	always @(posedge clk) begin
		if (rst) begin
			for (qi = 0; qi < IQ_ENTRIES; qi = qi + 1) iq_valid[qi] <= 1'b0;
		end else begin
			for (qi = 0; qi < IQ_ENTRIES; qi = qi + 1) begin
				if (cdb_valid && iq_valid[qi]) begin
					if (!iq_src1_ready[qi] && iq_src1_tag[qi]==cdb_tag) begin
						iq_src1_ready[qi] <= 1'b1;
						iq_src1_value[qi] <= cdb_value;
					end
					if (!iq_src2_ready[qi] && iq_src2_tag[qi]==cdb_tag) begin
						iq_src2_ready[qi] <= 1'b1;
						iq_src2_value[qi] <= cdb_value;
					end
				end
			end

			if (issue_fire_alu || issue_fire_store || (issue_fire_load && (issue_fire_load_fwd || (issue_fire_load_mem && dc_req_ready)))) begin
				iq_valid[issue_idx] <= 1'b0;
			end

			if (dispatch_is_iq_alloc) begin
				iq_valid[iq_free_idx]     <= 1'b1;
				iq_rob_idx[iq_free_idx]   <= tail;
				iq_type[iq_free_idx]      <= is_lw ? TYPE_LOAD : is_sw ? TYPE_STORE : TYPE_ALU;
				iq_alu_func[iq_free_idx]  <= is_mem ? `ALU_ADDU : alu_func;
				iq_is_shift[iq_free_idx]  <= is_shift;
				iq_use_imm[iq_free_idx]   <= is_mem ? 1'b1 : use_imm_op2;
				iq_imm[iq_free_idx]       <= imm_for_addr;
				iq_shamt[iq_free_idx]     <= shamt_f;
				iq_src1_ready[iq_free_idx] <= d_src1_ready;
				iq_src1_value[iq_free_idx] <= d_src1_value;
				iq_src1_tag[iq_free_idx]   <= d_src1_tag;
				iq_src2_ready[iq_free_idx] <= d_src2_ready;
				iq_src2_value[iq_free_idx] <= d_src2_value;
				iq_src2_tag[iq_free_idx]   <= d_src2_tag;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			ex_valid <= 1'b0;
			buffer_occupied <= 1'b0;
		end else begin
			if (dcache_wants_cdb && ex_valid) begin
				buffer_occupied <= 1'b1;
				buffer_value <= ex_result;
				buffer_tag   <= ex_rob_idx;
			end else if (!dcache_wants_cdb && buffer_occupied) begin
				buffer_occupied <= 1'b0;
			end

			ex_valid <= 1'b0;
			if (issue_fire_alu) begin
				ex_valid    <= 1'b1;
				ex_rob_idx  <= iq_rob_idx[issue_idx];
				ex_alu_func <= iq_alu_func[issue_idx];
				ex_shamt    <= iq_shamt[issue_idx];
				ex_op1      <= iq_eff_src1_value[issue_idx];
				ex_op2      <= iq_use_imm[issue_idx] ? iq_imm[issue_idx] : iq_eff_src2_value[issue_idx];
			end else if (issue_fire_load_fwd) begin
				ex_valid    <= 1'b1;
				ex_rob_idx  <= iq_rob_idx[issue_idx];
				ex_alu_func <= `ALU_ADDU;
				ex_shamt    <= 5'b0;
				ex_op1      <= load_fwd_value[issue_idx];
				ex_op2      <= 32'b0;
			end
		end
	end

	always @(posedge clk) begin
		if (rst) begin
			mem_owner_valid <= 1'b0;
		end else begin
			if (mem_owner_valid && dc_resp_valid) begin
				mem_owner_valid <= 1'b0;
			end
			if (dc_req_valid && dc_req_ready && !dc_resp_valid) begin
				mem_owner_valid   <= 1'b1;
				mem_owner_is_store<= store_commit_want;
				mem_owner_tag     <= store_commit_want ? head : iq_rob_idx[issue_idx];
			end
		end
	end

endmodule
