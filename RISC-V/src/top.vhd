LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY top IS
    PORT(
        out0       : inout std_logic_vector(31 downto 0);
        uart_tx    : out std_logic;
        uart_rx    : in std_logic;
        clk        : out std_logic;
        clk27      : in std_logic;
        --PSRAM
        sram_CS    : out std_logic;
        sram_CLK   : out std_logic;
        sram_SIO0  : inout std_logic;
        sram_SIO1  : inout std_logic;
        sram_SIO2  : inout std_logic;
        sram_SIO3  : inout std_logic;
        --FLASH
        flash_CS   : out std_logic;
        flash_CLK  : out std_logic;
        flash_SIO0 : inout std_logic;
        flash_SIO1 : inout std_logic;
        flash_SIO2 : inout std_logic;
        flash_SIO3 : inout std_logic;
        --VGA
        hSync    : out std_logic;
        vSync    : out std_logic;
        red3      : out std_logic_vector(2 downto 0);
        green3    : out std_logic_vector(2 downto 0);
        blue2     : out std_logic_vector(1 downto 0);
        --CLOCK & RESET
        rst_n      : in std_logic
    );
END ENTITY;

ARCHITECTURE topV1 OF top IS

    COMPONENT RAM
        PORT(
            dout            : out std_logic_vector(31 downto 0);
            din             : in std_logic_vector(31 downto 0);
            adr             : in std_logic_vector(7 downto 0);
            wenb            : in std_logic_vector(3 downto 0);
            rdy             : out std_logic;
            clk, cs, we, rd : in std_logic
        );
    END COMPONENT;

    COMPONENT ROM
        PORT(
            dout            : out std_logic_vector(31 downto 0);
            adr             : in std_logic_vector(9 downto 0);
            rdy             : out std_logic;
            cs, rd          : in std_logic;
            clk             : in std_logic
        );
    END COMPONENT;

    COMPONENT core
        PORT(
            --MEMORY BUS
            dout            : out std_logic_vector(31 downto 0);
            din             : in std_logic_vector(31 downto 0);
            adr             : out std_logic_vector(31 downto 0);
            rdy             : in std_logic;
            we, rd          : out std_logic;
            wenb            : out std_logic_vector(3 downto 0);
            --CLOCK & RESET
            clk             : in std_logic;
            rst             : in std_logic
        );
    END COMPONENT;

    COMPONENT qspi_sram
        GENERIC(
            A_WIDTH : integer := 21
        );
        PORT (
            -- CPU Interface
            dout        : out std_logic_vector(31 downto 0);
            din         : in std_logic_vector(31 downto 0);
            adr         : in std_logic_vector(A_WIDTH-1 downto 0);
            cs          : in std_logic;
            wr          : in std_logic;
            rd          : in std_logic;
            rdy         : out std_logic;
            wenb        : in std_logic_vector(3 downto 0);
            clkEn       : in std_logic;
            clk         : in std_logic; -- Horloge système unique
            rst         : in std_logic;
            -- QSPI Interface
            clkQspiEn   : in std_logic;
            sram_CS     : out std_logic;
            sram_CLK    : out std_logic;
            sram_SIO0   : inout std_logic;
            sram_SIO1   : inout std_logic;
            sram_SIO2   : inout std_logic;
            sram_SIO3   : inout std_logic
        );
    END COMPONENT;

    COMPONENT peripherals
        PORT(
            -- MEMORY INTERFACE
            dout            : out std_logic_vector(31 downto 0);
            din             : in std_logic_vector(31 downto 0);
            adr             : in std_logic_vector(7 downto 0);
            rdy             : out std_logic;
            clk, rst        : in std_logic;
            cs, we, rd      : in std_logic;
            -- IO ports
            GPIO0           : inout std_logic_vector(31 downto 0);
            clk_xtal        : in std_logic;
            uart_tx         : out std_logic;
            uart_rx         : in std_logic
        );
    END COMPONENT;

    COMPONENT qspi_flash
        GENERIC(
            A_WIDTH     : integer := 22;
            INIT_WAIT   : natural := 54000;
            RST_WAIT    : natural := 1080
        );
        PORT(
            -- CPU Interface
            dout        : out std_logic_vector(31 downto 0);
            adr         : in std_logic_vector(A_WIDTH-1 downto 0);
            cs          : in std_logic;
            rd          : in std_logic;
            wr          : in std_logic;
            rdy         : out std_logic;
            clk         : in std_logic;
            rst         : in std_logic;
            -- QSPI Interface
            clkQspiEn   : in std_logic;
            flash_CS    : out std_logic;
            flash_CLK   : out std_logic;
            flash_SIO0  : inout std_logic;
            flash_SIO1  : inout std_logic;
            flash_SIO2  : inout std_logic;
            flash_SIO3  : inout std_logic
        );
    END COMPONENT;

    COMPONENT vgaModule
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
    END COMPONENT;

    SIGNAL dout, din, adr                 : std_logic_vector(31 downto 0);
    SIGNAL wenb                           : std_logic_vector(3 downto 0);
    SIGNAL rdy, we, rd                    : std_logic;
    SIGNAL clkCpu, clkQspi, clk25         : std_logic;
    SIGNAL csRam, csFlash, csIO, csVram   : std_logic;
    SIGNAL red, green, blue               : std_logic;

    -- Sorties de chaque esclave, multiplexees vers le coeur (pas de trois etats)
    SIGNAL dinIO, dinFlash, dinRam        : std_logic_vector(31 downto 0);
    SIGNAL rdyIO, rdyFlash, rdyRam        : std_logic;

    -- Reset : POR + bouton rst_n resynchronise
    SIGNAL porCnt                         : unsigned(7 downto 0) := (OTHERS => '0');
    SIGNAL rstN1, rstN2                   : std_logic := '0';
    SIGNAL rst                            : std_logic := '1';
