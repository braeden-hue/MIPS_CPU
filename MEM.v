`timescale 1ns / 1ps

module MEM(
	input				clk,
	input				rst,

	input [31:0]		inst_addr,
	output reg [31:0]	inst,

	input				req_valid,
	output				req_ready,
	input [31:0]		req_addr,
	input				req_write,
	input [31:0]		req_wdata,
	input [3:0]			req_wmask,

	output				resp_valid,
	output [31:0]		resp_rdata,
	output				resp_error
    );

	parameter MEM_LATENCY = 5;

	reg [31:0] memory [0:8191];

	initial begin
		$readmemh("initial_mem.mem", memory);
	end

	always @(*) begin
		inst = memory[(inst_addr >> 2)];
	end

	reg			busy;
	reg [31:0]	count;
	reg [31:0]	latched_addr;
	reg			latched_write;
	reg [31:0]	latched_wdata;

	wire accept = req_valid && req_ready;
	wire [31:0] active_count = busy ? count : 32'd1;
	wire completing = (busy || accept) && (active_count == MEM_LATENCY);

	wire [31:0] active_addr  = busy ? latched_addr  : req_addr;
	wire		active_write = busy ? latched_write : req_write;
	wire [31:0] active_wdata = busy ? latched_wdata : req_wdata;

	assign req_ready  = !busy;
	assign resp_valid = completing;
	assign resp_rdata = memory[active_addr >> 2];
	assign resp_error = 1'b0;

	always @(posedge clk) begin
		if (rst) begin
			busy  <= 1'b0;
			count <= 32'b0;
		end
		else begin
			if (completing && active_write)
				memory[active_addr >> 2] <= active_wdata;

			if (completing)
				busy <= 1'b0;
			else if (accept) begin
				busy          <= 1'b1;
				count         <= 32'd2;
				latched_addr  <= req_addr;
				latched_write <= req_write;
				latched_wdata <= req_wdata;
			end
			else if (busy)
				count <= count + 1;
		end
	end

endmodule
