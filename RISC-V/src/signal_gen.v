module signal_gen(
    input  wire        clk_xtal,   // pixel clock
    input  wire        rst,

    // VGA
    output wire        Hsync,
    output wire        Vsync,
    output reg         RED,
    output reg         GREEN,
    output reg         BLUE,

    // VRAM
    output wire        en_vram,
    output reg [13:0]  addr_vram,
    input  wire [15:0] dout_vram
);

    // =========================
    // TIMINGS VGA 640x400@70Hz
    // =========================
    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = 800;

    localparam V_VISIBLE = 400;
    localparam V_FRONT   = 12;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 35;
    localparam V_TOTAL   = 449;

    // =========================
    // Compteurs
    // =========================
    reg [9:0] h_cnt;
    reg [8:0] v_cnt;

    wire end_of_line  = (h_cnt == H_TOTAL-1);
    wire end_of_frame = (v_cnt == V_TOTAL-1);

    // =========================
    // H/V counters
    // =========================
    always @(posedge clk_xtal or posedge rst) begin
        if (rst) begin
            h_cnt <= 10'b0;
            v_cnt <= 9'b0;
        end else begin
            if (end_of_line) begin
                h_cnt <= 10'b0;
                v_cnt <= end_of_frame ? 9'b0 : v_cnt + 9'b1;
            end else begin
                h_cnt <= h_cnt + 10'b1;
            end
        end
    end

    // =========================
    // Visible zones
    // =========================
    wire h_visible = (h_cnt < H_VISIBLE);
    wire v_visible = (v_cnt < V_VISIBLE);
    wire pixel_en  = h_visible && v_visible;

    // =========================
    // Syncs (active low)
    // =========================
    assign Hsync = ~((h_cnt >= H_VISIBLE + H_FRONT) &&
                     (h_cnt <  H_VISIBLE + H_FRONT + H_SYNC));

    assign Vsync = ~((v_cnt >= V_VISIBLE + V_FRONT) &&
                     (v_cnt <  V_VISIBLE + V_FRONT + V_SYNC));

    // =========================
    // VRAM addressing
    // =========================
    assign en_vram = pixel_en;

    reg [3:0] bit_cnt;
    reg [15:0] shift_reg;

    wire new_frame = (h_cnt == 10'b0 && v_cnt == 9'b0);

    always @(posedge clk_xtal or posedge rst) begin
        if (rst) begin
            addr_vram <= 14'b0;
            bit_cnt   <= 4'd15;
            shift_reg <= 16'b0;
        end else begin
            if (new_frame) begin
                addr_vram <= 14'b0;
                bit_cnt   <= 4'b0;
            end else if (pixel_en) begin
                if (bit_cnt == 4'b0) begin
                    shift_reg <= dout_vram;
                    bit_cnt   <= 4'd15;
                end else begin
                    bit_cnt <= bit_cnt - 4'b1;
                end

                if (bit_cnt == 4'b0)
                    addr_vram <= addr_vram + 14'b1;
            end
        end
    end

    // =========================
    // Pixel pipeline (1 cycle)
    // =========================
    reg pixel;
    reg pixel_en_d;

    always @(posedge clk_xtal) begin
        pixel      <= shift_reg[bit_cnt];
        pixel_en_d <= pixel_en;
    end

    // =========================
    // RGB output (ALIGNÉ)
    // =========================
    always @(posedge clk_xtal) begin
        if (pixel_en_d) begin
            RED   <= pixel;
            GREEN <= pixel;
            BLUE  <= pixel;
        end else begin
            RED   <= 1'b0;
            GREEN <= 1'b0;
            BLUE  <= 1'b0;
        end
    end

endmodule
