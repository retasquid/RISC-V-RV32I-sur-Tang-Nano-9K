--------------------------------------------------------------------------------
-- flash_cache_tb.vhd
-- Testbench auto-verifiant du cache flash (flash_cache, qui contient
-- qspi_flash + qspi_master) avec le modele GD25Q32C (flash_model), rempli
-- avec flash_pattern (tb_pkg) : le TB connait chaque octet. Maitre de bus au
-- rythme de uc (rd tombe au front ou rdy est vu, un pas a 0 entre deux
-- requetes).
--
-- Verifie la donnee de chaque lecture, et en mode FAST la latence (en
-- cycles, du front ou rd monte au front ou rdy est vu) :
--   T1 reset puis 1re lecture (init flash comprise)
--   T2 ligne lue en sequence (mots 0..7), puis relue : 8 hits en 2 cycles
--   T3 conflit : deux adresses a 8 KiB d'ecart se chassent (defauts)
--   T4 ligne partielle : depart au mot 5, puis mots 2..4 relus (defaut), les
--      mots deja valides restent des hits
--   T5 remplissage interrompu : un saut vers une autre ligne pendant le
--      remplissage est servi sans attendre la fin de la ligne
--   T6 hit sur une autre ligne pendant un remplissage
--   T7 400 lectures aleatoires sur 4 MiB, puis relecture des 64 dernieres
--   T8 ecriture en flash : acquittee, ignoree
--   T9 reset : le cache est vide (la 1re lecture est un defaut)
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/flash_cache.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_flash_cache is
    generic (
        -- true : maitre a pleine vitesse (comme uc) ; false : un pas tous les 17
        -- cycles (requetes tenues longtemps), latences non verifiees
        FAST     : boolean := true;
        -- SCLK = clk / SCLK_DIV (generic du controleur)
        SCLK_DIV : positive := 2
    );
end entity;

architecture sim of tb_flash_cache is

    constant MEM_BITS : natural := 16;   -- flash simulee : 64 KiB (alias au-dela)

    signal clk_sys      : std_logic := '0';
    signal rst          : std_logic := '1';
    signal enSlow, enMem : std_logic;
    signal en           : std_logic;
    signal sim_done     : boolean := false;

    signal m            : bus_m_t := BUS_M_IDLE;
    signal din_bus      : std_logic_vector(31 downto 0);
    signal rdy          : std_logic;
    signal cs           : std_logic;

    signal flash_cs_n   : std_logic;
    signal flash_clk    : std_logic;
    signal sio0, sio1   : std_logic;
    signal sio2, sio3   : std_logic;

    signal cont_mode    : std_logic;
    signal txn_count    : natural;
    signal cmd_count    : natural;
    signal last_addr    : std_logic_vector(23 downto 0);
    signal model_errors : natural;

