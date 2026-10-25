--------------------------------------------------------------------------------
-- vgaModule.vhd
-- VGA 640x400 monochrome : VRAM double port (vgaMemInterface) + generateur de
-- signaux (vgaSignalGen). Deux domaines d'horloge, separes par la BRAM :
--   clk_vram (clk27) : cote coeur
--   clk_xtal (~25 MHz, rPLL) : horloge pixel
-- Le reset (domaine clk27) est resynchronise dans le domaine pixel :
-- activation asynchrone, relachement synchrone sur 2 bascules.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaModule IS
    GENERIC (
        MODE_480 : boolean := false   -- 640x480@60 (image centree) ; false : 640x400@70
    );
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

ARCHITECTURE vgaModuleV2 OF vgaModule IS

    COMPONENT vgaSignalGen
        GENERIC (
            MODE_480 : boolean
        );
        PORT (
            clk_xtal  : in  std_logic;
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
            CLK_VRAM  : in  std_logic;
            CS_VRAM   : in  std_logic;
            WR_VRAM   : in  std_logic;
            RD_VRAM   : in  std_logic;
            RDY_VRAM  : out std_logic;
            WENB_VRAM : in  std_logic_vector(3 DOWNTO 0);
            ADDR_VRAM : in  std_logic_vector(14 DOWNTO 0);
            DIN_VRAM  : in  std_logic_vector(31 DOWNTO 0);
            DOUT_VRAM : out std_logic_vector(31 DOWNTO 0);
            CLK_VGA   : in  std_logic;
            RST_VGA   : in  std_logic;
            CS_VGA    : in  std_logic;
            ADDR_VGA  : in  std_logic_vector(12 DOWNTO 0);
            DOUT_VGA  : out std_logic_vector(31 DOWNTO 0)
        );
    END COMPONENT;

    SIGNAL rst_pix1, rst_pix : std_logic := '1';
    SIGNAL cs_vga            : std_logic;
    SIGNAL dout_vga          : std_logic_vector(31 downto 0);
    SIGNAL addr_vga          : std_logic_vector(12 downto 0);
BEGIN

    PROCESS(clk_xtal, rst)
    BEGIN
        IF rst = '1' THEN
            rst_pix1 <= '1';
            rst_pix  <= '1';
        ELSIF rising_edge(clk_xtal) THEN
            rst_pix1 <= '0';
            rst_pix  <= rst_pix1;
        END IF;
    END PROCESS;

    u1 : vgaSignalGen
    GENERIC MAP(
        MODE_480 => MODE_480
    )
    PORT MAP(
        clk_xtal  => clk_xtal,
        rst       => rst_pix,
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
        CLK_VRAM  => clk_vram,
        CS_VRAM   => cs_vram,
        WR_VRAM   => we_vram,
        RD_VRAM   => rd_vram,
        RDY_VRAM  => rdy_vram,
        WENB_VRAM => wenb_vram,
        ADDR_VRAM => addr_vram,
        DIN_VRAM  => din_vram,
        DOUT_VRAM => dout_vram,
        CLK_VGA   => clk_xtal,
        RST_VGA   => rst_pix,
        CS_VGA    => cs_vga,
        ADDR_VGA  => addr_vga,
        DOUT_VGA  => dout_vga
    );

END ARCHITECTURE;
