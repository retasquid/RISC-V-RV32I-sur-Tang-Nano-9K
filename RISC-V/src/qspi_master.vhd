--------------------------------------------------------------------------------
-- qspi_master.vhd
-- Moteur QSPI generique, une seule horloge (clk) + un enable 'tick'.
--
-- Chaque tick = une demi-periode de SCLK (tick = '1' en permanence -> clk/2).
-- SCLK, CS# et les sorties SIO sortent directement de registres.
-- Mode SPI 0 : SCLK au repos bas,
--   * l'hote change ses sorties sur la phase "front descendant",
--   * la memoire echantillonne au front montant,
--   * l'hote echantillonne les entrees sur la phase "front montant"
--     (donnee emise par la memoire au front descendant precedent).
--
-- Une transaction = suite de phases optionnelles, dans cet ordre :
--   CMD   : 8 bits sur SIO0 (cmd_quad = '0') ou 2 nibbles (cmd_quad = '1')
--   ADDR  : 24 bits en quad (6 coups)
--   MODE  : 8 bits en quad (2 coups)
--   DUMMY : n_dummy coups, bus relache
--   DATA  : n_bytes octets en quad, ecriture (rd_nwr = '0') ou lecture
-- Les octets de donnees sont transmis octet 0 (bits 7..0) en premier.
-- En lecture, seul n_bytes = 4 est supporte : rdata = octet3 & ... & octet0.
--
-- Protocole : start (1 cycle) quand busy = '0'. Les parametres sont lus au
-- cycle du start. done pulse 1 cycle quand CS# est remonte (rdata valide).
-- busy reste a '1' pendant CS# haut minimum (2 ticks, tCPH).
--
-- Flux (burst), pour les memoires statiques seulement (flash, pas la PSRAM a
-- cause de tCEM) : avec hold = '1', CS# reste BAS en fin de lecture, SCLK
-- arrete a l'etat bas (phase P_HOLD, held = '1', busy = '0', done pulse quand
-- meme). Depuis P_HOLD :
--   start + resume = '1' : reprend la phase DATA (lecture de n_bytes octets
--                          aux adresses suivantes), sans commande ni adresse
--   hold_end = '1'       : remonte CS# (P_CSHIGH puis P_IDLE, sans done)
-- Un start sans resume est ignore en P_HOLD : faire hold_end d'abord.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY qspi_master IS
    PORT(
        clk         : in  std_logic;
        rst         : in  std_logic;
        tick        : in  std_logic;
        -- Commande
        start       : in  std_logic;
        has_cmd     : in  std_logic;
        cmd_quad    : in  std_logic;
        cmd         : in  std_logic_vector(7 downto 0);
        has_addr    : in  std_logic;
        addr        : in  std_logic_vector(23 downto 0);
        has_mode    : in  std_logic;
        mode        : in  std_logic_vector(7 downto 0);
        n_dummy     : in  unsigned(3 downto 0);
        n_bytes     : in  unsigned(2 downto 0);
        rd_nwr      : in  std_logic;
        wdata       : in  std_logic_vector(31 downto 0);
        hold        : in  std_logic;
        resume      : in  std_logic;
        hold_end    : in  std_logic;
        held        : out std_logic;
        busy        : out std_logic;
        done        : out std_logic;
        rdata       : out std_logic_vector(31 downto 0);
        -- Pads
        cs_n        : out std_logic;
        sclk        : out std_logic;
        sio_o       : out std_logic_vector(3 downto 0);
        sio_oe      : out std_logic_vector(3 downto 0);
        sio_i       : in  std_logic_vector(3 downto 0)
    );
END ENTITY;

