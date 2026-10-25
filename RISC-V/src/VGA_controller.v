module VGA_controller(
    //VGA interface
    input clk_xtal,
    input rst,
    output Hsync,
    output Vsync,
    output RED,
    output GREEN,
    output BLUE,
    //CPU interface
    input clk_vram,
    input en_vram,
    input we_vram,
    input[13:0] addr_vram,
    input[15:0] din_vram,
    output[15:0] dout_vram
    );
    
    wire enB_vram;
    reg clk_25mhz;
    wire[13:0] addrB_vram;
    wire[15:0] doutB_vram;

    always@(posedge clk_xtal) begin
        clk_25mhz<=~clk_25mhz;
    end


    Gowin_DPB VRAM(
        .douta(dout_vram),  //output [15:0] douta
        .doutb(doutB_vram), //output [15:0] doutb
        .clka(clk_vram),    //input clka
        .ocea(en_vram),     //input ocea
        .cea(en_vram),      //input cea
        .reseta(rst),       //input reseta
        .wrea(we_vram),     //input wrea
        .clkb(clk_25mhz),        //input clkb
        .oceb(enB_vram),        //input oceb
        .ceb(enB_vram),          //input ceb
        .resetb(rst),       //input resetb
        .wreb(1'b0),        //input wreb
        .ada(addr_vram),          //input [13:0] ada
        .dina(din_vram),        //input [15:0] dina
        .adb(addrB_vram),          //input [13:0] adb
        .dinb(16'b0)         //input [15:0] dinb
    );
    
    signal_gen SIG_GEN(
        //VGA interface
        .clk_xtal(clk_25mhz),
        .rst(rst),
        .Hsync(Hsync),
        .Vsync(Vsync),
        .RED(RED),
        .GREEN(GREEN),
        .BLUE(BLUE),
        //VRAM interface
        .en_vram(enB_vram),
        .addr_vram(addrB_vram),
        .dout_vram(doutB_vram)
    );
    
endmodule
