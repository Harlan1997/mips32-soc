`ifdef VIC_PRIORITY_CHECKER_ENABLE
module vic_priority_checker #(
    parameter NUM_SOURCES = 32
) (
    input logic clk,
    input logic rst_n,
    input logic [NUM_SOURCES-1:0] pending,
    input logic [NUM_SOURCES-1:0] active,
    input logic [3:0] prio [NUM_SOURCES-1:0],
    input logic irq,
    input logic [7:0] vec_id,
    input logic [3:0] vec_prio
);
    integer i;
    reg expected_irq;
    reg [7:0] expected_id;
    reg [3:0] expected_prio;
    reg any_active;
    reg [3:0] running_prio;

    always @(*) begin
        expected_id = 8'hFF;
        expected_prio = 4'h0;
        any_active = 1'b0;
        running_prio = 4'h0;
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (active[i] && (!any_active || (prio[i] > running_prio))) begin
                any_active = 1'b1;
                running_prio = prio[i];
            end
        end
        for (i = 0; i < NUM_SOURCES; i = i + 1) begin
            if (pending[i] &&
                ((expected_id == 8'hFF) || (prio[i] > expected_prio))) begin
                expected_id = i[7:0];
                expected_prio = prio[i];
            end
        end
        expected_irq = (expected_id != 8'hFF) &&
                       (!any_active || (expected_prio > running_prio));
    end

    always @(posedge clk) begin
        if (rst_n) begin
            if (irq !== expected_irq)
                $error("VIC_PRIORITY_CHECKER_FAIL irq mismatch exp=%b got=%b", expected_irq, irq);
            if (vec_id !== expected_id)
                $error("VIC_PRIORITY_CHECKER_FAIL vec_id mismatch exp=%h got=%h", expected_id, vec_id);
            if (vec_prio !== expected_prio)
                $error("VIC_PRIORITY_CHECKER_FAIL vec_prio mismatch exp=%h got=%h", expected_prio, vec_prio);
            if (irq && (vec_id >= NUM_SOURCES || !pending[vec_id]))
                $error("VIC_PRIORITY_CHECKER_FAIL selected source is not pending");
        end
    end
endmodule
`endif
