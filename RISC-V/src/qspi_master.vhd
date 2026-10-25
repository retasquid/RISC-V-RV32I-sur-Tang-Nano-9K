--------------------------------------------------------------------------------
-- qspi_master.vhd
-- Moteur QSPI generique, une seule horloge (clk) + un enable 'tick'.
--
-- Un coup d'horloge SCLK par tick (tick = '1' en permanence -> SCLK = clk,
-- une unite transmise par cycle ; un tick sur deux -> SCLK = clk/2, et la
-- donnee lue a 2 periodes pour revenir au lieu d'une). Chaque cycle "actif" emet une
-- impulsion : SCLK bas pendant la premiere moitie du cycle, haut pendant la
-- seconde. Mode SPI 0 :
--   * l'hote change ses sorties au front montant de clk (= front descendant
--     de SCLK), la memoire echantillonne au front montant de SCLK, au milieu
--     du cycle : une demi-periode de setup et de hold ;
--   * la memoire sort la donnee suivante au front descendant de SCLK (front
--     montant de clk) ; l'hote l'echantillonne au front montant de clk
--     SUIVANT, une periode entiere plus tard (le temps de sortie de la
--     memoire, ~7 ns, et les delais des pads tiennent largement).
--
-- SCLK = sclk_p XOR sclk_n : sclk_n (front descendant de clk) bascule au
-- milieu d'un cycle actif, sclk_p (front montant) le rattrape a la fin du
-- cycle. Une seule des deux bascules change a la fois : pas de glitch. Une
-- ODDR Gowin ferait la meme chose mais avec 2 cycles de latence, qu'il
-- faudrait ajouter aussi aux donnees.
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
-- cycle du start. done pulse 1 cycle quand la transaction est finie (rdata
-- valide). Apres la derniere impulsion : 1 cycle (dernier echantillon,
-- tCHD >= 20 ns de la PSRAM), puis CS# remonte et reste haut au moins
-- 3 cycles (tCPH >= 50 ns) avant le CS# suivant.
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

