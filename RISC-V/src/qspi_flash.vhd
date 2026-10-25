--------------------------------------------------------------------------------
-- qspi_flash.vhd
-- Controleur de la flash SPI GigaDevice GD25Q32C (4 MiB, lecture seule) pour
-- le bus du coeur. QE (S9) doit etre a 1 : c'est fait une fois par le flasher.
--
-- Init, relancee a chaque rst :
--   attente INIT_WAIT cycles (tVSL >= 1.8 ms apres la mise sous tension),
--   sortie du mode continu (8 coups a FFh sur SIO0-3 : la flash y est peut-
--   etre restee apres un reset bouton, sinon c'est une commande FFh sans
--   effet), RESET 66h/99h, puis attente RST_WAIT cycles (tRST 30 us).
-- Lecture : EBh (commande sur SIO0), adresse alignee en quad, M = 20h
--   (M5-4 = "10" -> mode continu), 4 dummy, 4 octets -> mot 32 bits.
--   Une fois en mode continu, les lectures suivantes sautent la commande.
-- Flux : apres une lecture, CS# reste bas (qspi_master hold). Si la lecture
--   suivante vise le mot suivant (fetchs sequentiels), on reprend juste la
--   phase donnees : 8 coups au lieu de 20. Sinon, CS# remonte (release) et
--   une nouvelle lecture continue demarre.
-- Ecriture : ignoree, mais acquittee (rdy) pour ne pas bloquer le coeur.
-- Bus : une requete est acceptee quand cs = '1' et rd XOR wr ; rdy et dout
-- sont tenus jusqu'a ce que rd et wr retombent (handshake de uc).
-- clkQspiEn : tick d'une demi-periode SCLK ('1' -> SCLK = clk/2).
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY qspi_flash IS
    GENERIC (
        A_WIDTH   : integer := 22;
        INIT_WAIT : natural := 54000;   -- cycles de clk : 2 ms a 27 MHz
        RST_WAIT  : natural := 1080     -- cycles de clk : 40 us a 27 MHz
    );
    PORT (
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
END ENTITY;

ARCHITECTURE qspi_flashV2 OF qspi_flash IS
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

    TYPE state_t IS (
        S_POR, S_CRMR, S_66, S_99, S_INIT_WAIT, S_RST_WAIT,
        S_IDLE, S_RELEASE, S_ACCESS, S_ACK
    );

    CONSTANT CMD_RST_EN    : std_logic_vector(7 downto 0) := x"66";
    CONSTANT CMD_RST       : std_logic_vector(7 downto 0) := x"99";
    CONSTANT CMD_READ      : std_logic_vector(7 downto 0) := x"EB";
    CONSTANT MODE_CONT     : std_logic_vector(7 downto 0) := x"20";   -- M5-4 = "10"
    CONSTANT MODE_EXIT     : std_logic_vector(7 downto 0) := x"FF";

    SIGNAL state, next_init         : state_t := S_POR;
    SIGNAL wait_cnt                 : natural range 0 to INIT_WAIT + RST_WAIT := 0;
    SIGNAL cont                     : std_logic := '0';   -- flash en mode continu
    SIGNAL dout2                    : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL rdy2                     : std_logic := '0';

    SIGNAL m_start, m_busy, m_done  : std_logic := '0';
    SIGNAL m_hold, m_resume         : std_logic := '0';
    SIGNAL m_release, m_held        : std_logic := '0';
    SIGNAL next_adr                 : std_logic_vector(23 downto 0) := (OTHERS => '0');
    SIGNAL m_has_cmd, m_has_mode    : std_logic := '0';
    SIGNAL m_has_addr, m_rd_nwr     : std_logic := '0';
    SIGNAL m_cmd, m_mode            : std_logic_vector(7 downto 0) := (OTHERS => '0');
    SIGNAL m_addr                   : std_logic_vector(23 downto 0) := (OTHERS => '0');
    SIGNAL m_rdata                  : std_logic_vector(31 downto 0);
    SIGNAL m_n_dummy                : unsigned(3 downto 0) := (OTHERS => '0');
    SIGNAL m_n_bytes                : unsigned(2 downto 0) := (OTHERS => '0');
    SIGNAL sio_o, sio_oe, sio_i     : std_logic_vector(3 downto 0);
    SIGNAL fullAdr                  : std_logic_vector(23 downto 0);
BEGIN

    -- Pas de trois etats : top multiplexe les esclaves selon l'adresse
    dout <= dout2;
    rdy  <= rdy2;

    -- Pads trois etats : registres de sortie/OE dans qspi_master
    flash_SIO0 <= sio_o(0) WHEN sio_oe(0) = '1' ELSE 'Z';
    flash_SIO1 <= sio_o(1) WHEN sio_oe(1) = '1' ELSE 'Z';
    flash_SIO2 <= sio_o(2) WHEN sio_oe(2) = '1' ELSE 'Z';
    flash_SIO3 <= sio_o(3) WHEN sio_oe(3) = '1' ELSE 'Z';
    sio_i      <= flash_SIO3 & flash_SIO2 & flash_SIO1 & flash_SIO0;

    fullAdr <= std_logic_vector(resize(unsigned(adr), 24));

    u1 : qspi_master PORT MAP(
        clk      => clk,
        rst      => rst,
        tick     => clkQspiEn,
        start    => m_start,
        has_cmd  => m_has_cmd,
        cmd_quad => '0',
        cmd      => m_cmd,
        has_addr => m_has_addr,
        addr     => m_addr,
        has_mode => m_has_mode,
        mode     => m_mode,
        n_dummy  => m_n_dummy,
        n_bytes  => m_n_bytes,
        rd_nwr   => m_rd_nwr,
        wdata    => (OTHERS => '0'),
        hold     => m_hold,
        resume   => m_resume,
        hold_end => m_release,
        held     => m_held,
        busy     => m_busy,
        done     => m_done,
        rdata    => m_rdata,
        cs_n     => flash_CS,
        sclk     => flash_CLK,
        sio_o    => sio_o,
        sio_oe   => sio_oe,
        sio_i    => sio_i
    );

    PROCESS(clk)
        -- Lance une commande SPI sans adresse ni donnee, puis passe a 'nxt'
        PROCEDURE simple_cmd(c : std_logic_vector(7 downto 0); nxt : state_t) IS
        BEGIN
            IF m_busy = '0' THEN
                m_start    <= '1';
                m_has_cmd  <= '1';
                m_cmd      <= c;
                m_has_addr <= '0';
                m_has_mode <= '0';
                m_n_dummy  <= (OTHERS => '0');
                m_n_bytes  <= (OTHERS => '0');
                m_hold     <= '0';
                m_resume   <= '0';
                next_init  <= nxt;
                state      <= S_INIT_WAIT;
            END IF;
        END PROCEDURE;
    BEGIN
        IF rising_edge(clk) THEN
            m_start   <= '0';
            m_release <= '0';
            IF rst = '1' THEN
                state    <= S_POR;
                wait_cnt <= 0;
                cont     <= '0';
                rdy2     <= '0';
            ELSE
                CASE state IS
                    WHEN S_POR =>
                        -- tVSL >= 1.8 ms : CS# haut, SCLK bas
                        IF wait_cnt = INIT_WAIT THEN
                            state <= S_CRMR;
                        ELSE
                            wait_cnt <= wait_cnt + 1;
                        END IF;

                    WHEN S_CRMR =>
                        -- Sortie du mode continu : adresse FFFFFFh + M = FFh
                        -- (8 coups, SIO0-3 a 1), CS# remonte avant les dummy
                        IF m_busy = '0' THEN
                            m_start    <= '1';
                            m_has_cmd  <= '0';
                            m_has_addr <= '1';
                            m_addr     <= (OTHERS => '1');
                            m_has_mode <= '1';
                            m_mode     <= MODE_EXIT;
                            m_n_dummy  <= (OTHERS => '0');
                            m_n_bytes  <= (OTHERS => '0');
                            m_hold     <= '0';
                            m_resume   <= '0';
                            next_init  <= S_66;
                            state      <= S_INIT_WAIT;
                        END IF;

                    WHEN S_66 => simple_cmd(CMD_RST_EN, S_99);
                    WHEN S_99 => simple_cmd(CMD_RST,    S_RST_WAIT);

                    WHEN S_INIT_WAIT =>
                        wait_cnt <= 0;
                        IF m_done = '1' THEN
                            state <= next_init;
                        END IF;

                    WHEN S_RST_WAIT =>
                        -- tRST : la flash n'accepte aucune commande
                        IF wait_cnt = RST_WAIT THEN
                            state <= S_IDLE;
                        ELSE
                            wait_cnt <= wait_cnt + 1;
                        END IF;

                    WHEN S_IDLE =>
                        IF cs = '1' AND rd = '1' AND wr = '0' AND m_held = '1' AND
                           fullAdr(23 downto 2) & "00" = next_adr THEN
                            -- Mot suivant du flux : reprise de la phase donnees
                            m_start    <= '1';
                            m_resume   <= '1';
                            m_hold     <= '1';
                            m_n_bytes  <= to_unsigned(4, 3);
                            next_adr   <= std_logic_vector(unsigned(next_adr) + 4);
                            state      <= S_ACCESS;
                        ELSIF cs = '1' AND rd = '1' AND wr = '0' AND m_held = '1' THEN
                            -- Saut : fin du flux, la requete est reprise en S_IDLE
                            m_release  <= '1';
                            state      <= S_RELEASE;
                        ELSIF cs = '1' AND rd = '1' AND wr = '0' AND m_busy = '0' THEN
                            m_start    <= '1';
                            m_resume   <= '0';
                            m_hold     <= '1';
                            next_adr   <= std_logic_vector(unsigned(fullAdr(23 downto 2)) + 1) & "00";
                            m_has_cmd  <= NOT cont;
                            m_cmd      <= CMD_READ;
                            m_has_addr <= '1';
                            m_addr     <= fullAdr(23 downto 2) & "00";
                            m_has_mode <= '1';
                            m_mode     <= MODE_CONT;
                            m_n_dummy  <= to_unsigned(4, 4);
                            m_n_bytes  <= to_unsigned(4, 3);
                            m_rd_nwr   <= '1';
                            cont       <= '1';
                            state      <= S_ACCESS;
                        ELSIF cs = '1' AND wr = '1' AND rd = '0' THEN
                            -- Ecriture en flash : ignoree
                            rdy2  <= '1';
                            state <= S_ACK;
                        END IF;

                    WHEN S_RELEASE =>
                        IF m_held = '0' AND m_busy = '0' AND m_release = '0' THEN
                            state <= S_IDLE;
                        END IF;

                    WHEN S_ACCESS =>
                        IF m_done = '1' THEN
                            dout2 <= m_rdata;
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
