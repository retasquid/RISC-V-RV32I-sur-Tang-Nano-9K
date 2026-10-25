--------------------------------------------------------------------------------
-- RAM.vhd
-- RAM interne de 256 mots (1 KiB), alternative a la PSRAM (u2 commente dans top).
-- Ecriture par octets selon wenb ; comme pour qspi_sram, din n'est PAS
-- decale (core.vhd) : l'octet 0 de din va dans le premier octet active.
-- Bus : rdy n'est leve que pour une requete qui vise la RAM (cs) et
-- retombe avec rd/we ; l'ecriture n'a lieu qu'au premier cycle.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY RAM IS
    PORT(
        dout            : out std_logic_vector(31 downto 0);
        din             : in std_logic_vector(31 downto 0);
        adr             : in std_logic_vector(7 downto 0);
        wenb            : in std_logic_vector(3 downto 0);
        rdy             : out std_logic;
        clk, cs, we, rd : in std_logic
    );

END ENTITY;

ARCHITECTURE RAMV2 OF RAM IS
    TYPE ram_type IS ARRAY (0 to 255) OF std_logic_vector(31 downto 0);
    SIGNAL ram_d : ram_type := (others => (others => '0'));
    SIGNAL doutR : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL rdyR  : std_logic := '0';
    SIGNAL dinSh : std_logic_vector(31 downto 0);
BEGIN

    dout <= doutR;
    rdy  <= rdyR;

    -- Donnee placee sur l'octet de poids faible active par wenb
    dinSh <= din                            WHEN wenb(0) = '1' ELSE
             din(23 downto 0) & x"00"       WHEN wenb(1) = '1' ELSE
             din(15 downto 0) & x"0000"     WHEN wenb(2) = '1' ELSE
             din(7 downto 0)  & x"000000";

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            doutR <= ram_d(to_integer(unsigned(adr)));
            IF cs = '1' AND (rd XOR we) = '1' THEN
                IF we = '1' AND rdyR = '0' THEN
                    FOR i IN 0 TO 3 LOOP
                        IF wenb(i) = '1' THEN
                            ram_d(to_integer(unsigned(adr)))(8*i+7 DOWNTO 8*i) <= dinSh(8*i+7 DOWNTO 8*i);
                        END IF;
                    END LOOP;
                END IF;
                rdyR <= '1';
            ELSE
                rdyR <= '0';
            END IF;
        END IF;
    END PROCESS;
END ARCHITECTURE;
