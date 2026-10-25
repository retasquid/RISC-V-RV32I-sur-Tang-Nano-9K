--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: IP file
--Tool Version: V1.9.11.01 Education (64-bit)
--Part Number: GW1NR-LV9QN88PC6/I5
--Device: GW1NR-9
--Device Version: C
--Created Time: Mon Aug 31 16:38:18 2026

library IEEE;
use IEEE.std_logic_1164.all;

entity Gowin_OSC is
    port (
        oscout: out std_logic
    );
end Gowin_OSC;

architecture Behavioral of Gowin_OSC is

    --component declaration
    component OSC
        generic (
            FREQ_DIV: in integer := 2;
            DEVICE: in string := "GW1N-4"
        );
        port (
            OSCOUT: out std_logic
        );
    end component;

begin
    osc_inst: OSC
        generic map (
            FREQ_DIV => 2,
            DEVICE => "GW1NR-9C"
        )
        port map (
            OSCOUT => oscout
        );

end Behavioral; --Gowin_OSC
