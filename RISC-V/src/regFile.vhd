LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;

ENTITY regFile IS
    PORT(
        s1, s2 : out std_logic_vector(31 downto 0);
        rs1, rs2 : in std_logic_vector(4 downto 0);
        d : in std_logic_vector(31 downto 0);
        rd : in std_logic_vector(4 downto 0);
        clk, we : in std_logic
    );
END ENTITY;

ARCHITECTURE regFileV1 OF regFile IS
    TYPE regs_type IS ARRAY (0 to 31) OF std_logic_vector(31 downto 0);
    SIGNAL regs : regs_type := (others => (others => '0'));
    -- RAM distribuee (memoires 16x4 des blocs logiques, lecture
    -- combinatoire) : sans cet attribut, Gowin met le banc en BSRAM et en
    -- fait une copie par port de lecture, soit 2 blocs de 18 Kbit pour
    -- 1 Kbit utile chacun.
    ATTRIBUTE syn_ramstyle : string;
    ATTRIBUTE syn_ramstyle OF regs : SIGNAL IS "distributed_ram";

BEGIN
    s1 <= (OTHERS => '0') WHEN rs1="00000" ELSE regs(to_integer(unsigned(rs1)));
    s2 <= (OTHERS => '0') WHEN rs2="00000" ELSE regs(to_integer(unsigned(rs2)));

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF we = '1' AND rd /= "00000" THEN
                regs(to_integer(unsigned(rd))) <= d;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;