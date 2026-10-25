LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY pc IS
    PORT(
        imm, d                          : in std_logic_vector(31 downto 0);
        adr, adr4                       : out std_logic_vector(31 downto 0);
        pcsrc, brch, clk, rst, en       : in std_logic
    );
END ENTITY;

ARCHITECTURE pcV1 OF pc IS
    SIGNAL add4, addImm         : std_logic_vector(31 downto 0);
    SIGNAL pc_adr               : std_logic_vector(31 downto 0) := x"40000000";
BEGIN

    add4 <= std_logic_vector(unsigned(pc_adr) + x"00000004");
    addImm <= std_logic_vector(unsigned(pc_adr) + unsigned(imm));

    adr <= pc_adr;
    adr4 <= add4;

    PROCESS(clk, rst)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                pc_adr <= x"40000000";
            ELSIF en = '1' THEN
                IF pcsrc = '1' THEN
                    -- JAL/JALR : bit 0 de la cible force a 0 (spec JALR)
                    pc_adr <= d(31 downto 1) & '0';
                ELSE
                    IF brch = '1' THEN
                        pc_adr <= addImm;
                    ELSE
                        pc_adr <= add4;
                    END IF;
                END IF;
                
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;