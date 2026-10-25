--------------------------------------------------------------------------------
-- qspi_sram_tb.vhd
-- Testbench auto-verifiant du controleur PSRAM (qspi_sram) avec :
--   * le vrai clkDiv (enCore / enMem a partir de clk27)
--   * un maitre de bus qui reproduit le handshake de uc (tb_pkg)
--   * le modele LY68L6400 (psram_model) qui verifie protocole et timings
--   * un modele de reference de la memoire cote TB
--
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/qspi_sram.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_qspi_sram is
    generic (
        -- true : maitre a pleine vitesse (comme uc V2) ; false : 1 pas / 17
        -- cycles (ancien rythme enCore, requetes tenues longtemps)
        FAST : boolean := true
    );
end entity;

architecture sim of tb_qspi_sram is

    constant MEM_BITS : natural := 16;   -- memoire simulee : 64 KiB (alias au-dela)

    signal clk27        : std_logic := '0';
    signal rst          : std_logic := '1';
    signal enSlow       : std_logic;
    signal en           : std_logic;
    signal enMem        : std_logic;
    signal sim_done     : boolean := false;

    -- Bus coeur
    signal m            : bus_m_t := BUS_M_IDLE;
    signal din_bus      : std_logic_vector(31 downto 0);
    signal rdy          : std_logic;
    signal cs           : std_logic;

    -- QSPI
    signal sram_cs_n    : std_logic;
    signal sram_clk     : std_logic;
    signal sio0, sio1   : std_logic;
    signal sio2, sio3   : std_logic;

    -- Observation du modele
    signal qpi_mode     : std_logic;
    signal txn_count    : natural;
    signal last_addr    : std_logic_vector(23 downto 0);
    signal model_errors : natural;

