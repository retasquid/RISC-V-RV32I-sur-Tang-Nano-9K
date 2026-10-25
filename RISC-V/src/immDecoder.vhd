LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY immDecoder IS
    PORT(
        inst    : in  std_logic_vector(31 downto 0);
        instype : in  std_logic_vector(2 downto 0);
        imm     : out std_logic_vector(31 downto 0)
    );
END ENTITY;

ARCHITECTURE immDecoderV1 OF immDecoder IS
BEGIN

    WITH instype SELECT
    imm <=  (31 downto 0 => '0')                                                                 WHEN "000", --R-type

            (31 downto 12=>inst(31))&inst(31 downto 20)                                           WHEN "001", --I-type

            (31 downto 12=>inst(31))&inst(31 downto 25)&inst(11 downto 7)                         WHEN "010", --S-type

            (31 downto 13=>inst(31))&inst(31)&inst(7)&inst(30 downto 25)&inst(11 downto 8)&'0'    WHEN "011", --B-type

            inst(31 downto 12)&(11 downto 0 => '0')                                              WHEN "100", --U-type

            (31 downto 21 =>inst(31))&inst(31)&inst(19 downto 12)&inst(20)&inst(30 downto 21)&'0'  WHEN "101", --J-type

            (31 downto 0 => '0')                                                                 WHEN OTHERS;

END ARCHITECTURE;

