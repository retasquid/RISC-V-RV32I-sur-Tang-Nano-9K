LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY MUX2_32 IS
    PORT(
        in0, in1        : in    std_logic_vector(31 downto 0);
        output          : out   std_logic_vector(31 downto 0);
        sel             : in    std_logic
    );
END ENTITY;

ARCHITECTURE MUX2_32V1 OF MUX2_32 IS
BEGIN

    output <= in1 WHEN sel = '1' ELSE in0;

END ARCHITECTURE;