// Minimal hardware scheduler contract for the current RTL/simulation phase.
// A reschedule trigger is serialized as save-current -> select-next ->
// restore-next. Context storage is owned by this block so firmware can use
// the same protocol for timer, IPI, and explicit yield paths.
module cpu_scheduler #(
    parameter integer TASKS = 4
) (
    input wire clk, input wire rst_n,
    input wire enable,
    input wire timer_tick,
    input wire ipi_resched,
    input wire yield_req,
    input wire [TASKS-1:0] active_mask,
    output wire resched_ack,
    output wire scheduler_busy,
    output wire [7:0] current_task,
    output wire switch_valid,
    output wire [7:0] switch_from,
    output wire [7:0] switch_to,
    output wire ctx_save_req,
    output wire [7:0] ctx_save_task,
    input wire ctx_save_done,
    input wire [31:0] ctx_save_pc, input wire [31:0] ctx_save_sp,
    input wire [31:0] ctx_save_status, input wire [7:0] ctx_save_asid,
    input wire [31:0] ctx_save_srsctl,
    input wire [1023:0] ctx_save_gpr,
    input wire [16383:0] ctx_save_srs_gpr,
    input wire [1023:0] ctx_save_fpr, input wire [31:0] ctx_save_fcsr,
    output wire ctx_restore_req,
    output wire [7:0] ctx_restore_task,
    input wire ctx_restore_ack,
    output wire [31:0] ctx_restore_pc, output wire [31:0] ctx_restore_sp,
    output wire [31:0] ctx_restore_status, output wire [7:0] ctx_restore_asid,
    output wire [31:0] ctx_restore_srsctl,
    output wire [1023:0] ctx_restore_gpr,
    output wire [16383:0] ctx_restore_srs_gpr,
    output wire [1023:0] ctx_restore_fpr, output wire [31:0] ctx_restore_fcsr
);
    localparam ST_RUN = 2'd0, ST_SAVE = 2'd1, ST_RESTORE = 2'd2;
    reg [1:0] state;
    reg [7:0] current_r, next_r;
    reg [TASKS-1:0] pending_mask;
    reg [31:0] pc_bank [0:TASKS-1];
    reg [31:0] sp_bank [0:TASKS-1];
    reg [31:0] status_bank [0:TASKS-1];
    reg [7:0] asid_bank [0:TASKS-1];
    reg [31:0] srsctl_bank [0:TASKS-1];
    reg [1023:0] gpr_bank [0:TASKS-1];
    reg [16383:0] srs_gpr_bank [0:TASKS-1];
    reg [1023:0] fpr_bank [0:TASKS-1];
    reg [31:0] fcsr_bank [0:TASKS-1];
    integer k;

    wire trigger = enable && (timer_tick || ipi_resched || yield_req);
    wire [TASKS-1:0] eligible = active_mask & ~(1'b1 << current_r);
    reg [7:0] selected;
    integer offset;
    always @(*) begin
        selected = current_r;
        for (offset = 1; offset <= TASKS; offset = offset + 1)
            if ((selected == current_r) &&
                eligible[(current_r + offset) % TASKS])
                selected = (current_r + offset) % TASKS;
    end

    assign scheduler_busy = (state != ST_RUN);
    assign current_task = current_r;
    assign resched_ack = (state == ST_SAVE) && ctx_save_done;
    assign ctx_save_req = (state == ST_SAVE);
    assign ctx_save_task = current_r;
    assign ctx_restore_req = (state == ST_RESTORE);
    assign ctx_restore_task = next_r;
    assign switch_valid = (state == ST_RESTORE) && ctx_restore_ack;
    assign switch_from = current_r;
    assign switch_to = next_r;
    assign ctx_restore_pc = pc_bank[next_r];
    assign ctx_restore_sp = sp_bank[next_r];
    assign ctx_restore_status = status_bank[next_r];
    assign ctx_restore_asid = asid_bank[next_r];
    assign ctx_restore_srsctl = srsctl_bank[next_r];
    assign ctx_restore_gpr = gpr_bank[next_r];
    assign ctx_restore_srs_gpr = srs_gpr_bank[next_r];
    assign ctx_restore_fpr = fpr_bank[next_r];
    assign ctx_restore_fcsr = fcsr_bank[next_r];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_RUN; current_r <= 0; next_r <= 0; pending_mask <= 0;
            for (k = 0; k < TASKS; k = k + 1) begin
                pc_bank[k] <= 0; sp_bank[k] <= 0; status_bank[k] <= 0; asid_bank[k] <= 0;
                srsctl_bank[k] <= 0;
                gpr_bank[k] <= 0; srs_gpr_bank[k] <= 0;
                fpr_bank[k] <= 0; fcsr_bank[k] <= 0;
            end
        end else begin
            if (trigger && state == ST_RUN) pending_mask <= active_mask;
            case (state)
                ST_RUN: if (trigger && active_mask != 0) begin
                    next_r <= selected;
                    if (selected != current_r) state <= ST_SAVE;
                end
                ST_SAVE: if (ctx_save_done) begin
                    pc_bank[current_r] <= ctx_save_pc;
                    sp_bank[current_r] <= ctx_save_sp;
                    status_bank[current_r] <= ctx_save_status;
                    asid_bank[current_r] <= ctx_save_asid;
                    srsctl_bank[current_r] <= ctx_save_srsctl;
                    gpr_bank[current_r] <= ctx_save_gpr;
                    srs_gpr_bank[current_r] <= ctx_save_srs_gpr;
                    fpr_bank[current_r] <= ctx_save_fpr;
                    fcsr_bank[current_r] <= ctx_save_fcsr;
                    state <= ST_RESTORE;
                end
                ST_RESTORE: if (ctx_restore_ack) begin
                    current_r <= next_r;
                    state <= ST_RUN;
                end
            endcase
        end
    end
endmodule
