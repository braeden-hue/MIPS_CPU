`timescale 1ns / 1ps
`include "GLOBAL.v"

module CTRL(
	input [5:0] opcode,
	input [5:0] funct,

	output reg 	 	 ALUSrcA,
	output reg [1:0] ALUSrcB, 
	output reg 		 ExtOp, 
	output reg [3:0] alu_func, 

	output reg 		 MemWrite,

	output reg 		 RegWrite,
	output reg [1:0] RegDst,
	output reg [1:0] MemtoReg,

	output reg 		 Branch,
	output reg 		 B_NE,
	output reg 		 Jump,
	output reg 		 JumpLink,
	output reg 		 JumpReg
    );

	always @(*) begin
		ALUSrcA=0; ALUSrcB=2'b00; ExtOp=1; alu_func=`ALU_ADDU; MemWrite=0; RegWrite=0; 
		RegDst=2'b00; MemtoReg=2'b00; Branch=0; B_NE=0; Jump=0; JumpLink=0; JumpReg=0;

		case(opcode) 
			`OP_RTYPE: begin
				RegDst=2'b01;
				RegWrite=1;
				case(funct)
					`FUNCT_JR: begin 
						RegWrite=0; JumpReg=1;
					end 
					`FUNCT_ADDU: alu_func = `ALU_ADDU;
					`FUNCT_SUBU: alu_func = `ALU_SUBU;
					`FUNCT_AND: alu_func = `ALU_AND;
					`FUNCT_OR: alu_func = `ALU_OR;
					`FUNCT_XOR: alu_func = `ALU_XOR;
					`FUNCT_NOR: alu_func = `ALU_NOR;
					`FUNCT_SLL: alu_func = `ALU_SLL;
					`FUNCT_SRL: alu_func = `ALU_SRL;
					`FUNCT_SRA: alu_func = `ALU_SRA;
					`FUNCT_SLT: alu_func = `ALU_SLT;
					`FUNCT_SLTU: alu_func = `ALU_SLTU;
				endcase
			end
			`OP_LW: begin
				ALUSrcB=2'b01; MemtoReg=2'b01; RegWrite=1;
			end
			`OP_SW: begin
				ALUSrcB=2'b01; MemWrite=1;			
			end
			`OP_BEQ: begin
				alu_func=`ALU_EQ; Branch=1;
			end
			`OP_BNE: begin 
				alu_func=`ALU_NEQ; Branch=1; B_NE=1;
			end
			`OP_J: begin
				Jump=1;
			end
			`OP_JAL: begin
				RegDst=2'b10; MemtoReg=2'b10; RegWrite=1;
				Jump=1; JumpLink=1;
			end
			`OP_ADDIU: begin 
				alu_func=`ALU_ADDU;
				RegWrite=1; ALUSrcB=2'b01;
			end
			`OP_SLTI: begin
				alu_func=`ALU_SLT;
				RegWrite=1; ALUSrcB=2'b01;
			end
			`OP_SLTIU: begin
				alu_func=`ALU_SLTU;
				RegWrite=1; ALUSrcB=2'b01;
			end
			`OP_LUI: begin
				alu_func=`ALU_LUI;
				RegWrite=1; ALUSrcB=2'b10; ExtOp=0;
			end
			`OP_ANDI: begin
				alu_func=`ALU_AND;
				RegWrite=1; ALUSrcB=2'b10; ExtOp=0;
			end
			`OP_ORI: begin
				alu_func=`ALU_OR;
				RegWrite=1; ALUSrcB=2'b10; ExtOp=0;
			end
			`OP_XORI: begin
				alu_func=`ALU_XOR;
				RegWrite=1; ALUSrcB=2'b10; ExtOp=0;
			end
		endcase
	end
endmodule
