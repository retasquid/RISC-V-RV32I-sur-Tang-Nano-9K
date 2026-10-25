LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY barrelShifterRight IS
    PORT(
        s1    : in  std_logic_vector(31 downto 0);
        s2    : in  std_logic_vector(4 downto 0);
        arith : in  std_logic;
        d     : out std_logic_vector(31 downto 0)
    );
END ENTITY;

ARCHITECTURE barrelShifterRightV1 OF barrelShifterRight IS
    SIGNAL mux0, mux1, mux2, mux3 : std_logic_vector(31 downto 0);
    SIGNAL sign : std_logic;
BEGIN

    sign <= arith AND s1(31);

    mux0 <= sign & s1(31 downto 1)
            WHEN s2(0) = '1' ELSE s1;

    mux1 <= sign & sign & mux0(31 downto 2)
            WHEN s2(1) = '1' ELSE mux0;

    mux2 <= (31 downto 28 => sign) & mux1(31 downto 4)
            WHEN s2(2) = '1' ELSE mux1;

    mux3 <= (31 downto 24 => sign) & mux2(31 downto 8)
            WHEN s2(3) = '1' ELSE mux2;

    d <= (31 downto 16 => sign) & mux3(31 downto 16)
         WHEN s2(4) = '1' ELSE mux3;

END ARCHITECTURE;

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY barrelShifterLeft IS
    PORT(
        s1    : in  std_logic_vector(31 downto 0);
        s2    : in  std_logic_vector(4 downto 0);
        d     : out std_logic_vector(31 downto 0)
    );
END ENTITY;

ARCHITECTURE barrelShifterLefttV1 OF barrelShifterLeft IS
    SIGNAL mux0, mux1, mux2, mux3 : std_logic_vector(31 downto 0);
BEGIN

    mux0 <= s1(30 downto 0) & '0'
            WHEN s2(0) = '1' ELSE s1;

    mux1 <= mux0(29 downto 0) & "00"
            WHEN s2(1) = '1' ELSE mux0;

    mux2 <= mux1(27 downto 0) & "0000"
            WHEN s2(2) = '1' ELSE mux1;

    mux3 <= mux2(23 downto 0) & x"00"
            WHEN s2(3) = '1' ELSE mux2;

    d <= mux3(15 downto 0) & x"0000"
         WHEN s2(4) = '1' ELSE mux3;

END ARCHITECTURE;