ARCHITECTURE qspi_masterV1 OF qspi_master IS
    TYPE phase_t IS (P_IDLE, P_ARM, P_CMD, P_ADDR, P_MODE, P_DUMMY, P_DATA, P_CSHIGH, P_HOLD);

    SIGNAL phase                    : phase_t := P_IDLE;
    SIGNAL cnt                      : unsigned(4 downto 0) := (OTHERS => '0');
    SIGNAL sr, rx                   : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL quad                     : std_logic := '0';
    SIGNAL cs_r, sclk_r             : std_logic := '1';
    SIGNAL o_r, oe_r                : std_logic_vector(3 downto 0) := "0000";

    -- Parametres latches au start
    SIGNAL l_has_cmd, l_cmd_quad    : std_logic := '0';
    SIGNAL l_has_addr, l_has_mode   : std_logic := '0';
    SIGNAL l_rd_nwr, l_hold         : std_logic := '0';
    SIGNAL l_cmd, l_mode            : std_logic_vector(7 downto 0) := (OTHERS => '0');
    SIGNAL l_addr                   : std_logic_vector(23 downto 0) := (OTHERS => '0');
    SIGNAL l_wdata                  : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL l_n_dummy                : unsigned(3 downto 0) := (OTHERS => '0');
    SIGNAL l_n_bytes                : unsigned(2 downto 0) := (OTHERS => '0');
