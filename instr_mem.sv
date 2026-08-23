`default_nettype none

module instr_mem #(
    IAWIDTH = 32
) (
    input logic [IAWIDTH-1:0] instr_addr,
    input logic clk,
    output logic instr
);

  always_ff @(posedge clk) begin
    // use detamover to get instr from memory
  end

endmodule

`default_nettype wire
