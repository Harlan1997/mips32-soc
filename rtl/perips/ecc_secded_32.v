// Vendor-neutral SECDED for a 32-bit word.
// code[0] is overall parity; code[1..38] is Hamming(38,32).
module ecc_secded_32 (
    input wire [31:0] data_in,
    input wire [38:0] code_in,
    output wire [38:0] code_out,
    output reg [31:0] data_out,
    output reg correctable_error,
    output reg uncorrectable_error
);
    function automatic [38:0] encode;
        input [31:0] d;
        reg [38:0] c;
        integer p, k, di, parity;
        begin
            c = 39'd0; di = 0;
            for (p = 1; p <= 38; p = p + 1)
                if ((p != 1) && (p != 2) && (p != 4) && (p != 8) && (p != 16) && (p != 32)) begin c[p] = d[di]; di = di + 1; end
            for (k = 0; k < 6; k = k + 1) begin
                parity = 0;
                for (p = 1; p <= 38; p = p + 1)
                    if ((p & (1 << k)) != 0 && p != (1 << k)) parity = parity ^ c[p];
                c[1 << k] = parity;
            end
            c[0] = ^c[38:1]; encode = c;
        end
    endfunction
    assign code_out = encode(data_in);
    integer p, k, syndrome, parity, di;
    reg [38:0] fixed;
    always @* begin
        syndrome = 0;
        for (k = 0; k < 6; k = k + 1) begin
            parity = 0;
            for (p = 1; p <= 38; p = p + 1)
                if ((p & (1 << k)) != 0) parity = parity ^ code_in[p];
            if (parity) syndrome = syndrome | (1 << k);
        end
        parity = ^code_in; fixed = code_in;
        correctable_error = 1'b0; uncorrectable_error = 1'b0;
        if (parity && syndrome != 0) begin if (syndrome <= 38) fixed[syndrome] = ~fixed[syndrome]; correctable_error = 1'b1; end
        else if (parity && syndrome == 0) begin fixed[0] = ~fixed[0]; correctable_error = 1'b1; end
        else if (!parity && syndrome != 0) uncorrectable_error = 1'b1;
        data_out = 32'd0; di = 0;
        for (p = 1; p <= 38; p = p + 1)
            if ((p != 1) && (p != 2) && (p != 4) && (p != 8) && (p != 16) && (p != 32)) begin data_out[di] = fixed[p]; di = di + 1; end
    end
endmodule
