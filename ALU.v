`timescale 1ns / 1ps
`include "GLOBAL.v"

module ALU(
		input [31:0]		operand1,
		input [31:0]		operand2,
		input [4:0]			shamt,
		input [3:0]			funct,
		output reg [31:0]	alu_result
	);
	
	always @(*) begin
		alu_result = 0;
		case (funct)
			`ALU_ADDU:
				alu_result = operand1 + operand2;
			`ALU_AND :
				alu_result = operand1 & operand2;
			`ALU_NOR : 
				alu_result = ~(operand1 | operand2);
			`ALU_OR  :
				alu_result = operand1 | operand2;
			`ALU_SLL :
				alu_result = operand2 << shamt;
			`ALU_SRA :
				alu_result = $signed(operand2) >>> shamt;
			`ALU_SRL :
				alu_result = operand2 >> shamt;
			`ALU_SUBU:
				alu_result = operand1 - operand2;
			`ALU_XOR :
				alu_result = operand1 ^ operand2;
			`ALU_SLT :
				alu_result = ($signed(operand1) < $signed(operand2)) ? 32'd1 : 32'd0;
			`ALU_SLTU:
				alu_result = (operand1 < operand2) ? 32'd1 : 32'd0; 
			`ALU_EQ  :
				alu_result = (operand1 == operand2) ? 32'd1 : 32'd0;
			`ALU_NEQ :
				alu_result = (operand1 != operand2) ? 32'd1 : 32'd0;
			`ALU_LUI :
				alu_result = {operand2[15:0], 16'b0};
		endcase
	end
endmodule