BEGIN

    cs_n   <= cs_r;
    sclk   <= sclk_r;
    sio_o  <= o_r;
    sio_oe <= oe_r;
    busy   <= '0' WHEN phase = P_IDLE OR phase = P_HOLD ELSE '1';
    held   <= '1' WHEN phase = P_HOLD ELSE '0';

    PROCESS(clk)
        -- Phase suivant 'ph' parmi celles demandees (P_CSHIGH = fin)
        IMPURE FUNCTION next_phase(ph : phase_t) RETURN phase_t IS
        BEGIN
            IF ph = P_ARM AND l_has_cmd = '1' THEN
                RETURN P_CMD;
            ELSIF (ph = P_ARM OR ph = P_CMD) AND l_has_addr = '1' THEN
                RETURN P_ADDR;
            ELSIF (ph = P_ARM OR ph = P_CMD OR ph = P_ADDR) AND l_has_mode = '1' THEN
                RETURN P_MODE;
            ELSIF (ph = P_ARM OR ph = P_CMD OR ph = P_ADDR OR ph = P_MODE) AND l_n_dummy /= 0 THEN
                RETURN P_DUMMY;
            ELSIF ph /= P_DATA AND l_n_bytes /= 0 THEN
                RETURN P_DATA;
            ELSE
                RETURN P_CSHIGH;
            END IF;
        END FUNCTION;

        -- Entree dans une phase, sur un tick "front descendant" (ou P_ARM) :
        -- charge le registre a decalage et pose la premiere unite sur les pads
        PROCEDURE enter(ph : phase_t) IS
            VARIABLE v : std_logic_vector(31 downto 0);
        BEGIN
            phase <= ph;
            CASE ph IS
                WHEN P_CMD =>
                    v := l_cmd & x"000000";
                    IF l_cmd_quad = '1' THEN
                        quad <= '1'; cnt <= to_unsigned(2, 5);
                        o_r  <= v(31 downto 28); oe_r <= "1111";
                    ELSE
                        quad <= '0'; cnt <= to_unsigned(8, 5);
                        o_r  <= "000" & v(31); oe_r <= "0001";
                    END IF;
                    sr <= v;
                WHEN P_ADDR =>
                    v := l_addr & x"00";
                    quad <= '1'; cnt <= to_unsigned(6, 5);
                    o_r  <= v(31 downto 28); oe_r <= "1111";
                    sr   <= v;
                WHEN P_MODE =>
                    v := l_mode & x"000000";
                    quad <= '1'; cnt <= to_unsigned(2, 5);
                    o_r  <= v(31 downto 28); oe_r <= "1111";
                    sr   <= v;
                WHEN P_DUMMY =>
                    cnt  <= '0' & l_n_dummy;
                    oe_r <= "0000";
                WHEN P_DATA =>
                    quad <= '1';
                    cnt  <= '0' & l_n_bytes & '0';   -- 2 coups par octet
                    IF l_rd_nwr = '1' THEN
                        oe_r <= "0000";
                    ELSE
                        v := l_wdata(7 downto 0) & l_wdata(15 downto 8) &
                             l_wdata(23 downto 16) & l_wdata(31 downto 24);
                        o_r  <= v(31 downto 28); oe_r <= "1111";
                        sr   <= v;
                    END IF;
                WHEN P_CSHIGH =>
                    -- Fin de transaction : CS# remonte, sauf en mode flux (hold)
                    oe_r  <= "0000";
                    done  <= '1';
                    rdata <= rx(7 downto 0) & rx(15 downto 8) & rx(23 downto 16) & rx(31 downto 24);
                    IF l_hold = '1' THEN
                        phase <= P_HOLD;
                    ELSE
                        cs_r  <= '1';
                        cnt   <= to_unsigned(2, 5);
                    END IF;
                WHEN OTHERS =>
                    NULL;
            END CASE;
        END PROCEDURE;
    BEGIN
        IF rising_edge(clk) THEN
            done <= '0';
            IF rst = '1' THEN
                phase  <= P_IDLE;
                cs_r   <= '1';
                sclk_r <= '0';
                oe_r   <= "0000";
                o_r    <= "0000";
            ELSE
                CASE phase IS
                    WHEN P_IDLE =>
                        sclk_r <= '0';
                        IF start = '1' THEN
                            l_has_cmd  <= has_cmd;
                            l_cmd_quad <= cmd_quad;
                            l_cmd      <= cmd;
                            l_has_addr <= has_addr;
                            l_addr     <= addr;
                            l_has_mode <= has_mode;
                            l_mode     <= mode;
                            l_n_dummy  <= n_dummy;
                            l_n_bytes  <= n_bytes;
                            l_rd_nwr   <= rd_nwr;
                            l_wdata    <= wdata;
                            l_hold     <= hold;
                            phase      <= P_ARM;
                        END IF;

                    WHEN P_HOLD =>
                        -- CS# bas, SCLK bas : la memoire presente deja le
                        -- nibble suivant (sorti au dernier front descendant)
                        IF hold_end = '1' THEN
                            cs_r  <= '1';
                            cnt   <= to_unsigned(2, 5);
                            phase <= P_CSHIGH;
                        ELSIF start = '1' AND resume = '1' THEN
                            l_n_bytes <= n_bytes;
                            l_rd_nwr  <= '1';
                            l_hold    <= hold;
                            rx        <= (OTHERS => '0');
                            quad      <= '1';
                            cnt       <= '0' & n_bytes & '0';
                            phase     <= P_DATA;
                        END IF;

                    WHEN P_ARM =>
                        -- CS# descend avec SCLK bas ; premier front montant au tick suivant
                        IF tick = '1' THEN
                            cs_r <= '0';
                            rx   <= (OTHERS => '0');
                            enter(next_phase(P_ARM));
                        END IF;

                    WHEN P_CSHIGH =>
                        -- CS# haut minimum (tCPH / tSHSL) avant d'accepter un autre start
                        IF tick = '1' THEN
                            cnt <= cnt - 1;
                            IF cnt = 1 THEN
                                phase <= P_IDLE;
                            END IF;
                        END IF;

                    WHEN OTHERS =>
                        IF tick = '1' THEN
                            IF sclk_r = '0' THEN
                                -- Front montant : la memoire echantillonne, on lit les entrees
                                sclk_r <= '1';
                                cnt    <= cnt - 1;
                                IF phase = P_DATA AND l_rd_nwr = '1' THEN
                                    rx <= rx(27 downto 0) & sio_i;
                                END IF;
                            ELSE
                                -- Front descendant : unite suivante ou phase suivante
                                sclk_r <= '0';
                                IF cnt = 0 THEN
                                    enter(next_phase(phase));
                                ELSIF quad = '1' THEN
                                    sr  <= sr(27 downto 0) & "0000";
                                    o_r <= sr(27 downto 24);
                                ELSE
                                    sr  <= sr(30 downto 0) & '0';
                                    o_r <= "000" & sr(30);
                                END IF;
                            END IF;
                        END IF;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
