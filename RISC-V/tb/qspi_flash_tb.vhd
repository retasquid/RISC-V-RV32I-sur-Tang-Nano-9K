--------------------------------------------------------------------------------
-- qspi_flash_tb.vhd
-- Testbench auto-verifiant du controleur flash (qspi_flash) avec :
--   * le vrai clkDiv (enCore a partir de clk27)
--   * un maitre de bus qui reproduit le handshake de uc (tb_pkg)
--   * le modele GD25Q32C (flash_model) qui verifie protocole et timings,
--     rempli avec flash_pattern (tb_pkg) : le TB connait chaque octet
--
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/qspi_flash.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_qspi_flash is
    generic (
        -- true : maitre a pleine vitesse (comme uc V2) ; false : 1 pas / 17
        -- cycles (ancien rythme enCore, requetes tenues longtemps)
        FAST : boolean := true
    );
end entity;

architecture sim of tb_qspi_flash is

    constant MEM_BITS : natural := 16;   -- flash simulee : 64 KiB (alias au-dela)

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
    signal flash_cs_n   : std_logic;
    signal flash_clk    : std_logic;
    signal sio0, sio1   : std_logic;
    signal sio2, sio3   : std_logic;

    -- Observation du modele
    signal cont_mode    : std_logic;
    signal txn_count    : natural;
    signal cmd_count    : natural;
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

    cs <= '1' when m.adr(31 downto 24) = x"40" else '0';

    u_div : entity work.clkDiv
        port map (
            clk27  => clk27,
            enCore => enSlow,
            enMem  => enMem
        );

    dut : entity work.qspi_flash
        generic map (
            A_WIDTH => 22
        )
        port map (
            dout       => din_bus,
            adr        => m.adr(21 downto 0),
            cs         => cs,
            rd         => m.rd,
            wr         => m.we,
            rdy        => rdy,
            clk        => clk27,
            rst        => rst,
            clkQspiEn  => '1',            -- SCLK = clk27/2 = 13.5 MHz (comme dans top)
            flash_CS   => flash_cs_n,
            flash_CLK  => flash_clk,
            flash_SIO0 => sio0,
            flash_SIO1 => sio1,
            flash_SIO2 => sio2,
            flash_SIO3 => sio3
        );

    u_flash : entity work.flash_model
        generic map (
            MEM_ADDR_BITS => MEM_BITS
        )
        port map (
            cs_n      => flash_cs_n,
            sclk      => flash_clk,
            sio0      => sio0,
            sio1      => sio1,
            sio2      => sio2,
            sio3      => sio3,
            cont_mode => cont_mode,
            txn_count => txn_count,
            cmd_count => cmd_count,
            last_addr => last_addr,
            errors    => model_errors
        );

    stim : process
        constant BASE    : unsigned(31 downto 0) := x"40000000";
        constant TIMEOUT : natural := 400;   -- pas de uc (~250 us) avant d'abandonner un acces
        constant TIMEOUT_INIT : natural := 80000;  -- 1er acces apres reset : init (~2.1 ms) comprise

        variable errs    : natural := 0;
        variable n_acc   : natural := 0;
        variable n_to    : natural := 0;
        variable dead    : boolean := false;
        variable seed    : unsigned(31 downto 0) := x"6C8E9CF5";
        variable r       : std_logic_vector(31 downto 0);
        variable c0, s0  : natural;
        -- Flux (CS# tenu bas entre deux lectures) attendu cote controleur
        variable stream_open : boolean := false;
        variable stream_next : natural := 0;
        variable n_seq       : natural := 0;

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

        procedure note_access(ok : boolean; what : string; tmo : natural) is
        begin
            n_acc := n_acc + 1;
            if ok then
                n_to := 0;
            else
                check(false, what & " : pas de rdy apres " & integer'image(tmo) & " pas de uc");
                n_to := n_to + 1;
                if n_to >= 3 then
                    report "TB : 3 timeouts consecutifs, abandon des acces restants" severity error;
                    dead := true;
                end if;
            end if;
        end procedure;

        -- Deux pas de uc hors de la flash entre deux acces (cs flash = 0)
        procedure idle_steps is
        begin
            wait_tick(clk27, en);
            m.adr <= x"00000000";
            m.rd  <= '0';
            m.we  <= '0';
            wait_tick(clk27, en);
        end procedure;

        -- Transactions attendues (le modele les compte a la remontee de CS#) :
        --   lecture du mot suivant du flux : 0, et pas de nouvelle adresse
        --   autre lecture : 1 si un flux etait ouvert (il est ferme), sinon 0
        --   init = true (1re lecture apres reset) : 3 (sortie mode continu,
        --   66h, 99h) ; le flux ouvert a ete ferme par le reset, avant le releve
        procedure do_load(o : natural; f3 : std_logic_vector(2 downto 0);
                          tmo : natural := TIMEOUT; init : boolean := false) is
            constant al    : natural := o - (o mod 4);
            variable a     : std_logic_vector(31 downto 0) := std_logic_vector(BASE + o);
            variable rdata : std_logic_vector(31 downto 0);
            variable exp   : std_logic_vector(31 downto 0);
            variable ok    : boolean;
            variable t1    : natural;
            variable seq   : boolean;
            variable n_txn : natural;
            variable a0    : std_logic_vector(23 downto 0);
            constant what  : string := "load f3=" & to_string(f3) & " @0x" & to_hstring(a);
        begin
            if dead then return; end if;
            seq   := stream_open and al = stream_next and not init;
            n_txn := 0;
            if stream_open and not seq then n_txn := 1; end if;
            if init then n_txn := 3; end if;
            for i in 0 to 3 loop
                exp(8*i + 7 downto 8*i) := flash_pattern((al + i) mod 2**MEM_BITS);
            end loop;
            idle_steps;
            t1 := txn_count;
            a0 := last_addr;
            bus_cycle(clk27, en, rdy, din_bus, m, false, a, x"00000000", core_wenb(f3, a),
                      rdata, ok, tmo);
            note_access(ok, what, tmo);
            if not ok then return; end if;
            -- Le controleur lit toujours le mot aligne ; signExtender extrait l'octet/demi-mot
            check(rdata = exp, what & " : lu 0x" & to_hstring(rdata) & ", attendu 0x" & to_hstring(exp));
            check(txn_count = t1 + n_txn, what & " : " & integer'image(txn_count - t1)
                  & " transaction(s) QSPI au lieu de " & integer'image(n_txn));
            if seq then
                check(last_addr = a0, what & " : nouvelle adresse envoyee (0x" & to_hstring(last_addr)
                      & ") au lieu de poursuivre le flux");
                n_seq := n_seq + 1;
            else
                check(last_addr = std_logic_vector(to_unsigned(al, 24)),
                      what & " : adresse recue par la flash = 0x" & to_hstring(last_addr));
            end if;
            check(cont_mode = '1', what & " : la flash n'est pas restee en mode continu");
            stream_open := true;
            stream_next := al + 4;
        end procedure;

        procedure do_store(o : natural; val : std_logic_vector(31 downto 0)) is
            variable a     : std_logic_vector(31 downto 0) := std_logic_vector(BASE + o);
            variable rdata : std_logic_vector(31 downto 0);
            variable ok    : boolean;
            variable t1    : natural;
            constant what  : string := "store @0x" & to_hstring(a);
        begin
            if dead then return; end if;
            idle_steps;
            t1 := txn_count;
            bus_cycle(clk27, en, rdy, din_bus, m, true, a, val, core_wenb(F3_W, a),
                      rdata, ok, TIMEOUT);
            note_access(ok, what, TIMEOUT);
            if not ok then return; end if;
            check(txn_count = t1, what & " : une ecriture en flash a genere "
                  & integer'image(txn_count - t1) & " transaction(s) QSPI");
        end procedure;

        -- Reset du controleur puis, comme le coeur, fetch en 0x40000000 tout de
        -- suite : la lecture attend la fin de l'init (tVSL 2 ms, sortie du mode
        -- continu, 66h, 99h, tRST), soit 3 transactions + celle de la lecture.
        procedure reset_and_first_load is
            variable c1 : natural;
        begin
            wait until rising_edge(clk27);
            rst <= '1';
            for i in 1 to 20 loop wait until rising_edge(clk27); end loop;
            rst <= '0';
            dead := false;
            n_to := 0;
            c1   := cmd_count;
            report "TB : reset puis 1er fetch (attend la fin de l'init flash, ~2.1 ms)";
            do_load(16#0000#, F3_W, TIMEOUT_INIT, init => true);
            check(cmd_count = c1 + 1, "1er acces : " & integer'image(cmd_count - c1)
                  & " commande(s) EBh au lieu de 1");
        end procedure;

    begin
        ------------------------------------------------------------------------
        report "TB : T1 - init puis premiere lecture (commande EBh, passage en mode continu)";
        reset_and_first_load;

        ------------------------------------------------------------------------
        report "TB : T2 - 64 lectures sequentielles (comme des fetchs) : flux, sans commande";
        c0 := cmd_count;
        s0 := n_seq;
        for k in 1 to 64 loop
            do_load(4*k, F3_W);
        end loop;
        check(cmd_count = c0, "T2 : " & integer'image(cmd_count - c0)
              & " commande(s) EBh envoyee(s) en mode continu");
        check(n_seq = s0 + 64, "T2 : " & integer'image(n_seq - s0) & " lecture(s) en flux au lieu de 64");

        ------------------------------------------------------------------------
        report "TB : T3 - adresses hautes (A21..A16)";
        do_load(16#3FFFFC#, F3_W);
        do_load(16#200000#, F3_W);
        do_load(16#123454#, F3_W);
        do_load(16#0ABCD8#, F3_W);

        ------------------------------------------------------------------------
        report "TB : T4 - lectures a adresse non alignee (LB/LH/LBU/LHU)";
        do_load(16#0101#, F3_B);
        do_load(16#0102#, F3_H);
        do_load(16#0103#, F3_BU);
        do_load(16#0106#, F3_HU);

        ------------------------------------------------------------------------
        report "TB : T5 - 200 lectures aleatoires sur 4 MiB";
        for k in 1 to 200 loop
            rnd(r);
            do_load(to_integer(unsigned(r(21 downto 0))), F3_W);
        end loop;

        ------------------------------------------------------------------------
        report "TB : T6 - ecriture en flash : acquittee, ignoree";
        do_store(16#0010#, x"DEADBEEF");
        do_load (16#0010#, F3_W);

        ------------------------------------------------------------------------
        report "TB : T7 - reset du controleur alors que la flash est en mode continu (Q8)";
        check(cont_mode = '1', "T7 : la flash devrait etre en mode continu avant le reset");
        reset_and_first_load;
        c0 := cmd_count;
        rnd(r);
        do_load(to_integer(unsigned(r(21 downto 2))) * 4, F3_W);
        do_load(16#0040#, F3_W);
        check(cmd_count = c0, "T7 : commande EBh envoyee alors que la flash est en mode continu");

        ------------------------------------------------------------------------
        wait for 1 us;
        report "======== tb_qspi_flash : " & integer'image(n_acc) & " acces, "
               & integer'image(errs) & " erreur(s) TB, "
               & integer'image(model_errors) & " erreur(s) protocole flash ========";
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
