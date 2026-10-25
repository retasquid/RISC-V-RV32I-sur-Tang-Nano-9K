LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaModule IS
    PORT (
        -- VGA interface
        clk_xtal : IN  std_logic;
        rst      : IN  std_logic;

        hSync    : OUT std_logic;
        vSync    : OUT std_logic;

        red      : OUT std_logic;
        green    : OUT std_logic;
        blue     : OUT std_logic;

        -- CPU interface
        clk_vram  : IN  std_logic;
        cs_vram   : IN  std_logic;
        we_vram   : IN  std_logic;
        rd_vram   : IN  std_logic;
        rdy_vram  : OUT std_logic;
        wenb_vram : IN  std_logic_vector(3 DOWNTO 0);
        addr_vram : IN  std_logic_vector(14 DOWNTO 0);
        din_vram  : IN  std_logic_vector(31 DOWNTO 0);
        dout_vram : OUT std_logic_vector(31 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE vgaModuleV1 OF vgaModule IS

    COMPONENT vgaSignalGen
        PORT (
            clk_xtal  : in  std_logic;                      -- pixel clock
            rst       : in  std_logic;

            Hsync     : out std_logic;
            Vsync     : out std_logic;
            RED       : out std_logic;
            GREEN     : out std_logic;
            BLUE      : out std_logic;

            en_vram   : out std_logic;
            addr_vram : out std_logic_vector(12 downto 0);
            dout_vram : in  std_logic_vector(31 downto 0)
        );
    END COMPONENT;


    COMPONENT vgaMemInterface
    PORT (
            RST       : in  std_logic;
            -- CPU interface
            CLK_VRAM  : in  std_logic;
            CS_VRAM   : in  std_logic;
            WR_VRAM   : in  std_logic;
            RD_VRAM   : in  std_logic;
            RDY_VRAM  : out std_logic;
            WENB_VRAM : in  std_logic_vector(3 DOWNTO 0);
            ADDR_VRAM : in  std_logic_vector(14 DOWNTO 0);
            DIN_VRAM  : in  std_logic_vector(31 DOWNTO 0);
            DOUT_VRAM : out std_logic_vector(31 DOWNTO 0);
            -- VGA interface
            CLK_VGA  : in  std_logic;
            CS_VGA   : in  std_logic;
            ADDR_VGA : in  std_logic_vector(12 DOWNTO 0);
            DOUT_VGA : out std_logic_vector(31 DOWNTO 0)
        );
    END COMPONENT;
    
    SIGNAL cs_vga                   : std_logic;
    SIGNAL dout_vga       : std_logic_vector(31 downto 0);
    SIGNAL addr_vga       : std_logic_vector(12 downto 0);
BEGIN

    u1 : vgaSignalGen
    PORT MAP(
        clk_xtal  => clk_xtal,
        rst       => rst,

        Hsync     => hSync,
        Vsync     => vSync,
        RED       => red,
        GREEN     => green,
        BLUE      => blue,

        en_vram   => cs_vga,
        addr_vram => addr_vga,
        dout_vram => dout_vga
    );


    u2 : vgaMemInterface
    PORT MAP(
        RST       => rst,
        -- CPU interface
        CLK_VRAM  => clk_vram,
        CS_VRAM   => cs_vram,
        WR_VRAM   => we_vram,
        RD_VRAM   => rd_vram,
        RDY_VRAM  => rdy_vram,
        WENB_VRAM => wenb_vram,
        ADDR_VRAM => addr_vram,
        DIN_VRAM  => din_vram,
        DOUT_VRAM => dout_vram,
        -- VGA interface
        CLK_VGA   => clk_xtal,
        CS_VGA    => cs_vga,
        ADDR_VGA  => addr_vga,
        DOUT_VGA  => dout_vga
    );


END ARCHITECTURE;