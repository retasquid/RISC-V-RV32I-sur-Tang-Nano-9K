--------------------------------------------------------------------------------
-- clkDiv.vhd
-- Impulsions d'un cycle : enCore toutes les 17 periodes de clk27, enMem toutes
-- les 5. Plus instancie dans top depuis l'etape 6 (le coeur tourne a chaque
-- cycle) : ne sert plus qu'aux TB unitaires, comme rythme du maitre de bus
-- "lent" (generic FAST = false).
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY clkDiv IS
    PORT(
        clk27 : in std_logic;
        enCore : out std_logic;
        enMem : out std_logic
    );
END ENTITY;

ARCHITECTURE clkDivV1 OF clkDiv IS
    component Gowin_OSC
        port (
            oscout: out std_logic
        );
    end component;

    SIGNAL cnt, cnt2  : unsigned(31 downto 0) := (OTHERS => '0');
BEGIN

    --osc: Gowin_OSC
    --port map (
    --    oscout => clkOsc    --262.6 MHZ
    --);

    PROCESS(clk27)
    BEGIN
        IF rising_edge(clk27) THEN
            IF cnt = x"0000010" THEN
                cnt  <= (OTHERS => '0');
                enCore <= '1'; -- Impulsion !
            ELSE
                cnt <= cnt + 1;
                enCore <= '0';
            END IF;

            IF cnt2 = x"0000004" THEN 
                cnt2  <= (OTHERS => '0');
                enMem <= '1'; -- Impulsion !
            ELSE
                cnt2 <= cnt2 + 1;
                enMem  <= '0';
            END IF;
        END IF;
    END PROCESS;
END ARCHITECTURE;