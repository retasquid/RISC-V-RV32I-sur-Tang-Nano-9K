--------------------------------------------------------------------------------
-- vgaSigGen.vhd
-- Generateur VGA monochrome, horloge pixel ~25 MHz, image 640x400 :
--   MODE_480 = true (defaut) : sortie 640x480 @ 60 Hz, image centree (40 lignes
--     noires en haut et en bas). Mode standard reconnu par tous les ecrans.
--   MODE_480 = false : sortie 640x400 @ 70 Hz. Mode ambigu : meme frequence
--     de ligne et memes polarites que le mode texte 720x400 @ 70, que beaucoup
--     d'ecrans LCD choisissent -> image decalee de quelques pixels.
-- La VRAM contient 20 mots de 32 bits par ligne (8000 mots), le bit 31 d'un
-- mot est le pixel le plus a gauche (comme set_pixel dans periph.c).
--
-- Pipeline fixe de 2 cycles, adapte a une BRAM a 1 cycle de latence :
--   etage 0 : compteurs H/V -> adresse du mot (en_vram = zone visible)
--   etage 1 : la BRAM rend le mot, selection du bit (h retarde d'un cycle)
--   etage 2 : RGB, Hsync et Vsync sortent de registres
-- Les synchros sont retardees d'autant que les pixels : l'alignement est
-- garanti, l'image entiere est simplement decalee de 2 pixels d'horloge.
-- Polarites normalisees : Hsync negative ; Vsync negative en 640x480,
-- positive en 640x400.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaSignalGen IS
    GENERIC (
        MODE_480 : boolean := true
    );
    PORT (
        clk_xtal  : in  std_logic;                      -- horloge pixel
        rst       : in  std_logic;                      -- synchrone a clk_xtal

        Hsync     : out std_logic;
        Vsync     : out std_logic;
        RED       : out std_logic;
        GREEN     : out std_logic;
        BLUE      : out std_logic;

        en_vram   : out std_logic;
        addr_vram : out std_logic_vector(12 downto 0);
        dout_vram : in  std_logic_vector(31 downto 0)
    );
END ENTITY vgaSignalGen;

ARCHITECTURE vgaSignalGenV2 OF vgaSignalGen IS
    CONSTANT H_VISIBLE : natural := 640;
    CONSTANT H_FRONT   : natural := 16;
    CONSTANT H_SYNC    : natural := 96;
    CONSTANT H_TOTAL   : natural := 800;

    FUNCTION sel(c : boolean; a, b : natural) RETURN natural IS
    BEGIN
        IF c THEN RETURN a; ELSE RETURN b; END IF;
    END FUNCTION;

    -- Lignes : zone affichee (V_DISP) dont l'image 640x400 occupe
    -- [V_TOP, V_TOP + IMG_LINES[ ; puis front porch, synchro, back porch
    CONSTANT IMG_LINES : natural := 400;
    CONSTANT V_DISP    : natural := sel(MODE_480, 480, 400);
    CONSTANT V_TOP     : natural := sel(MODE_480, 40, 0);
    CONSTANT V_FRONT   : natural := sel(MODE_480, 10, 12);
    CONSTANT V_SYNC    : natural := 2;
    CONSTANT V_TOTAL   : natural := sel(MODE_480, 525, 449);

    CONSTANT HSYNC_ACTIVE : std_logic := '0';
    FUNCTION vs_pol(c : boolean) RETURN std_logic IS
    BEGIN
        IF c THEN RETURN '0'; ELSE RETURN '1'; END IF;
    END FUNCTION;
    CONSTANT VSYNC_ACTIVE : std_logic := vs_pol(MODE_480);

    CONSTANT WORDS_PER_LINE : natural := H_VISIBLE / 32;

    SIGNAL h_cnt     : unsigned(9 downto 0) := (OTHERS => '0');
    SIGNAL v_cnt     : unsigned(9 downto 0) := (OTHERS => '0');
    SIGNAL line_base : unsigned(12 downto 0) := (OTHERS => '0');   -- v_cnt * 20

    SIGNAL vis0, hs0, vs0 : std_logic;
    -- Registres de synchro initialises a l'etat INACTIF : pas de fausse
    -- impulsion apres la configuration ou le reset
    SIGNAL vis1           : std_logic := '0';
    SIGNAL hs1, hs2       : std_logic := NOT HSYNC_ACTIVE;
    SIGNAL vs1, vs2       : std_logic := NOT VSYNC_ACTIVE;
    SIGNAL bit1           : unsigned(4 downto 0) := (OTHERS => '0');
    SIGNAL pixel          : std_logic;
BEGIN

    -- Etage 0 : compteurs, zone visible, synchros, adresse du mot
    vis0 <= '1' WHEN h_cnt < H_VISIBLE AND v_cnt >= V_TOP AND v_cnt < V_TOP + IMG_LINES ELSE '0';
    hs0  <= HSYNC_ACTIVE WHEN h_cnt >= H_VISIBLE + H_FRONT AND
                              h_cnt <  H_VISIBLE + H_FRONT + H_SYNC ELSE NOT HSYNC_ACTIVE;
    vs0  <= VSYNC_ACTIVE WHEN v_cnt >= V_DISP + V_FRONT AND
                              v_cnt <  V_DISP + V_FRONT + V_SYNC ELSE NOT VSYNC_ACTIVE;

    en_vram   <= vis0;
    addr_vram <= std_logic_vector(line_base + resize(h_cnt(9 downto 5), 13));

    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            IF rst = '1' THEN
                h_cnt     <= (OTHERS => '0');
                v_cnt     <= (OTHERS => '0');
                line_base <= (OTHERS => '0');
            ELSIF h_cnt = H_TOTAL - 1 THEN
                h_cnt <= (OTHERS => '0');
                IF v_cnt = V_TOTAL - 1 THEN
                    v_cnt     <= (OTHERS => '0');
                    line_base <= (OTHERS => '0');
                ELSE
                    v_cnt <= v_cnt + 1;
                    -- line_base = (v_cnt - V_TOP) * 20 sur les lignes d'image
                    IF v_cnt >= V_TOP AND v_cnt < V_TOP + IMG_LINES THEN
                        line_base <= line_base + WORDS_PER_LINE;
                    END IF;
                END IF;
            ELSE
                h_cnt <= h_cnt + 1;
            END IF;
        END IF;
    END PROCESS;

    Hsync <= hs2;
    Vsync <= vs2;

    -- Etage 1 : le mot de la BRAM est disponible, selection du pixel
    pixel <= dout_vram(31 - to_integer(bit1));

    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            vis1 <= vis0;
            hs1  <= hs0;
            vs1  <= vs0;
            bit1 <= h_cnt(4 downto 0);

            -- Etage 2 : sorties registrees
            hs2 <= hs1;
            vs2 <= vs1;
            IF vis1 = '1' THEN
                RED   <= pixel;
                GREEN <= pixel;
                BLUE  <= pixel;
            ELSE
                RED   <= '0';
                GREEN <= '0';
                BLUE  <= '0';
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
