--------------------------------------------------------------------------------
-- qspi_sram.vhd
-- Controleur de la PSRAM QSPI Lyontek LY68L6400 (8 MiB) pour le bus du coeur.
--
-- Init (datasheet §9), relancee a chaque rst :
--   attente INIT_WAIT = 160 us (>= 150 us, calcule a partir de CLK_HZ),
--   F5h en quad (sortie QPI si la PSRAM y etait restee apres un reset
--   bouton ; tronque et ignore si elle est en SPI), RESET 66h/99h en SPI,
--   puis 35h -> mode QPI.
-- Acces (mode QPI) :
--   lecture  : EBh, adresse alignee, 6 wait, 4 octets -> mot 32 bits
--   ecriture : 38h, adresse octet exacte, 1/2/4 octets de din (non decale,
--              octet 0 = din(7 downto 0)) selon le nombre de bits de wenb
-- Bus : une requete est acceptee quand cs = '1' et rd XOR wr ; rdy et dout
-- sont tenus jusqu'a ce que rd et wr retombent (handshake de uc). Le
-- controleur ne depend pas de clkEn.
-- clkQspiEn ET un diviseur interne (SCLK_DIV) donnent le tick du moteur :
-- un coup de SCLK par tick. SCLK_DIV = 1 et clkQspiEn = '1' -> SCLK = clk.
-- tCEM <= 8 us : une transaction dure moins de 30 cycles.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY qspi_sram IS
    GENERIC (
        A_WIDTH   : integer := 23;
        CLK_HZ    : natural := 31_500_000;  -- frequence de clk
        SCLK_DIV  : positive := 1           -- SCLK = clk / SCLK_DIV
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
        clkEn       : in std_logic;     -- inutilise (conserve pour l'interface)
        clk         : in std_logic;
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
END ENTITY;

ARCHITECTURE qspi_sramV2 OF qspi_sram IS
    COMPONENT qspi_master
        PORT(
            clk, rst, tick  : in  std_logic;
            start           : in  std_logic;
            has_cmd         : in  std_logic;
            cmd_quad        : in  std_logic;
            cmd             : in  std_logic_vector(7 downto 0);
            has_addr        : in  std_logic;
            addr            : in  std_logic_vector(23 downto 0);
            has_mode        : in  std_logic;
            mode            : in  std_logic_vector(7 downto 0);
            n_dummy         : in  unsigned(3 downto 0);
            n_bytes         : in  unsigned(2 downto 0);
            rd_nwr          : in  std_logic;
            wdata           : in  std_logic_vector(31 downto 0);
            hold, resume    : in  std_logic;
            hold_end        : in  std_logic;
            held            : out std_logic;
            busy, done      : out std_logic;
            rdata           : out std_logic_vector(31 downto 0);
            cs_n, sclk      : out std_logic;
            sio_o, sio_oe   : out std_logic_vector(3 downto 0);
            sio_i           : in  std_logic_vector(3 downto 0)
        );
    END COMPONENT;

    CONSTANT INIT_WAIT : natural := CLK_HZ / 6250;    -- cycles de clk : 160 us

    TYPE state_t IS (
        S_POR, S_F5, S_66, S_99, S_35, S_INIT_WAIT,
        S_IDLE, S_ACCESS, S_ACK
    );

    CONSTANT CMD_QPI_EXIT  : std_logic_vector(7 downto 0) := x"F5";
    CONSTANT CMD_RST_EN    : std_logic_vector(7 downto 0) := x"66";
    CONSTANT CMD_RST       : std_logic_vector(7 downto 0) := x"99";
    CONSTANT CMD_QPI_ENTER : std_logic_vector(7 downto 0) := x"35";
    CONSTANT CMD_READ      : std_logic_vector(7 downto 0) := x"EB";
    CONSTANT CMD_WRITE     : std_logic_vector(7 downto 0) := x"38";

    SIGNAL state, next_init         : state_t := S_POR;
    SIGNAL por_cnt                  : natural range 0 to INIT_WAIT := 0;
    SIGNAL dout2                    : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL rdy2                     : std_logic := '0';

    SIGNAL m_start, m_busy, m_done  : std_logic := '0';
    SIGNAL m_cmd_quad, m_has_addr   : std_logic := '0';
    SIGNAL m_rd_nwr                 : std_logic := '0';
    SIGNAL m_cmd                    : std_logic_vector(7 downto 0) := (OTHERS => '0');
    SIGNAL m_addr                   : std_logic_vector(23 downto 0) := (OTHERS => '0');
    SIGNAL m_wdata, m_rdata         : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL m_n_dummy                : unsigned(3 downto 0) := (OTHERS => '0');
    SIGNAL m_n_bytes                : unsigned(2 downto 0) := (OTHERS => '0');
    SIGNAL sio_o, sio_oe, sio_i     : std_logic_vector(3 downto 0);
    SIGNAL div_cnt                  : natural range 0 to SCLK_DIV - 1 := 0;
    SIGNAL m_tick                   : std_logic;
    SIGNAL fullAdr                  : std_logic_vector(23 downto 0);
    SIGNAL nBytes                   : unsigned(2 downto 0);
BEGIN

    -- Pas de trois etats : top multiplexe les esclaves selon l'adresse
    dout <= dout2;
    rdy  <= rdy2;

    -- Pads trois etats : registres de sortie/OE dans qspi_master
    sram_SIO0 <= sio_o(0) WHEN sio_oe(0) = '1' ELSE 'Z';
    sram_SIO1 <= sio_o(1) WHEN sio_oe(1) = '1' ELSE 'Z';
    sram_SIO2 <= sio_o(2) WHEN sio_oe(2) = '1' ELSE 'Z';
    sram_SIO3 <= sio_o(3) WHEN sio_oe(3) = '1' ELSE 'Z';
    sio_i     <= sram_SIO3 & sram_SIO2 & sram_SIO1 & sram_SIO0;

    fullAdr <= std_logic_vector(resize(unsigned(adr), 24));

    -- Nombre d'octets ecrits : la donnee de din n'est pas decalee (core.vhd)
    WITH wenb SELECT
    nBytes <= "001" WHEN "0001" | "0010" | "0100" | "1000",
              "010" WHEN "0011" | "0110" | "1100",
              "100" WHEN OTHERS;

    -- Tick du moteur : un cycle sur SCLK_DIV
    m_tick <= clkQspiEn WHEN div_cnt = 0 ELSE '0';
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF div_cnt = SCLK_DIV - 1 THEN
                div_cnt <= 0;
            ELSE
                div_cnt <= div_cnt + 1;
            END IF;
        END IF;
    END PROCESS;

    u1 : qspi_master PORT MAP(
        clk      => clk,
        rst      => rst,
        tick     => m_tick,
        start    => m_start,
        has_cmd  => '1',
        cmd_quad => m_cmd_quad,
        cmd      => m_cmd,
        has_addr => m_has_addr,
        addr     => m_addr,
        has_mode => '0',
        mode     => x"00",
        n_dummy  => m_n_dummy,
        n_bytes  => m_n_bytes,
        rd_nwr   => m_rd_nwr,
        wdata    => m_wdata,
        hold     => '0',          -- pas de flux : tCEM <= 8 us
        resume   => '0',
        hold_end => '0',
        held     => OPEN,
        busy     => m_busy,
        done     => m_done,
        rdata    => m_rdata,
        cs_n     => sram_CS,
        sclk     => sram_CLK,
        sio_o    => sio_o,
        sio_oe   => sio_oe,
        sio_i    => sio_i
    );

    PROCESS(clk)
        -- Lance une commande sans adresse ni donnee, puis passe a 'nxt'
        PROCEDURE simple_cmd(c : std_logic_vector(7 downto 0); quad : std_logic; nxt : state_t) IS
        BEGIN
            IF m_busy = '0' THEN
                m_start    <= '1';
                m_cmd      <= c;
                m_cmd_quad <= quad;
                m_has_addr <= '0';
                m_n_dummy  <= (OTHERS => '0');
                m_n_bytes  <= (OTHERS => '0');
                next_init  <= nxt;
                state      <= S_INIT_WAIT;
            END IF;
        END PROCEDURE;
    BEGIN
        IF rising_edge(clk) THEN
            m_start <= '0';
            IF rst = '1' THEN
                state   <= S_POR;
                por_cnt <= 0;
                rdy2    <= '0';
            ELSE
                CASE state IS
                    WHEN S_POR =>
                        -- tPU >= 150 us : CE# haut, SCLK bas
                        IF por_cnt = INIT_WAIT THEN
                            state <= S_F5;
                        ELSE
                            por_cnt <= por_cnt + 1;
                        END IF;

                    WHEN S_F5 => simple_cmd(CMD_QPI_EXIT,  '1', S_66);
                    WHEN S_66 => simple_cmd(CMD_RST_EN,    '0', S_99);
                    WHEN S_99 => simple_cmd(CMD_RST,       '0', S_35);
                    WHEN S_35 => simple_cmd(CMD_QPI_ENTER, '0', S_IDLE);

                    WHEN S_INIT_WAIT =>
                        IF m_done = '1' THEN
                            state <= next_init;
                        END IF;

                    WHEN S_IDLE =>
                        IF cs = '1' AND (rd XOR wr) = '1' AND m_busy = '0' THEN
                            m_start    <= '1';
                            m_cmd_quad <= '1';
                            m_has_addr <= '1';
                            m_wdata    <= din;
                            IF rd = '1' THEN
                                m_cmd     <= CMD_READ;
                                m_addr    <= fullAdr(23 downto 2) & "00";
                                m_n_dummy <= to_unsigned(6, 4);
                                m_n_bytes <= to_unsigned(4, 3);
                                m_rd_nwr  <= '1';
                            ELSE
                                m_cmd     <= CMD_WRITE;
                                m_addr    <= fullAdr;
                                m_n_dummy <= (OTHERS => '0');
                                m_n_bytes <= nBytes;
                                m_rd_nwr  <= '0';
                            END IF;
                            state <= S_ACCESS;
                        END IF;

                    WHEN S_ACCESS =>
                        IF m_done = '1' THEN
                            IF m_rd_nwr = '1' THEN
                                dout2 <= m_rdata;
                            END IF;
                            rdy2  <= '1';
                            state <= S_ACK;
                        END IF;

                    WHEN S_ACK =>
                        -- rdy tenu jusqu'a ce que le coeur relache rd/wr
                        IF rd = '0' AND wr = '0' THEN
                            rdy2  <= '0';
                            state <= S_IDLE;
                        END IF;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
