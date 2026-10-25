--------------------------------------------------------------------------------
-- vgaModule.vhd
-- VGA 320x200 en 16 niveaux de gris, agrandi x2 : VRAM double port
-- (vgaMemInterface) + generateur de signaux (vgaSignalGen) + palette vers les
-- sorties red3 / green3 / blue2. Deux domaines d'horloge, separes par la BRAM :
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

        red      : OUT std_logic_vector(2 DOWNTO 0);
        green    : OUT std_logic_vector(2 DOWNTO 0);
        blue     : OUT std_logic_vector(1 DOWNTO 0);

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
            GRAY      : out std_logic_vector(3 downto 0);
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
    SIGNAL gray              : std_logic_vector(3 downto 0);

    -- Palette : gris 4 bits -> R(3 bits) G(3 bits) B(2 bits). Un gris exact
    -- demande R = G = B, ce que le bleu sur 2 bits ne permet pas : chaque
    -- niveau est la combinaison dont la luminance (0,299 R + 0,587 G +
    -- 0,114 B) est la plus proche de n/15 avec le moins de teinte. Les 16
    -- luminances sont strictement croissantes ; noir et blanc sont exacts.
    TYPE pal_t IS ARRAY (0 TO 15) OF std_logic_vector(7 DOWNTO 0);   -- R & G & B
    CONSTANT PALETTE : pal_t := (
        "000" & "000" & "00",   --  0
        "000" & "001" & "00",   --  1
        "001" & "001" & "00",   --  2
        "010" & "001" & "01",   --  3
        "010" & "010" & "01",   --  4
        "011" & "010" & "01",   --  5
        "011" & "011" & "01",   --  6
        "100" & "011" & "01",   --  7
        "011" & "100" & "10",   --  8
        "100" & "100" & "10",   --  9
        "100" & "101" & "10",   -- 10
        "101" & "101" & "10",   -- 11
        "101" & "110" & "10",   -- 12
        "110" & "110" & "11",   -- 13
        "111" & "110" & "11",   -- 14
        "111" & "111" & "11"    -- 15
    );
    SIGNAL rgb               : std_logic_vector(7 DOWNTO 0) := (OTHERS => '0');
    SIGNAL hs_g, vs_g        : std_logic;
    -- Synchros initialisees a l'etat INACTIF (pas de fausse impulsion) :
    -- Hsync active basse ; Vsync active basse en 640x480, haute en 640x400
    FUNCTION vs_idle(c : boolean) RETURN std_logic IS
    BEGIN
        IF c THEN RETURN '1'; ELSE RETURN '0'; END IF;
    END FUNCTION;
    SIGNAL hs_r              : std_logic := '1';
    SIGNAL vs_r              : std_logic := vs_idle(MODE_480);
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
        Hsync     => hs_g,
        Vsync     => vs_g,
        GRAY      => gray,
        en_vram   => cs_vga,
        addr_vram => addr_vga,
        dout_vram => dout_vga
    );

    -- Palette registree (etage 3) : toutes les broches VGA sortent d'une
    -- bascule ; les synchros sont retardees d'autant que les couleurs
    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            rgb  <= PALETTE(to_integer(unsigned(gray)));
            hs_r <= hs_g;
            vs_r <= vs_g;
        END IF;
    END PROCESS;
    hSync <= hs_r;
    vSync <= vs_r;
    red   <= rgb(7 DOWNTO 5);
    green <= rgb(4 DOWNTO 2);
    blue  <= rgb(1 DOWNTO 0);

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
