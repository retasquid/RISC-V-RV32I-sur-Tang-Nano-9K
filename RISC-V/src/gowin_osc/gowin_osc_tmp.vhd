--Copyright (C)2014-2025 Gowin Semiconductor Corporation.
--All rights reserved.
--File Title: Template file for instantiation
--Tool Version: V1.9.11.01 Education (64-bit)
--Part Number: GW1NR-LV9QN88PC6/I5
--Device: GW1NR-9
--Device Version: C
--Created Time: Mon Aug 31 16:38:18 2026

--Change the instance name and port connections to the signal names
----------Copy here to design--------

component Gowin_OSC
    port (
        oscout: out std_logic
    );
end component;

your_instance_name: Gowin_OSC
    port map (
        oscout => oscout
    );

----------Copy end-------------------
