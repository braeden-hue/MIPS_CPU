`timescale 1ns / 1ps

module DCACHE #(
	parameter SETS = 32,
	parameter WAYS = 2,
	parameter WORDS_PER_LINE = 4,
	parameter BYPASS = 1'b0
	) (
	input			clk,
	input			rst,

	input			req_valid,
	output			req_ready,
	input [31:0]	req_addr,
	input			req_write,
	input [31:0]	req_wdata,
	input [3:0]		req_wmask,

	output			resp_valid,
	output [31:0]	resp_rdata,
	output			resp_error,

	output			bk_req_valid,
	input			bk_req_ready,
	output [31:0]	bk_req_addr,
	output			bk_req_write,
	output [31:0]	bk_req_wdata,
	output [3:0]	bk_req_wmask,

	input			bk_resp_valid,
	input [31:0]	bk_resp_rdata,
	input			bk_resp_error
    );

	initial begin
		if (WAYS != 2) begin
			$display("ERROR: DCACHE WAYS=%0d is not supported - the LRU/victim logic is hardcoded for exactly 2 ways", WAYS);
			$finish;
		end
	end

	localparam OFFSET_BITS = $clog2(WORDS_PER_LINE);
	localparam INDEX_BITS  = $clog2(SETS);
	localparam TAG_BITS    = 30 - INDEX_BITS - OFFSET_BITS;

	localparam IDLE = 2'd0, WRITEBACK = 2'd1, FILL = 2'd2;

	reg [31:0] data [0:SETS-1][0:WAYS-1][0:WORDS_PER_LINE-1];
	reg [TAG_BITS-1:0] tag [0:SETS-1][0:WAYS-1];
	reg valid [0:SETS-1][0:WAYS-1];
	reg dirty [0:SETS-1][0:WAYS-1];
	reg lru [0:SETS-1];

	reg [1:0] state;

	reg [INDEX_BITS-1:0] miss_index;
	reg [TAG_BITS-1:0] miss_tag;
	reg [OFFSET_BITS-1:0] miss_offset;
	reg miss_way;
	reg miss_is_write;
	reg [31:0] miss_wdata;
	reg [3:0] miss_wmask;
	reg [OFFSET_BITS-1:0] fill_idx;

	reg [TAG_BITS-1:0] victim_tag_reg;
	reg [31:0] victim_data [0:WORDS_PER_LINE-1];
	reg [OFFSET_BITS-1:0] wb_idx;

	reg bk_req_valid_r;
	reg bk_req_write_r;
	reg [31:0] bk_req_addr_r;
	reg [31:0] bk_req_wdata_r;

	wire [29:0] word_addr = req_addr[31:2];
	wire [INDEX_BITS-1:0] index = word_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
	wire [OFFSET_BITS-1:0] offset = word_addr[OFFSET_BITS-1:0];
	wire [TAG_BITS-1:0] tag_in = word_addr[29:OFFSET_BITS+INDEX_BITS];

	wire hit0 = valid[index][0] && (tag[index][0] == tag_in);
	wire hit1 = valid[index][1] && (tag[index][1] == tag_in);
	wire hit  = hit0 || hit1;

	wire victim_way   = !valid[index][0] ? 1'b0 : !valid[index][1] ? 1'b1 : lru[index];
	wire victim_dirty = valid[index][victim_way] && dirty[index][victim_way];

	wire bk_accept = bk_req_valid_r && bk_req_ready;

	wire access_hit    = (state==IDLE) && req_valid && hit;
	wire fill_complete = (state==FILL) && bk_resp_valid && (fill_idx==WORDS_PER_LINE-1);

	wire cache_req_ready  = (state == IDLE);
	wire cache_resp_valid = access_hit || fill_complete;
	wire [31:0] cache_resp_rdata = (state==IDLE) ? (hit1 ? data[index][1][offset] : data[index][0][offset])
	                      : (state==FILL && fill_idx==miss_offset) ? bk_resp_rdata
	                      : data[miss_index][miss_way][miss_offset];

	assign req_ready   = BYPASS ? bk_req_ready  : cache_req_ready;
	assign resp_valid  = BYPASS ? bk_resp_valid : cache_resp_valid;
	assign resp_rdata  = BYPASS ? bk_resp_rdata : cache_resp_rdata;
	assign resp_error  = BYPASS ? bk_resp_error : 1'b0;

	assign bk_req_valid = BYPASS ? req_valid  : bk_req_valid_r;
	assign bk_req_addr  = BYPASS ? req_addr   : bk_req_addr_r;
	assign bk_req_write = BYPASS ? req_write  : bk_req_write_r;
	assign bk_req_wdata = BYPASS ? req_wdata  : bk_req_wdata_r;
	assign bk_req_wmask = 4'hF;

	function [31:0] merge_bytes;
		input [31:0] old_word;
		input [31:0] new_word;
		input [3:0] wmask;
		begin
			merge_bytes[7:0]   = wmask[0] ? new_word[7:0]   : old_word[7:0];
			merge_bytes[15:8]  = wmask[1] ? new_word[15:8]  : old_word[15:8];
			merge_bytes[23:16] = wmask[2] ? new_word[23:16] : old_word[23:16];
			merge_bytes[31:24] = wmask[3] ? new_word[31:24] : old_word[31:24];
		end
	endfunction

	integer i;
	always @(posedge clk) begin
		if (rst) begin
			state <= IDLE;
			bk_req_valid_r <= 1'b0;
			for (i=0; i<SETS; i=i+1) begin
				valid[i][0] <= 1'b0;
				valid[i][1] <= 1'b0;
				dirty[i][0] <= 1'b0;
				dirty[i][1] <= 1'b0;
				lru[i] <= 1'b0;
			end
		end
		else if (!BYPASS) begin
			case (state)
				IDLE: begin
					if (req_valid) begin
						if (hit) begin
							if (req_write) begin
								if (hit0) data[index][0][offset] <= merge_bytes(data[index][0][offset], req_wdata, req_wmask);
								else      data[index][1][offset] <= merge_bytes(data[index][1][offset], req_wdata, req_wmask);
								if (hit0) dirty[index][0] <= 1'b1;
								else      dirty[index][1] <= 1'b1;
							end
							lru[index] <= hit0;
						end
						else begin
							miss_index    <= index;
							miss_tag      <= tag_in;
							miss_offset   <= offset;
							miss_way      <= victim_way;
							miss_is_write <= req_write;
							miss_wdata    <= req_wdata;
							miss_wmask    <= req_wmask;
							fill_idx      <= {OFFSET_BITS{1'b0}};
							if (victim_dirty) begin
								victim_tag_reg <= tag[index][victim_way];
								for (i=0; i<WORDS_PER_LINE; i=i+1)
									victim_data[i] <= data[index][victim_way][i];
								wb_idx <= {OFFSET_BITS{1'b0}};
								bk_req_valid_r <= 1'b1;
								bk_req_write_r <= 1'b1;
								bk_req_addr_r  <= {tag[index][victim_way], index, {OFFSET_BITS{1'b0}}, 2'b00};
								bk_req_wdata_r <= data[index][victim_way][0];
								state <= WRITEBACK;
							end
							else begin
								bk_req_valid_r <= 1'b1;
								bk_req_write_r <= 1'b0;
								bk_req_addr_r  <= {req_addr[31:OFFSET_BITS+2], {OFFSET_BITS{1'b0}}, 2'b00};
								state <= FILL;
							end
						end
					end
				end

				WRITEBACK: begin
					if (bk_accept) bk_req_valid_r <= 1'b0;
					if (bk_resp_valid) begin
						if (wb_idx == WORDS_PER_LINE-1) begin
							bk_req_valid_r <= 1'b1;
							bk_req_write_r <= 1'b0;
							bk_req_addr_r  <= {miss_tag, miss_index, {OFFSET_BITS{1'b0}}, 2'b00};
							state <= FILL;
						end
						else begin
							wb_idx <= wb_idx + 1'b1;
							bk_req_valid_r <= 1'b1;
							bk_req_write_r <= 1'b1;
							bk_req_addr_r  <= {victim_tag_reg, miss_index, wb_idx + 1'b1, 2'b00};
							bk_req_wdata_r <= victim_data[wb_idx + 1'b1];
							state <= WRITEBACK;
						end
					end
				end

				FILL: begin
					if (bk_accept) bk_req_valid_r <= 1'b0;
					if (bk_resp_valid) begin
						data[miss_index][miss_way][fill_idx] <= (miss_is_write && fill_idx==miss_offset)
						                      ? merge_bytes(bk_resp_rdata, miss_wdata, miss_wmask)
						                      : bk_resp_rdata;
						if (fill_idx == WORDS_PER_LINE-1) begin
							valid[miss_index][miss_way] <= 1'b1;
							tag[miss_index][miss_way]   <= miss_tag;
							dirty[miss_index][miss_way] <= miss_is_write;
							lru[miss_index] <= ~miss_way;
							state <= IDLE;
						end
						else begin
							fill_idx <= fill_idx + 1'b1;
							bk_req_valid_r <= 1'b1;
							bk_req_write_r <= 1'b0;
							bk_req_addr_r  <= {miss_tag, miss_index, fill_idx + 1'b1, 2'b00};
							state <= FILL;
						end
					end
				end
			endcase
		end
	end

endmodule
