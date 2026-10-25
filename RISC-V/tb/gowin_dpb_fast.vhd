--------------------------------------------------------------------------------
-- gowin_dpb_fast.vhd  (simulation uniquement)
-- Remplacant comportemental de l'IP Gowin_DPB (double port 8K x 8, lecture
-- "bypass") pour les tests systeme : memes ports, meme comportement que le
-- modele prim_sim mesure sur la vraie IP (1 cycle de latence en lecture,
-- sortie conservee quand ce = '0', reset synchrone de la sortie). Le port B
-- est en lecture seule (le design n'ecrit jamais par le port B).
-- vga_tb utilise la vraie IP ; top_tests.do compile ce fichier A LA PLACE de
-- src/gowin_dpb/gowin_dpb.vhd pour garder des temps de simulation courts.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Gowin_DPB is
    port (
        douta: out std_logic_vector(7 downto 0);
        doutb: out std_logic_vector(7 downto 0);
        clka: in std_logic;
        ocea: in std_logic;
        cea: in std_logic;
        reseta: in std_logic;
        wrea: in std_logic;
        clkb: in std_logic;
        oceb: in std_logic;
        ceb: in std_logic;
        resetb: in std_logic;
        wreb: in std_logic;
        ada: in std_logic_vector(12 downto 0);
        dina: in std_logic_vector(7 downto 0);
        adb: in std_logic_vector(12 downto 0);
        dinb: in std_logic_vector(7 downto 0)
    );
end entity;

architecture fast of Gowin_DPB is
    type mem_t is array (0 to 8191) of std_logic_vector(7 downto 0);
    signal mem : mem_t := (others => (others => '0'));   -- ecrit par le port A seul
begin
    pa : process (clka)
    begin
        if rising_edge(clka) then
            if reseta = '1' then
                douta <= (others => '0');
            elsif cea = '1' then
                if wrea = '1' then
                    mem(to_integer(unsigned(ada))) <= dina;
                    douta <= dina;                       -- mode normal
                else
                    douta <= mem(to_integer(unsigned(ada)));
                end if;
            end if;
        end if;
    end process;

    pb : process (clkb)
    begin
        if rising_edge(clkb) then
            if resetb = '1' then
                doutb <= (others => '0');
            elsif ceb = '1' then
                -- Port B en lecture seule dans ce design (wreb = '0')
                doutb <= mem(to_integer(unsigned(adb)));
            end if;
        end if;
    end process;
end architecture;