ARCHITECTURE qspi_masterV3 OF qspi_master IS
    TYPE phase_t IS (P_IDLE, P_ARM, P_CMD, P_ADDR, P_MODE, P_DUMMY, P_DATA, P_END, P_CSHIGH, P_HOLD, P_RESUME);

    SIGNAL phase                    : phase_t := P_IDLE;
    SIGNAL cnt                      : unsigned(4 downto 0) := (OTHERS => '0');
    SIGNAL sr, rx                   : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL quad                     : std_logic := '0';
    SIGNAL cs_r                     : std_logic := '1';
    SIGNAL o_r, oe_r                : std_logic_vector(3 downto 0) := "0000";
    SIGNAL pulse                    : std_logic := '0';   -- impulsion SCLK dans ce cycle
    SIGNAL smp                      : std_logic := '0';   -- echantillonner sio_i au front suivant
    SIGNAL sclk_p, sclk_n           : std_logic := '0';

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
    sclk   <= sclk_p XOR sclk_n;
    sio_o  <= o_r;
    sio_oe <= oe_r;
    busy   <= '0' WHEN phase = P_IDLE OR phase = P_HOLD ELSE '1';
    held   <= '1' WHEN phase = P_HOLD ELSE '0';

    -- Generation de SCLK : monte au milieu d'un cycle ou pulse = '1',
    -- redescend au front montant de clk suivant
    PROCESS(clk)
    BEGIN
        IF falling_edge(clk) THEN
            IF pulse = '1' THEN
                sclk_n <= NOT sclk_p;
            ELSE
                sclk_n <= sclk_p;
            END IF;
        END IF;
    END PROCESS;

    PROCESS(clk)
        -- Phase suivant 'ph' parmi celles demandees (P_END = fin)
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
                RETURN P_END;
            END IF;
        END FUNCTION;

        -- Entree dans une phase : pose la premiere unite sur les pads et
        -- emet son impulsion dans ce cycle ; cnt = unites restantes ensuite
        PROCEDURE enter(ph : phase_t) IS
            VARIABLE v : std_logic_vector(31 downto 0);
        BEGIN
            phase <= ph;
            pulse <= '1';
            CASE ph IS
                WHEN P_CMD =>
                    v := l_cmd & x"000000";
                    IF l_cmd_quad = '1' THEN
                        quad <= '1'; cnt <= to_unsigned(1, 5);
                        o_r  <= v(31 downto 28); oe_r <= "1111";
                    ELSE
                        quad <= '0'; cnt <= to_unsigned(7, 5);
                        o_r  <= "000" & v(31); oe_r <= "0001";
                    END IF;
                    sr <= v;
                WHEN P_ADDR =>
                    v := l_addr & x"00";
                    quad <= '1'; cnt <= to_unsigned(5, 5);
                    o_r  <= v(31 downto 28); oe_r <= "1111";
                    sr   <= v;
                WHEN P_MODE =>
                    v := l_mode & x"000000";
                    quad <= '1'; cnt <= to_unsigned(1, 5);
                    o_r  <= v(31 downto 28); oe_r <= "1111";
                    sr   <= v;
                WHEN P_DUMMY =>
                    cnt  <= ('0' & l_n_dummy) - 1;
                    oe_r <= "0000";
                WHEN P_DATA =>
                    quad <= '1';
                    cnt  <= ('0' & l_n_bytes & '0') - 1;   -- 2 coups par octet
                    IF l_rd_nwr = '1' THEN
                        oe_r <= "0000";
                        smp  <= '1';
                    ELSE
                        v := l_wdata(7 downto 0) & l_wdata(15 downto 8) &
                             l_wdata(23 downto 16) & l_wdata(31 downto 24);
                        o_r  <= v(31 downto 28); oe_r <= "1111";
                        sr   <= v;
                    END IF;
                WHEN OTHERS =>
                    -- P_END : plus d'impulsion ; le dernier nibble lu est
                    -- echantillonne a ce front
                    pulse <= '0';
                    oe_r  <= "0000";
            END CASE;
        END PROCEDURE;
    BEGIN
        IF rising_edge(clk) THEN
            done  <= '0';
            pulse <= '0';
            smp   <= '0';
            sclk_p <= sclk_n;
            -- Nibble sorti par la memoire au front descendant de SCLK qui
            -- termine l'impulsion du cycle precedent
            IF smp = '1' THEN
                rx <= rx(27 downto 0) & sio_i;
            END IF;
            IF rst = '1' THEN
                phase  <= P_IDLE;
                cs_r   <= '1';
                oe_r   <= "0000";
                o_r    <= "0000";
            ELSE
                CASE phase IS
                    WHEN P_IDLE =>
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
                            phase <= P_CSHIGH;
                        ELSIF start = '1' AND resume = '1' THEN
                            -- Premiere impulsion de donnees des ce cycle si
                            -- tick, sinon au prochain tick (P_RESUME)
                            l_n_bytes <= n_bytes;
                            l_rd_nwr  <= '1';
                            l_hold    <= hold;
                            rx        <= (OTHERS => '0');
                            quad      <= '1';
                            cnt       <= ('0' & n_bytes & '0') - 1;
                            IF tick = '1' THEN
                                pulse <= '1';
                                smp   <= '1';
                                phase <= P_DATA;
                            ELSE
                                phase <= P_RESUME;
                            END IF;
                        END IF;

                    WHEN P_RESUME =>
                        IF tick = '1' THEN
                            pulse <= '1';
                            smp   <= '1';
                            phase <= P_DATA;
                        END IF;

                    WHEN P_ARM =>
                        -- CS# descend au debut du cycle de la premiere
                        -- impulsion : SCLK monte une demi-periode plus tard
                        IF tick = '1' THEN
                            cs_r <= '0';
                            rx   <= (OTHERS => '0');
                            enter(next_phase(P_ARM));
                        END IF;

                    WHEN P_END =>
                        -- Fin de transaction : CS# remonte, sauf en mode flux
                        done  <= '1';
                        rdata <= rx(7 downto 0) & rx(15 downto 8) & rx(23 downto 16) & rx(31 downto 24);
                        IF l_hold = '1' THEN
                            phase <= P_HOLD;
                        ELSE
                            cs_r  <= '1';
                            phase <= P_CSHIGH;
                        END IF;

                    WHEN P_CSHIGH =>
                        -- CS# haut minimum (tCPH / tSHSL) : start accepte au
                        -- cycle suivant, le CS# suivant descend au plus tot
                        -- 3 cycles apres la remontee (95 ns a 31.5 MHz)
                        IF tick = '1' THEN
                            phase <= P_IDLE;
                        END IF;

                    WHEN OTHERS =>
                        -- P_CMD .. P_DATA : une unite par tick
                        IF tick = '1' THEN
                            IF cnt = 0 THEN
                                enter(next_phase(phase));
                            ELSE
                                cnt   <= cnt - 1;
                                pulse <= '1';
                                IF phase = P_DATA AND l_rd_nwr = '1' THEN
                                    smp <= '1';
                                END IF;
                                IF quad = '1' THEN
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