begin

    clk_sys <= not clk_sys after CLK_SYS_PERIOD / 2 when not sim_done;
    en      <= '1' when FAST else enSlow;

    sio0 <= 'H';
    sio1 <= 'H';
    sio2 <= 'H';
    sio3 <= 'H';

    cs <= '1' when m.adr(31 downto 24) = x"40" else '0';

    u_div : entity work.clkDiv
        port map (
            clk27  => clk_sys,
            enCore => enSlow,
            enMem  => enMem
        );

    dut : entity work.flash_cache
        generic map (
            A_WIDTH  => 22,
            SCLK_DIV => SCLK_DIV
        )
        port map (
            dout       => din_bus,
            adr        => m.adr(21 downto 0),
            cs         => cs,
            rd         => m.rd,
            wr         => m.we,
            rdy        => rdy,
            clk        => clk_sys,
            rst        => rst,
            clkQspiEn  => '1',
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
        constant TIMEOUT      : natural := 2000;    -- pas de uc
        constant TIMEOUT_INIT : natural := 100000;  -- 1er acces apres reset (init ~2 ms)
        constant HIT_LAT      : natural := 2;
        constant LINE         : natural := 32;
        constant CACHE        : natural := 8192;

        variable errs    : natural := 0;
        variable n_acc   : natural := 0;
        variable n_hit   : natural := 0;
        variable dead    : boolean := false;
        variable seed    : unsigned(31 downto 0) := x"2545F491";
        variable r       : std_logic_vector(31 downto 0);
        variable lat     : natural;
        variable lat_fresh, lat_abort : natural;
        variable hist    : natural;
        type adr_arr_t is array (0 to 63) of natural;
        variable last64  : adr_arr_t;

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

        function expected(o : natural) return std_logic_vector is
            constant al : natural := o - (o mod 4);
            variable e  : std_logic_vector(31 downto 0);
        begin
            for i in 0 to 3 loop
                e(8*i + 7 downto 8*i) := flash_pattern((al + i) mod 2**MEM_BITS);
            end loop;
            return e;
        end function;

        -- Une requete comme uc : un pas avec rd = 0 (S_GAP / S_DECODE), rd
        -- monte, attente de rdy ; lat = nombre de cycles de clk entre le front
        -- ou rd monte et celui ou rdy est vu
        procedure bus_req(o : natural; wr : boolean; l : out natural;
                         tmo : natural := TIMEOUT) is
            variable a     : std_logic_vector(31 downto 0) := std_logic_vector(x"40000000" + to_unsigned(o, 32));
            variable n     : natural := 0;
            variable steps : natural := 0;
            variable got   : std_logic_vector(31 downto 0);
        begin
            l := 0;
            if dead then return; end if;
            wait_tick(clk_sys, en);
            m.adr  <= a;
            m.dout <= x"DEADBEEF";
            m.wenb <= "1111";
            if wr then m.we <= '1'; else m.rd <= '1'; end if;
            loop
                wait until rising_edge(clk_sys);
                n := n + 1;
                if en = '1' then
                    if rdy = '1' then
                        got  := din_bus;
                        m.rd <= '0';
                        m.we <= '0';
                        exit;
                    end if;
                    steps := steps + 1;
                    if steps >= tmo then
                        m.rd <= '0';
                        m.we <= '0';
                        check(false, "acces @0x" & to_hstring(a) & " : pas de rdy");
                        dead := true;
                        return;
                    end if;
                end if;
            end loop;
            n_acc := n_acc + 1;
            l := n;
            if n = HIT_LAT then n_hit := n_hit + 1; end if;
            if not wr then
                check(got = expected(o), "lecture @0x" & to_hstring(a) & " : lu 0x" & to_hstring(got)
                      & ", attendu 0x" & to_hstring(expected(o)));
            end if;
        end procedure;

        procedure rd_hit(o : natural; what : string) is
            variable l : natural;
        begin
            bus_req(o, false, l);
            if FAST then
                check(l = HIT_LAT, what & " @0x" & to_hstring(to_unsigned(o, 24)) & " : hit attendu, latence "
                      & integer'image(l) & " cycles");
            end if;
        end procedure;

        procedure rd_miss(o : natural; what : string) is
            variable l : natural;
        begin
            bus_req(o, false, l);
            if FAST then
                check(l > HIT_LAT, what & " @0x" & to_hstring(to_unsigned(o, 24)) & " : defaut attendu, latence "
                      & integer'image(l) & " cycles");
            end if;
        end procedure;

        -- Laisse finir le remplissage en fond (8 mots au plus)
        procedure settle is
        begin
            for i in 1 to 600 loop wait until rising_edge(clk_sys); end loop;
        end procedure;

        procedure do_reset is
        begin
            wait until rising_edge(clk_sys);
            rst <= '1';
            for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
            rst <= '0';
        end procedure;

    begin
        m <= BUS_M_IDLE;
        do_reset;

        ------------------------------------------------------------------------
        report "TB : T1 - reset puis 1re lecture (attend la fin de l'init flash)";
        bus_req(16#0100#, false, lat, TIMEOUT_INIT);
        report "TB : 1re lecture servie en " & integer'image(lat) & " cycles";
        settle;

        ------------------------------------------------------------------------
        report "TB : T2 - ligne lue en sequence puis relue (hits)";
        for w in 0 to 7 loop
            bus_req(16#0400# + 4*w, false, lat);
            if w = 0 then
                lat_fresh := lat;
                report "TB : defaut sur une ligne neuve : " & integer'image(lat) & " cycles";
            elsif w = 1 then
                report "TB : mot suivant pendant le remplissage : " & integer'image(lat) & " cycles";
            end if;
        end loop;
        for w in 0 to 7 loop
            rd_hit(16#0400# + 4*w, "T2 relecture");
        end loop;
        rd_hit(16#0100#, "T2 ligne de T1");

        ------------------------------------------------------------------------
        report "TB : T3 - conflit : deux adresses a 8 KiB d'ecart";
        for k in 1 to 4 loop
            rd_miss(16#0400# + CACHE, "T3 ligne B");
            rd_miss(16#0400#,         "T3 ligne A");
        end loop;
        settle;
        -- La ligne A est complete ; B la chasse : ses autres mots ne doivent pas
        -- etre pris pour valides (donnees de A) avant d'avoir ete lus
        rd_miss(16#0400# + CACHE + 12, "T3 ligne B, mot 3");
        bus_req(16#0400# + CACHE + 16, false, lat);
        bus_req(16#0400# + CACHE + 28, false, lat);
        settle;
        rd_miss(16#0400# + CACHE, "T3 ligne B, mot 0 (avant le depart)");
        rd_miss(16#0400#,         "T3 ligne A rechargee");
        settle;
        rd_hit(16#0404#, "T3 mot de la ligne A, remplie en fond");

        ------------------------------------------------------------------------
        report "TB : T4 - ligne partielle (depart au mot 5)";
        rd_miss(16#0800# + 20, "T4 mot 5");
        rd_hit (16#0800# + 20, "T4 mot 5 relu");
        settle;
        rd_miss(16#0800# + 8,  "T4 mot 2 (avant le depart)");
        settle;
        for w in 2 to 7 loop
            rd_hit(16#0800# + 4*w, "T4 mots 2..7");
        end loop;
        rd_miss(16#0800#,      "T4 mot 0 (jamais rempli)");
        settle;

        ------------------------------------------------------------------------
        report "TB : T5 - saut pendant un remplissage";
        rd_miss(16#0C00# + 4, "T5 mot 1 d'une ligne neuve");
        bus_req(16#1000#, false, lat_abort);
        report "TB : saut servi en " & integer'image(lat_abort) & " cycles (defaut seul : "
               & integer'image(lat_fresh) & ")";
        if FAST then
            check(lat_abort < lat_fresh + lat_fresh / 2,
                  "T5 : le saut attend la fin du remplissage (" & integer'image(lat_abort) & " cycles)");
        end if;
        -- La ligne interrompue reste correcte : mots valides en hit, les autres relus
        rd_hit(16#0C00# + 4, "T5 mot 1 deja recu");
        bus_req(16#0C00# + 28, false, lat);
        settle;

        ------------------------------------------------------------------------
        report "TB : T6 - hit sur une autre ligne pendant un remplissage";
        rd_miss(16#1400#, "T6 mot 0 d'une ligne neuve");
        rd_hit (16#0404#, "T6 ligne deja en cache");
        rd_hit (16#0400# + 28, "T6 ligne deja en cache");
        bus_req(16#1400# + 28, false, lat);
        rd_hit(16#1400# + 12, "T6 ligne remplie en fond");
        settle;

        ------------------------------------------------------------------------
        report "TB : T7 - 400 lectures aleatoires sur 4 MiB, puis relecture";
        for k in 0 to 399 loop
            rnd(r);
            bus_req(to_integer(unsigned(r(21 downto 2))) * 4, false, lat);
            if k >= 336 then last64(k - 336) := to_integer(unsigned(r(21 downto 2))) * 4; end if;
        end loop;
        settle;
        -- Relecture : chaque adresse est soit un hit, soit chassee par une
        -- autre de la liste ayant le meme index ; la donnee doit etre juste
        hist := n_hit;
        for k in 0 to 63 loop
            bus_req(last64(k), false, lat);
        end loop;
        report "TB : relecture des 64 dernieres : " & integer'image(n_hit - hist) & " hits";
        if FAST then
            check(n_hit - hist >= 40, "T7 : trop peu de hits a la relecture");
        end if;

        ------------------------------------------------------------------------
        report "TB : T8 - ecriture en flash : acquittee, ignoree";
        bus_req(16#0400#, true, lat);
        rd_hit(16#0400#, "T8 apres ecriture");

        ------------------------------------------------------------------------
        report "TB : T9 - reset : cache vide";
        do_reset;
        bus_req(16#0400#, false, lat, TIMEOUT_INIT);
        if FAST then
            check(lat > 1000, "T9 : 1re lecture apres reset servie en " & integer'image(lat)
                  & " cycles : le cache n'a pas ete vide (ou l'init flash sautee)");
        end if;
        rd_hit (16#0400#, "T9 relecture");

        ------------------------------------------------------------------------
        wait for 1 us;
        report "======== tb_flash_cache : " & integer'image(n_acc) & " acces dont "
               & integer'image(n_hit) & " hits, " & integer'image(errs) & " erreur(s) TB, "
               & integer'image(model_errors) & " erreur(s) protocole flash ========";
        if errs = 0 and model_errors = 0 and not dead then
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
        wait for 200 ms;
        report "TB_RESULT: ECHEC (watchdog 200 ms)" severity failure;
        wait;
    end process;

end architecture;