begin

    clk27 <= not clk27 after CLK27_PERIOD / 2 when not sim_done;
    en    <= '1' when FAST else enSlow;

    -- Pull-ups des pads (PULL_MODE=UP dans le .cst) : une ligne flottante lit 'H'
    sio0 <= 'H';
    sio1 <= 'H';
    sio2 <= 'H';
    sio3 <= 'H';

    cs <= '1' when m.adr(31 downto 24) = x"80" else '0';

    u_div : entity work.clkDiv
        port map (
            clk27  => clk27,
            enCore => enSlow,
            enMem  => enMem
        );

    dut : entity work.qspi_sram
        generic map (
            A_WIDTH => 23
        )
        port map (
            dout      => din_bus,
            din       => m.dout,
            adr       => m.adr(22 downto 0),
            cs        => cs,
            wr        => m.we,
            rd        => m.rd,
            rdy       => rdy,
            wenb      => m.wenb,
            clkEn     => en,
            clk       => clk27,
            rst       => rst,
            clkQspiEn => '1',            -- SCLK = clk27/2 = 13.5 MHz (comme dans top)
            sram_CS   => sram_cs_n,
            sram_CLK  => sram_clk,
            sram_SIO0 => sio0,
            sram_SIO1 => sio1,
            sram_SIO2 => sio2,
            sram_SIO3 => sio3
        );

    u_psram : entity work.psram_model
        generic map (
            MEM_ADDR_BITS => MEM_BITS
        )
        port map (
            ce_n      => sram_cs_n,
            sclk      => sram_clk,
            sio0      => sio0,
            sio1      => sio1,
            sio2      => sio2,
            sio3      => sio3,
            qpi_mode  => qpi_mode,
            txn_count => txn_count,
            last_addr => last_addr,
            errors    => model_errors
        );

    stim : process
        constant BASE    : unsigned(31 downto 0) := x"80000000";
        constant TIMEOUT : natural := 400;   -- pas de uc (~250 us) avant d'abandonner un acces

        type ref_t is array (0 to 2**MEM_BITS - 1) of std_logic_vector(7 downto 0);
        variable ref     : ref_t := (others => (others => 'U'));
        variable errs    : natural := 0;
        variable n_acc   : natural := 0;
        variable n_to    : natural := 0;
        variable dead    : boolean := false;
        variable seed    : unsigned(31 downto 0) := x"2545F491";
        variable r       : std_logic_vector(31 downto 0);
        variable off     : natural;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                if errs <= 40 then
                    report "TB @" & time'image(now) & " : " & msg severity error;
                elsif errs = 41 then
                    report "TB : trop d'erreurs, les suivantes ne sont plus affichees" severity error;
                end if;
            end if;
        end procedure;

        procedure rnd(v : out std_logic_vector(31 downto 0)) is
            variable x : unsigned(31 downto 0) := seed;
        begin
            x    := x xor shift_left(x, 13);
            x    := x xor shift_right(x, 17);
            x    := x xor shift_left(x, 5);
            seed := x;
            v    := std_logic_vector(x);
        end procedure;

        procedure note_access(ok : boolean; what : string) is
        begin
            n_acc := n_acc + 1;
            if ok then
                n_to := 0;
            else
                check(false, what & " : pas de rdy apres " & integer'image(TIMEOUT) & " pas de uc");
                n_to := n_to + 1;
                if n_to >= 3 then
                    report "TB : 3 timeouts consecutifs, abandon des acces restants" severity error;
                    dead := true;
                end if;
            end if;
        end procedure;

        procedure do_store(o : natural; f3 : std_logic_vector(2 downto 0);
                           val : std_logic_vector(31 downto 0)) is
            variable a     : std_logic_vector(31 downto 0) := std_logic_vector(BASE + o);
            variable rdata : std_logic_vector(31 downto 0);
            variable ok    : boolean;
            variable t0    : natural;
            constant what  : string := "store f3=" & to_string(f3) & " @0x" & to_hstring(a)
                                       & " val=0x" & to_hstring(val);
        begin
            if dead then return; end if;
            bus_fetch(clk27, en, m);
            t0 := txn_count;
            bus_cycle(clk27, en, rdy, din_bus, m, true, a, val, core_wenb(f3, a),
                      rdata, ok, TIMEOUT);
            note_access(ok, what);
            if not ok then return; end if;
            for i in 0 to store_bytes(f3) - 1 loop
                ref((o + i) mod 2**MEM_BITS) := val(8*i + 7 downto 8*i);
            end loop;
            check(txn_count = t0 + 1, what & " : " & integer'image(txn_count - t0)
                  & " transaction(s) QSPI au lieu de 1");
            check(last_addr = a(23 downto 0), what & " : adresse recue par la PSRAM = 0x"
                  & to_hstring(last_addr));
        end procedure;

        procedure do_load(o : natural; f3 : std_logic_vector(2 downto 0)) is
            constant al    : natural := o - (o mod 4);
            variable a     : std_logic_vector(31 downto 0) := std_logic_vector(BASE + o);
            variable rdata : std_logic_vector(31 downto 0);
            variable exp   : std_logic_vector(31 downto 0);
            variable ok    : boolean;
            variable t0    : natural;
            constant what  : string := "load f3=" & to_string(f3) & " @0x" & to_hstring(a);
        begin
            if dead then return; end if;
            for i in 0 to 3 loop
                exp(8*i + 7 downto 8*i) := ref((al + i) mod 2**MEM_BITS);
            end loop;
            bus_fetch(clk27, en, m);
            t0 := txn_count;
            bus_cycle(clk27, en, rdy, din_bus, m, false, a, x"00000000", core_wenb(f3, a),
                      rdata, ok, TIMEOUT);
            note_access(ok, what);
            if not ok then return; end if;
            -- Le controleur lit toujours le mot aligne ; signExtender extrait l'octet/demi-mot
            check(rdata = exp, what & " : lu 0x" & to_hstring(rdata) & ", attendu 0x" & to_hstring(exp));
            check(txn_count = t0 + 1, what & " : " & integer'image(txn_count - t0)
                  & " transaction(s) QSPI au lieu de 1");
            check(last_addr = std_logic_vector(to_unsigned(al, 24)),
                  what & " : adresse recue par la PSRAM = 0x" & to_hstring(last_addr));
        end procedure;

        procedure wait_init is
        begin
            report "TB : attente de la fin de l'init PSRAM (tPU 150 us + sequence d'init)";
            wait for 250 us;
            check(qpi_mode = '1', "la PSRAM n'est pas en mode QPI apres l'init");
        end procedure;

    begin
        ------------------------------------------------------------------------
        -- Reset puis init
        ------------------------------------------------------------------------
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk27); end loop;
        rst <= '0';
        wait_init;

        ------------------------------------------------------------------------
        report "TB : T1 - SW/LW simple";
        do_store(16#0000#, F3_W, x"A1B2C3D4");
        do_load (16#0000#, F3_W);

        ------------------------------------------------------------------------
        report "TB : T2 - SW/LW avec bits d'adresse de poids fort";
        for k in 0 to 3 loop
            case k is
                when 0      => off := 16#7FFFFC#;
                when 1      => off := 16#400010#;
                when 2      => off := 16#123454#;
                when others => off := 16#0ABCD8#;
            end case;
            rnd(r);
            do_store(off, F3_W, r);
            do_load (off, F3_W);
        end loop;

        ------------------------------------------------------------------------
        -- Le coeur met s2 NON decale sur dout : les octets hauts de s2 sont
        -- aleatoires et ne doivent jamais etre ecrits
        report "TB : T3 - SB aux offsets 0..3";
        do_store(16#0100#, F3_W, x"11223344");
        for k in 0 to 3 loop
            rnd(r);
            do_store(16#0100# + k, F3_B, r);
            do_load (16#0100# + k, F3_BU);
        end loop;

        ------------------------------------------------------------------------
        report "TB : T4 - SH aux offsets 0 et 2";
        do_store(16#0200#, F3_W, x"55667788");
        for k in 0 to 1 loop
            rnd(r);
            do_store(16#0200# + 2*k, F3_H, r);
            do_load (16#0200# + 2*k, F3_HU);
        end loop;

        ------------------------------------------------------------------------
        report "TB : T5 - lectures a adresse non alignee (LB/LH)";
        do_load(16#0101#, F3_B);
        do_load(16#0102#, F3_H);
        do_load(16#0103#, F3_B);

        ------------------------------------------------------------------------
        report "TB : T6 - 300 acces aleatoires sur 256 octets";
        for k in 0 to 63 loop
            rnd(r);
            do_store(16#1000# + 4*k, F3_W, r);
        end loop;
        for k in 1 to 300 loop
            rnd(r);
            off := 16#1000# + to_integer(unsigned(r(9 downto 2)));
            if r(10) = '0' then
                do_load(off, F3_W);
            else
                case r(12 downto 11) is
                    when "00"   => do_store(off - (off mod 4), F3_W, r xor x"5A5A5A5A");
                    when "01"   => do_store(off - (off mod 2), F3_H, r xor x"A5A5A5A5");
                    when others => do_store(off,                F3_B, r xor x"3C3C3C3C");
                end case;
            end if;
        end loop;

        ------------------------------------------------------------------------
        report "TB : T7 - reset du controleur en cours de fonctionnement";
        wait until rising_edge(clk27);
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk27); end loop;
        rst <= '0';
        dead := false;
        n_to := 0;
        wait_init;
        rnd(r);
        do_store(16#2000#, F3_W, r);
        do_load (16#2000#, F3_W);

        ------------------------------------------------------------------------
        wait for 1 us;
        report "======== tb_qspi_sram : " & integer'image(n_acc) & " acces, "
               & integer'image(errs) & " erreur(s) TB, "
               & integer'image(model_errors) & " erreur(s) protocole PSRAM ========";
        if errs = 0 and model_errors = 0 then
            report "TB_RESULT: SUCCES";
        else
            report "TB_RESULT: ECHEC" severity error;
        end if;
        sim_done <= true;
        std.env.finish;
        wait;
    end process;

    watchdog : process
    begin
        wait for 100 ms;
        report "TB_RESULT: ECHEC (watchdog 100 ms)" severity failure;
        wait;
    end process;

end architecture;
