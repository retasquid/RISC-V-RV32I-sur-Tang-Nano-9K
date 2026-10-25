LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY alu IS
    PORT(
        s1, s2          : in std_logic_vector(31 downto 0);
        opcode          : in std_logic_vector(2 downto 0);
        alt, brchEn     : in std_logic;
        d               : out std_logic_vector(31 downto 0);
        branch          : out std_logic
    );

END ENTITY;

ARCHITECTURE aluV1 OF alu IS
    SIGNAL s2_addsub, dsr, dsl, s2n : std_logic_vector(31 downto 0);
    SIGNAL d_add                    : std_logic_vector(32 downto 0);
    SIGNAL eq, ne, lt, ge, ltu, geu : std_logic;
    SIGNAL branchAnd                : std_logic;

    COMPONENT barrelShifterLeft
        PORT(
            s1    : in  std_logic_vector(31 downto 0);
            s2    : in  std_logic_vector(4 downto 0);
            d     : out std_logic_vector(31 downto 0)
        );
    END COMPONENT;

    COMPONENT barrelShifterRight
        PORT(
            s1    : in  std_logic_vector(31 downto 0);
            s2    : in  std_logic_vector(4 downto 0);
            arith : in  std_logic;
            d     : out std_logic_vector(31 downto 0)
        );
    END COMPONENT;

BEGIN

    u1 : barrelShifterLeft PORT MAP(
        s1 => s1,
        s2 => s2(4 downto 0),
        d => dsl
        );

    u2 : barrelShifterRight PORT MAP(
        s1 => s1,
        s2 => s2(4 downto 0),
        arith => alt,
        d => dsr
        );
    
    s2n <= NOT s2;
    s2_addsub <= s2n WHEN alt = '1' ELSE s2;
    d_add <= std_logic_vector(
        unsigned('0' & s1) +
        unsigned('0' & s2_addsub) +
        (to_unsigned(0, 31) & alt)
    );

    eq <= '1' when d_add(31 downto 0) = (31 downto 0 => '0') else '0';
    ne <= NOT eq;
    lt <= ((d_add(31) OR s1(31)) AND ((d_add(31) AND s1(31)) OR s2n(31)));
    ge <= NOT lt;
    ltu <= NOT geu;
    geu <= d_add(32);

    branch <= branchAnd AND brchEn;

    WITH opcode SELECT
    d   <=  d_add(31 downto 0)                          WHEN "000",
            dsl                                         WHEN "001",
            (31 downto 1 => '0') & lt                   WHEN "010",
            (31 downto 1 => '0') & ltu                  WHEN "011",
            s1 XOR s2                                   WHEN "100",
            dsr                                         WHEN "101",
            s1 OR  s2                                   WHEN "110",
            s1 AND s2                                   WHEN "111",
            (OTHERS => '0')                             WHEN OTHERS;


    WITH opcode SELECT
    branchAnd <=    eq                                  WHEN "000",
                    ne                                  WHEN "001",
                    lt                                  WHEN "100",
                    ge                                  WHEN "101",
                    ltu                                 WHEN "110",
                    geu                                 WHEN "111",
                    '0'                                 WHEN OTHERS;

END ARCHITECTURE;