--------------------------------------------------------------------------------
-- gowin_rpll_fast.vhd  (simulation uniquement)
-- Remplacant leger de l'IP Gowin_rPLL pour les tests systeme : memes ports,
-- memes frequences (clkout = 27*13/7 = 50.14 MHz, clkoutd = 25.07 MHz), mais
-- simple generateur d'horloge. Le modele detaille de prim_sim.vhd ralentit
-- la simulation d'un facteur ~40 ; il reste utilise par vga_tb.
-- Gowin_rPLL_sys (horloge systeme 31.5 MHz) : idem, avec 'lock' qui monte
-- apres 2 us, comme le vrai PLL apres son verrouillage.
-- top_tests.do compile ce fichier A LA PLACE de src/gowin_rpll/gowin_rpll.vhd
-- et de src/gowin_rpll_sys/gowin_rpll_sys.vhd.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity Gowin_rPLL is
    port (
        clkout  : out std_logic;
        clkoutd : out std_logic;
        clkin   : in  std_logic
    );
end entity;

architecture fast of Gowin_rPLL is
    constant T_OUT : time := 19.944 ns;     -- 1 / 50.14 MHz
    signal c, cd   : std_logic := '0';
begin
    c       <= not c after T_OUT / 2;
    cd      <= not cd after T_OUT;
    clkout  <= c;
    clkoutd <= cd;
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity Gowin_rPLL_sys is
    port (
        clkout  : out std_logic;
        lock    : out std_logic;
        clkin   : in  std_logic
    );
end entity;

architecture fast of Gowin_rPLL_sys is
    constant T_OUT : time := 31.746 ns;     -- 1 / 31.5 MHz
    signal c       : std_logic := '0';
begin
    c      <= not c after T_OUT / 2;
    clkout <= c;
    lock   <= '0', '1' after 2 us;
end architecture;
