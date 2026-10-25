LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY signExtender IS
    PORT(
        d_din       : in  std_logic_vector(31 downto 0);
        func3       : in  std_logic_vector(2 downto 0);
        adr2        : in  std_logic_vector(1 downto 0);
        dLsu        : out std_logic_vector(31 downto 0)
    );
END ENTITY;

ARCHITECTURE signExtenderV1 OF signExtender IS
    SIGNAL ld_byte_val : std_logic_vector(7 downto 0);
    SIGNAL ld_half_val : std_logic_vector(15 downto 0);
BEGIN

    --Partie load
    WITH adr2 SELECT
    ld_byte_val <= d_din(7 downto 0)    WHEN "00",
                d_din(15 downto 8)      WHEN "01",
                d_din(23 downto 16)     WHEN "10",
                d_din(31 downto 24)     WHEN OTHERS;

    ld_half_val <= d_din(15 downto 0) WHEN adr2(1) = '0' ELSE d_din(31 downto 16);

    WITH func3 SELECT
    dLsu <= std_logic_vector(resize(signed(ld_byte_val), 32))      WHEN "000",
            std_logic_vector(resize(signed(ld_half_val), 32))      WHEN "001",
            std_logic_vector(resize(unsigned(ld_byte_val), 32))    WHEN "100",
            std_logic_vector(resize(unsigned(ld_half_val), 32))    WHEN "101",
            d_din                                                  WHEN OTHERS;

END ARCHITECTURE;