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

    -- Horloge systeme clk_sys = rPLL 27 * 7 / 6 = 31.5 MHz : coeur, bus,
    -- QSPI (SCLK = clk_sys), peripheriques, port coeur de la VRAM.
    -- A changer avec le rPLL (src/gowin_rpll_sys), le .sdc et CLK_CORE_FREQ
    -- de soft/periph.h.
    CONSTANT CLK_HZ : natural := 31_500_000;

    -- Diviseurs de SCLK, independants du coeur : SCLK = CLK_HZ / DIV.
    -- 1 -> 31.5 MHz (un nibble par cycle) ; 2 -> 15.75 MHz, la donnee lue a
    -- 2 periodes (63 ns) au lieu d'une pour revenir des puces externes.
    CONSTANT FLASH_SCLK_DIV : positive := 2;
    CONSTANT PSRAM_SCLK_DIV : positive := 1;

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
            instRet         : out std_logic;
            --CLOCK & RESET
            clk             : in std_logic;
            rst             : in std_logic
        );
    END COMPONENT;

    COMPONENT qspi_sram
        GENERIC(
            A_WIDTH  : integer := 21;
            CLK_HZ   : natural := 31_500_000;
            SCLK_DIV : positive := 1
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
            CLK_HZ      : natural := 31_500_000;
            SCLK_DIV    : positive := 1
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

    -- rPLL Gowin : 27 MHz * 13 / 7 = 50.14 MHz, clkoutd = /2 = 25.07 MHz
    -- (horloge pixel 640x400@70, -0.4 % par rapport a 25.175 MHz)
    COMPONENT Gowin_rPLL
        PORT (
            clkout  : out std_logic;
            clkoutd : out std_logic;
            clkin   : in  std_logic
        );
    END COMPONENT;

    -- rPLL Gowin : 27 MHz * 7 / 6 = 31.5 MHz (horloge systeme)
    COMPONENT Gowin_rPLL_sys
        PORT (
            clkout  : out std_logic;
            lock    : out std_logic;
            clkin   : in  std_logic
        );
    END COMPONENT;

    SIGNAL dout, din, adr                 : std_logic_vector(31 downto 0);
    SIGNAL wenb                           : std_logic_vector(3 downto 0);
    SIGNAL rdy, we, rd                    : std_logic;
    SIGNAL clk50, clk25                   : std_logic;
    SIGNAL clk_sys, pllLock               : std_logic;
    SIGNAL csRam, csFlash, csIO, csVram   : std_logic;
    SIGNAL red, green, blue               : std_logic;
    SIGNAL instRet, instPulse             : std_logic := '0';

    -- Sorties de chaque esclave, multiplexees vers le coeur (pas de trois etats)
    SIGNAL dinIO, dinFlash, dinRam, dinVram : std_logic_vector(31 downto 0);
    SIGNAL rdyIO, rdyFlash, rdyRam, rdyVram : std_logic;

    -- Reset : POR + bouton rst_n resynchronise
    SIGNAL porCnt                         : unsigned(7 downto 0) := (OTHERS => '0');
    SIGNAL rstN1, rstN2                   : std_logic := '0';
    SIGNAL lock1, lock2                   : std_logic := '0';
    SIGNAL rst                            : std_logic := '1';
BEGIN
    red3 <= red & red & red;
    green3 <= green & green & green;
    blue2 <= blue & blue;

    csVram  <= '1' WHEN adr(31 downto 24)=x"C0" ELSE '0';
    csRam   <= '1' WHEN adr(31 downto 24)=x"80" ELSE '0';
    csFlash <= '1' WHEN adr(31 downto 24)=x"40" ELSE '0';
    csIO    <= '1' WHEN adr(31 downto 24)=x"00" ELSE '0';

    -- Bus de lecture : mux explicite. Zone non mappee : rdy = '1' et din = 0,
    -- le coeur ne se bloque pas.
    WITH adr(31 downto 24) SELECT
    din <= dinIO    WHEN x"00",
           dinFlash WHEN x"40",
           dinRam   WHEN x"80",
           dinVram  WHEN x"C0",
           (OTHERS => '0') WHEN OTHERS;

    WITH adr(31 downto 24) SELECT
    rdy <= rdyIO    WHEN x"00",
           rdyFlash WHEN x"40",
           rdyRam   WHEN x"80",
           rdyVram  WHEN x"C0",
           '1'      WHEN OTHERS;

    -- Sortie de debug (pin 40) : une impulsion d'un cycle clk_sys (32 ns) par
    -- instruction executee. Frequence mesuree = instructions par seconde.
    -- Passe par un registre : pas de glitch sur la broche.
    PROCESS(clk_sys)
    BEGIN
        IF rising_edge(clk_sys) THEN
            instPulse <= instRet;
        END IF;
    END PROCESS;
    clk <= instPulse;

    -- Reset synchrone : actif tant que le rPLL systeme n'est pas verrouille,
    -- puis pendant 255 cycles (les registres partent de leur valeur
    -- initiale), puis tant que rst_n = '0'. rst_n et lock sont asynchrones :
    -- 2 bascules de synchronisation chacun.
    PROCESS(clk_sys)
    BEGIN
        IF rising_edge(clk_sys) THEN
            rstN1 <= rst_n;
            rstN2 <= rstN1;
            lock1 <= pllLock;
            lock2 <= lock1;
            IF lock2 = '0' THEN
                porCnt <= (OTHERS => '0');
                rst    <= '1';
            ELSIF porCnt /= x"FF" THEN
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
    --     clk  => clk_sys,
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
    --     clk  => clk_sys
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
        instRet => instRet,
        clk  => clk_sys,
        rst  => rst
    );

    u5 : qspi_sram
    GENERIC MAP (
        A_WIDTH       => 23,
        CLK_HZ        => CLK_HZ,
        SCLK_DIV      => PSRAM_SCLK_DIV
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
        clk         => clk_sys,
        rst         => rst,

        clkQspiEn   => '1',     -- SCLK = clk_sys / PSRAM_SCLK_DIV (tCEM 8 us respecte)

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
        clk    => clk_sys,
        rst    => rst,
        GPIO0  => out0,
        clk_xtal => clk_sys,    -- baud = BAUD_UART * clk_sys / 2^32
        uart_tx  => uart_tx,
        uart_rx  => uart_rx
    );
    
    u7 : qspi_flash
    GENERIC MAP (
        A_WIDTH     => 22,
        CLK_HZ      => CLK_HZ,
        SCLK_DIV    => FLASH_SCLK_DIV
    )
    PORT MAP (
        dout        => dinFlash,
        adr         => adr(21 downto 0),

        cs          => csFlash,
        rd          => rd,
        wr          => we,
        rdy         => rdyFlash,
        clk         => clk_sys,
        rst         => rst,

        clkQspiEn   => '1',     -- SCLK = clk_sys / FLASH_SCLK_DIV

        flash_CS    => flash_CS,
        flash_CLK   => flash_CLK,
        flash_SIO0  => flash_SIO0,
        flash_SIO1  => flash_SIO1,
        flash_SIO2  => flash_SIO2,
        flash_SIO3  => flash_SIO3
    );

    u8 : vgaModule
    PORT MAP(
        -- VGA interface
        clk_xtal => clk25,
        rst      => rst,
        hSync    => hSync,
        vSync    => vSync,
        red      => red,
        green    => green,
        blue     => blue,
        -- CPU interface
        clk_vram  => clk_sys,
        cs_vram   => csVram,
        we_vram   => we,
        rd_vram   => rd,
        rdy_vram  => rdyVram,
        wenb_vram => wenb,
        addr_vram => adr(14 downto 0),
        din_vram  => dout,
        dout_vram => dinVram
    );

    u9 : Gowin_rPLL
    PORT MAP(
        clkout  => clk50,
        clkoutd => clk25,
        clkin   => clk27
    );

    u10 : Gowin_rPLL_sys
    PORT MAP(
        clkout  => clk_sys,
        lock    => pllLock,
        clkin   => clk27
    );
END ARCHITECTURE;