BEGIN
    red3 <= red & red & red;
    green3 <= green & green & green;
    blue2 <= blue & blue;

    csVram  <= '1' WHEN adr(31 downto 24)=x"C0" ELSE '0';
    csRam   <= '1' WHEN adr(31 downto 24)=x"80" ELSE '0';
    csFlash <= '1' WHEN adr(31 downto 24)=x"40" ELSE '0';
    csIO    <= '1' WHEN adr(31 downto 24)=x"00" ELSE '0';

    -- Bus de lecture : mux explicite. Zone non mappee (dont la VRAM tant que
    -- le VGA est commente) : rdy = '1' et din = 0, le coeur ne se bloque pas.
    WITH adr(31 downto 24) SELECT
    din <= dinIO    WHEN x"00",
           dinFlash WHEN x"40",
           dinRam   WHEN x"80",
           (OTHERS => '0') WHEN OTHERS;

    WITH adr(31 downto 24) SELECT
    rdy <= rdyIO    WHEN x"00",
           rdyFlash WHEN x"40",
           rdyRam   WHEN x"80",
           '1'      WHEN OTHERS;

    -- Sortie de debug (pin 40) : haut pendant chaque requete memoire du coeur
    -- (fetch, load, store). Plus de clock-enable : le coeur tourne sur clk27.
    clk <= rd OR we;

    -- Reset synchrone : actif pendant 255 cycles apres la configuration (les
    -- registres partent de leur valeur initiale), puis tant que rst_n = '0'.
    -- rst_n est asynchrone (bouton) : 2 bascules de synchronisation.
    PROCESS(clk27)
    BEGIN
        IF rising_edge(clk27) THEN
            rstN1 <= rst_n;
            rstN2 <= rstN1;
            IF porCnt /= x"FF" THEN
                porCnt <= porCnt + 1;
                rst    <= '1';
            ELSE
                rst    <= NOT rstN2;
            END IF;
        END IF;
    END PROCESS;

    -- u2 : RAM   (a la place de u5)
    -- PORT MAP(
    --     din  => dout,
    --     dout => dinRam,
    --     adr  => adr(9 downto 2),
    --     wenb => wenb,
    --     rdy  => rdyRam,
    --     clk  => clk27,
    --     cs   => csRam,
    --     we   => we,
    --     rd   => rd
    -- );

    -- ROM interne remplacee par la flash QSPI (u7). Pour revenir a la ROM :
    -- decommenter u3 et commenter u7.
    -- u3 : ROM
    -- PORT MAP(
    --     dout => dinFlash,
    --     adr  => adr(11 downto 2),
    --     rdy  => rdyFlash,
    --     rd   => rd,
    --     cs   => csFlash,
    --     clk  => clk27
    -- );

    u4 : core 
    PORT MAP(
        dout => dout,
        din  => din,
        adr  => adr,
        rdy  => rdy,
        we   => we,
        rd   => rd,
        wenb   => wenb,
        clk  => clk27,
        rst  => rst
    );

    u5 : qspi_sram
    GENERIC MAP (
        A_WIDTH       => 23
    )
    PORT MAP (
        dout        => dinRam,
        din         => dout,
        adr         => adr(22 downto 0),

        cs          => csRam,
        wr          => we,
        rd          => rd,
        rdy         => rdyRam,
        wenb        => wenb,
        clkEn       => '1',     -- inutilise par qspi_sram
        clk         => clk27,
        rst         => rst,

        clkQspiEn   => '1',     -- SCLK = clk27/2 = 13.5 MHz (tCEM 8 us respecte)

        sram_CS     => sram_CS,
        sram_CLK    => sram_CLK,
        sram_SIO0   => sram_SIO0,
        sram_SIO1   => sram_SIO1,
        sram_SIO2   => sram_SIO2,
        sram_SIO3   => sram_SIO3
    );

    u6 : peripherals 
    PORT MAP(
        dout   => dinIO,
        din    => dout,
        adr    => adr(9 downto 2),
        rdy    => rdyIO,
        rd     => rd,
        we     => we,
        cs     => csIO,
        clk    => clk27,
        rst    => rst,
        GPIO0  => out0,
        clk_xtal => clk27,
        uart_tx  => uart_tx,
        uart_rx  => uart_rx
    );
    
    u7 : qspi_flash
    GENERIC MAP (
        A_WIDTH     => 22
    )
    PORT MAP (
        dout        => dinFlash,
        adr         => adr(21 downto 0),

        cs          => csFlash,
        rd          => rd,
        wr          => we,
        rdy         => rdyFlash,
        clk         => clk27,
        rst         => rst,

        clkQspiEn   => '1',     -- SCLK = clk27/2 = 13.5 MHz

        flash_CS    => flash_CS,
        flash_CLK   => flash_CLK,
        flash_SIO0  => flash_SIO0,
        flash_SIO1  => flash_SIO1,
        flash_SIO2  => flash_SIO2,
        flash_SIO3  => flash_SIO3
    );

    -- u8 : vgaModule
    -- PORT MAP(
    --     -- VGA interface
    --     clk_xtal => clk25,
    --     rst      => rst,
    --     hSync    => hSync,
    --     vSync    => vSync,
    --     red      => red,
    --     green    => green,
    --     blue     => blue,
    --     -- CPU interface
    --     clk_vram  => clkCpu,
    --     cs_vram   => csVram,
    --     we_vram   => we,
    --     rd_vram   => rd,
    --     rdy_vram  => rdyVram,     -- a ajouter au mux (x"C0")
    --     wenb_vram => wenb,
    --     addr_vram => adr(14 downto 0),
    --     din_vram  => dout,
    --     dout_vram => dinVram
    -- );
END ARCHITECTURE;