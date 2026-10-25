--------------------------------------------------------------------------------
-- top_tb.vhd
-- Testbench systeme : le vrai top (coeur + qspi_flash + qspi_sram +
-- peripherals) avec flash_model (charge avec HEX_FILE) et psram_model.
-- Le programme de test ecrit son resultat a TOHOST = 0x00000040 (voir
-- soft/tests/env/riscv_test.h) : 1 = succes, (n << 1) | 1 = echec du test n.
-- Les caracteres emis sur l'UART sont affiches ligne par ligne.
--
-- 'status' (lu par sim/top_tests.do) : 0 en cours, 1 succes, 2 echec du
-- programme, 3 timeout, 4 erreur de protocole flash/PSRAM.
-- Programmes : soft/tests/build_tests.py -> RISC-V/sim/tests/*.hex
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_top is
    generic (
        HEX_FILE : string := "tests/rv32ui-simple.hex";
        MAX_TIME : time   := 60 ms
    );
end entity;

architecture sim of tb_top is
    constant BIT_T  : time := 1 sec / 115200;
    constant TOHOST : std_logic_vector(31 downto 0) := x"00000040";

    signal clk27        : std_logic := '0';
    signal clk_sys      : std_logic := '0';
    signal rst_n        : std_logic := '1';   -- pas d'appui bouton : POR seul
    signal out0         : std_logic_vector(31 downto 0);
    signal uart_tx, clk : std_logic;
    signal scs, sclk    : std_logic;
    signal s0, s1, s2, s3 : std_logic;
    signal fcs, fclk    : std_logic;
    signal f0, f1, f2, f3 : std_logic;
    signal hs, vs       : std_logic;
    signal r3, g3       : std_logic_vector(2 downto 0);
    signal b2           : std_logic_vector(1 downto 0);

    signal qpi, cont    : std_logic;
    signal txn, nerr    : natural;
    signal ftxn, fcmd   : natural;
    signal ferr         : natural;
    signal la, fla      : std_logic_vector(23 downto 0);

    signal tohost_val   : std_logic_vector(31 downto 0) := (others => '0');
    signal tohost_seen  : boolean := false;
    signal sim_done     : boolean := false;
    signal status       : natural := 0;
begin

    clk27 <= not clk27 after 18.5185 ns when not sim_done;

    s0 <= 'H'; s1 <= 'H'; s2 <= 'H'; s3 <= 'H';
    f0 <= 'H'; f1 <= 'H'; f2 <= 'H'; f3 <= 'H';

    dut : entity work.top
        port map (
            out0 => out0, uart_tx => uart_tx, uart_rx => '1', clk => clk, clk27 => clk27,
            sram_CS => scs, sram_CLK => sclk,
            sram_SIO0 => s0, sram_SIO1 => s1, sram_SIO2 => s2, sram_SIO3 => s3,
            flash_CS => fcs, flash_CLK => fclk,
            flash_SIO0 => f0, flash_SIO1 => f1, flash_SIO2 => f2, flash_SIO3 => f3,
            hSync => hs, vSync => vs, red3 => r3, green3 => g3, blue2 => b2,
            rst_n => rst_n
        );

    u_psram : entity work.psram_model
        generic map (MEM_ADDR_BITS => 20)     -- 1 MiB : pile de link.ld comprise
        port map (
            ce_n => scs, sclk => sclk, sio0 => s0, sio1 => s1, sio2 => s2, sio3 => s3,
            qpi_mode => qpi, txn_count => txn, last_addr => la, errors => nerr
        );

    u_flash : entity work.flash_model
        generic map (MEM_ADDR_BITS => 16, INIT_FILE => HEX_FILE)
        port map (
            cs_n => fcs, sclk => fclk, sio0 => f0, sio1 => f1, sio2 => f2, sio3 => f3,
            cont_mode => cont, txn_count => ftxn, cmd_count => fcmd,
            last_addr => fla, errors => ferr
        );

    -- Releve des ecritures a TOHOST sur le bus du coeur (horloge systeme du
    -- rPLL interne au top)
    clk_sys_mon : process
        alias clk_dut is <<signal .tb_top.dut.clk_sys : std_logic>>;
    begin
        wait on clk_dut;
        clk_sys <= clk_dut;
    end process;

    tohost_mon : process (clk_sys)
        alias bus_we   is <<signal .tb_top.dut.we   : std_logic>>;
        alias bus_adr  is <<signal .tb_top.dut.adr  : std_logic_vector(31 downto 0)>>;
        alias bus_dout is <<signal .tb_top.dut.dout : std_logic_vector(31 downto 0)>>;
    begin
        if rising_edge(clk_sys) and bus_we = '1' and bus_adr = TOHOST then
            tohost_val  <= bus_dout;
            tohost_seen <= true;
        end if;
    end process;

    -- Affichage de la sortie UART, ligne par ligne
    uart_mon : process
        variable c    : std_logic_vector(7 downto 0);
        variable line : string(1 to 80);
        variable n    : natural := 0;
    begin
        wait until falling_edge(uart_tx);
        wait for BIT_T * 1.5;
        for i in 0 to 7 loop c(i) := uart_tx; wait for BIT_T; end loop;
        if c = x"0A" or c = x"0D" or n = line'length then
            if n > 0 then report "UART : " & line(1 to n); end if;
            n := 0;
        else
            n := n + 1;
            line(n) := character'val(to_integer(unsigned(c)));
        end if;
    end process;

    main : process
        alias adr_pc is <<signal .tb_top.dut.u4.adrPc : std_logic_vector(31 downto 0)>>;
        variable v : unsigned(31 downto 0);
    begin
        wait until tohost_seen for MAX_TIME;
        wait for 1 us;
        v := unsigned(tohost_val);
        if not tohost_seen then
            report "TB_RESULT: ECHEC " & HEX_FILE & " : timeout " & time'image(MAX_TIME)
                   & ", PC = 0x" & to_hstring(adr_pc) severity error;
            status <= 3;
        elsif ferr /= 0 or nerr /= 0 then
            report "TB_RESULT: ECHEC " & HEX_FILE & " : " & integer'image(ferr) & " erreur(s) flash, "
                   & integer'image(nerr) & " erreur(s) PSRAM" severity error;
            status <= 4;
        elsif v = 1 then
            report "TB_RESULT: SUCCES " & HEX_FILE & " (" & time'image(now) & ")";
            status <= 1;
        else
            report "TB_RESULT: ECHEC " & HEX_FILE & " : test " & integer'image(to_integer(v / 2))
                   & " (TOHOST = 0x" & to_hstring(tohost_val) & ")" severity error;
            status <= 2;
        end if;
        sim_done <= true;
        wait for 0 ns;
        std.env.finish;
        wait;
    end process;

end architecture;
