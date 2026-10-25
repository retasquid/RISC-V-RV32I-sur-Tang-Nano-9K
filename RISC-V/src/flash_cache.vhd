--------------------------------------------------------------------------------
-- flash_cache.vhd
-- Cache d'instructions/constantes pour la flash : correspondance directe,
-- 8 KiB, 256 lignes de 32 octets (8 mots). Memes ports que qspi_flash, qu'il
-- instancie : remplace qspi_flash dans top sans autre changement.
--
-- Decoupage de l'adresse flash (22 bits) :
--   tag = adr(21:13) (9 bits) | index = adr(12:5) (ligne) | mot = adr(4:2)
-- Memoires (BSRAM inferees, 1 port d'ecriture + 1 port de lecture) :
--   data_ram : 2048 x 32 bits, adresse = adr(12:2)
--   tag_ram  : 256 x 17 bits = valides(8, un bit par mot) & tag(9)
--
-- Hit en 2 cycles : les deux RAM lisent l'adresse du bus a chaque front ; au
-- front suivant (rd deja a '1' au front precedent, donc meme adresse),
-- rdy = tag egal ET mot valide, en combinatoire, avec le mot lu sur dout.
--
-- Defaut : le remplissage commence au mot demande (le coeur repart des que
-- ce mot est ecrit) et continue jusqu'a la fin de la ligne, en lisant
-- qspi_flash mot par mot : les mots suivants arrivent en flux (8 coups de
-- SCLK), et la ligne suivante aussi si le code est sequentiel. Il s'arrete :
--   * en fin de ligne ou sur un mot deja valide ;
--   * quand le coeur attend un autre mot que ceux qui restent a venir dans
--     cette ligne (saut) : le defaut suivant est traite tout de suite.
-- Les mots avant le mot de depart restent invalides : un acces ulterieur fait
-- un defaut qui ne relit que ce qui manque. Pendant un remplissage, les hits
-- sur les autres lignes sont servis normalement.
--
-- Une nouvelle ligne repart de valides = 0 (f_val) : seuls les mots relus
-- deviennent valides, chaque donnee etant ecrite au meme front que son bit
-- de validite. Le tag est aussi invalide des l'allocation (precaution). Lecture et ecriture a la meme adresse au
-- meme front : la valeur lue est indefinie dans une BSRAM ; aucune
-- consultation n'est donc faite pendant une ecriture de tag ni au cycle qui
-- suit (t_we, guard).
--
-- Au reset, les 256 tags sont effaces (256 cycles, pendant l'init flash).
-- Ecritures en flash : ignorees mais acquittees, comme qspi_flash.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY flash_cache IS
    GENERIC (
        A_WIDTH   : integer := 22;          -- doit valoir 22 (4 MiB)
        CLK_HZ    : natural := 31_500_000;  -- frequence de clk
        SCLK_DIV  : positive := 1           -- SCLK = clk / SCLK_DIV
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

ARCHITECTURE flash_cacheV1 OF flash_cache IS
    COMPONENT qspi_flash
        GENERIC (
            A_WIDTH   : integer;
            CLK_HZ    : natural;
            SCLK_DIV  : positive
        );
        PORT (
            dout        : out std_logic_vector(31 downto 0);
            adr         : in std_logic_vector(A_WIDTH-1 downto 0);
            cs          : in std_logic;
            rd          : in std_logic;
            wr          : in std_logic;
            rdy         : out std_logic;
            clk         : in std_logic;
            rst         : in std_logic;
            clkQspiEn   : in std_logic;
            flash_CS    : out std_logic;
            flash_CLK   : out std_logic;
            flash_SIO0  : inout std_logic;
            flash_SIO1  : inout std_logic;
            flash_SIO2  : inout std_logic;
            flash_SIO3  : inout std_logic
        );
    END COMPONENT;

    TYPE data_t IS ARRAY(0 TO 2047) OF std_logic_vector(31 downto 0);
    TYPE tag_t  IS ARRAY(0 TO 255)  OF std_logic_vector(16 downto 0);
    SIGNAL data_ram : data_t;
    SIGNAL tag_ram  : tag_t;
    ATTRIBUTE syn_ramstyle : string;
    ATTRIBUTE syn_ramstyle OF data_ram : SIGNAL IS "block_ram";
    ATTRIBUTE syn_ramstyle OF tag_ram  : SIGNAL IS "block_ram";

    TYPE state_t IS (S_CLEAR, S_IDLE, S_FILL, S_NEXT);
    SIGNAL state                    : state_t := S_CLEAR;
    SIGNAL clr_idx                  : unsigned(7 downto 0) := (OTHERS => '0');

    -- Ports d'ecriture des RAM
    SIGNAL d_we, t_we               : std_logic := '0';
    SIGNAL d_wa                     : unsigned(10 downto 0) := (OTHERS => '0');
    SIGNAL t_wa                     : unsigned(7 downto 0) := (OTHERS => '0');
    SIGNAL d_wd                     : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL t_wd                     : std_logic_vector(16 downto 0) := (OTHERS => '0');
    -- Ports de lecture (adresse du bus, registree dans la BSRAM)
    SIGNAL d_q                      : std_logic_vector(31 downto 0);
    SIGNAL t_q                      : std_logic_vector(16 downto 0);

    SIGNAL rd_q, guard, ready       : std_logic := '0';
    SIGNAL req_tag                  : std_logic_vector(8 downto 0);
    SIGNAL req_idx                  : unsigned(7 downto 0);
    SIGNAL req_w                    : unsigned(2 downto 0);
    SIGNAL lookup, tag_ok, word_ok  : std_logic;
    SIGNAL hit, miss                : std_logic;
    SIGNAL wack                     : std_logic := '0';

    -- Remplissage en cours
    SIGNAL f_tag                    : std_logic_vector(8 downto 0) := (OTHERS => '0');
    SIGNAL f_idx                    : unsigned(7 downto 0) := (OTHERS => '0');
    SIGNAL f_w                      : unsigned(2 downto 0) := (OTHERS => '0');
    SIGNAL f_val                    : std_logic_vector(7 downto 0) := (OTHERS => '0');

    -- Bus vers qspi_flash
    SIGNAL q_rd, q_rdy              : std_logic := '0';
    SIGNAL q_adr                    : std_logic_vector(21 downto 0);
    SIGNAL q_dout                   : std_logic_vector(31 downto 0);
BEGIN

    req_tag <= adr(21 downto 13);
    req_idx <= unsigned(adr(12 downto 5));
    req_w   <= unsigned(adr(4 downto 2));

    -- Lecture valide : meme requete depuis le front precedent (le coeur tient
    -- adr tant que rd = '1'), tags effaces, et aucune ecriture de tag en
    -- cours (t_we : la valeur lue est encore l'ancienne) ni au front
    -- precedent (guard : lecture et ecriture simultanees, valeur indefinie)
    lookup  <= cs AND rd AND rd_q AND ready AND NOT guard AND NOT t_we;
    tag_ok  <= '1' WHEN t_q(8 downto 0) = req_tag ELSE '0';
    word_ok <= t_q(9 + to_integer(req_w));
    hit     <= lookup AND tag_ok AND word_ok;
    miss    <= lookup AND NOT (tag_ok AND word_ok);

    dout <= d_q;
    rdy  <= hit OR wack;

    -- RAM : un port d'ecriture (remplissage), un port de lecture (coeur)
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF d_we = '1' THEN
                data_ram(to_integer(d_wa)) <= d_wd;
            END IF;
            d_q <= data_ram(to_integer(unsigned(adr(12 downto 2))));
        END IF;
    END PROCESS;

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF t_we = '1' THEN
                tag_ram(to_integer(t_wa)) <= t_wd;
            END IF;
            t_q <= tag_ram(to_integer(unsigned(adr(12 downto 5))));
        END IF;
    END PROCESS;

    q_adr <= f_tag & std_logic_vector(f_idx) & std_logic_vector(f_w) & "00";

    u1 : qspi_flash
    GENERIC MAP (
        A_WIDTH  => 22,
        CLK_HZ   => CLK_HZ,
        SCLK_DIV => SCLK_DIV
    )
    PORT MAP (
        dout       => q_dout,
        adr        => q_adr,
        cs         => '1',
        rd         => q_rd,
        wr         => '0',
        rdy        => q_rdy,
        clk        => clk,
        rst        => rst,
        clkQspiEn  => clkQspiEn,
        flash_CS   => flash_CS,
        flash_CLK  => flash_CLK,
        flash_SIO0 => flash_SIO0,
        flash_SIO1 => flash_SIO1,
        flash_SIO2 => flash_SIO2,
        flash_SIO3 => flash_SIO3
    );

    PROCESS(clk)
        VARIABLE nv : std_logic_vector(7 downto 0);
    BEGIN
        IF rising_edge(clk) THEN
            rd_q  <= rd;
            d_we  <= '0';
            t_we  <= '0';
            guard <= t_we;

            -- Ecriture en flash : acquittee une fois, rdy tenu jusqu'a wr = '0'
            IF cs = '1' AND wr = '1' AND rd = '0' THEN
                wack <= '1';
            ELSE
                wack <= '0';
            END IF;

            IF rst = '1' THEN
                state   <= S_CLEAR;
                clr_idx <= (OTHERS => '0');
                ready   <= '0';
                q_rd    <= '0';
                wack    <= '0';
            ELSE
                CASE state IS
                    WHEN S_CLEAR =>
                        -- Effacement des tags (valides = 0)
                        t_we    <= '1';
                        t_wa    <= clr_idx;
                        t_wd    <= (OTHERS => '0');
                        clr_idx <= clr_idx + 1;
                        IF clr_idx = 255 THEN
                            ready <= '1';
                            state <= S_IDLE;
                        END IF;

                    WHEN S_IDLE =>
                        IF miss = '1' THEN
                            -- Nouvelle ligne : tag ecrit avec valides = 0 ;
                            -- meme ligne : on garde les mots deja valides
                            f_tag <= req_tag;
                            f_idx <= req_idx;
                            f_w   <= req_w;
                            IF tag_ok = '1' THEN
                                f_val <= t_q(16 downto 9);
                            ELSE
                                f_val <= (OTHERS => '0');
                                t_we  <= '1';
                                t_wa  <= req_idx;
                                t_wd  <= (OTHERS => '0');
                                t_wd(8 downto 0) <= req_tag;
                            END IF;
                            q_rd  <= '1';
                            state <= S_FILL;
                        END IF;

                    WHEN S_FILL =>
                        IF q_rdy = '1' THEN
                            -- Mot recu : donnee et tag (valide) ecrits ensemble
                            nv := f_val;
                            nv(to_integer(f_w)) := '1';
                            f_val <= nv;
                            d_we  <= '1';
                            d_wa  <= f_idx & f_w;
                            d_wd  <= q_dout;
                            t_we  <= '1';
                            t_wa  <= f_idx;
                            t_wd  <= nv & f_tag;
                            q_rd  <= '0';
                            -- Suite de la ligne, sauf fin de ligne, mot deja
                            -- valide, ou coeur en attente d'un mot qui ne
                            -- viendra pas dans ce remplissage
                            IF f_w /= 7 AND nv(to_integer(f_w) + 1) = '0' AND
                               NOT (miss = '1' AND NOT (req_idx = f_idx AND req_tag = f_tag AND req_w >= f_w)) THEN
                                f_w   <= f_w + 1;
                                state <= S_NEXT;
                            ELSE
                                state <= S_IDLE;
                            END IF;
                        END IF;

                    WHEN S_NEXT =>
                        -- rd retombe un cycle entre deux requetes (protocole)
                        q_rd  <= '1';
                        state <= S_FILL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
