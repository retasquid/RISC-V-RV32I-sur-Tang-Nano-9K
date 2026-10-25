LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY MUX4_32 IS
    PORT(
        in0, in1, in2, in3      : in    std_logic_vector(31 downto 0);
        output                  : out   std_logic_vector(31 downto 0);
        sel                     : in    std_logic_vector(1 downto 0)
    );
END ENTITY;

ARCHITECTURE MUX4_32V1 OF MUX4_32 IS
BEGIN

    output <= in0 WHEN sel = "00" ELSE 
              in1 WHEN sel = "01" ELSE 
              in2 WHEN sel = "10" ELSE 
              in3;

END ARCHITECTURE;