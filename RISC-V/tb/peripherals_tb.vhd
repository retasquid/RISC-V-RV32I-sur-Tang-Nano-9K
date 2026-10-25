--------------------------------------------------------------------------------
-- peripherals_tb.vhd
-- Testbench auto-verifiant de peripherals (GPIO + UART) avec le vrai clkDiv et
-- le maitre de bus de tb_pkg (rd/we tenus ~17 cycles, comme uc) :
--   T1 GPIO : direction, sorties, entrees resynchronisees, pas de conflit ni
--      de boucle combinatoire (B2)
--   T2 UART TX : une ecriture = exactement une trame, busy vu juste apres
--   T3 UART RX : chaque octet recu est vu EXACTEMENT une fois avec bit 8 = 1 (B1)
--   T4 adresse non decodee : acquittee, lit 0
--   T5 reset : registres remis a zero
--   T6/T7 RX apres reset : pas d'octet perime, reception qui repart meme si
--      un octet n'avait pas ete lu (bug vu sur carte)
--   T8 timer 64 bits : chaque lecture LO puis HI donne exactement le nombre
--      de cycles ecoules, y compris quand la retenue tombe entre les deux
--      lectures (8 dephasages) ; microsecondes a +-1 pres
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/peripherals.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_peripherals is
    generic (
        -- true : maitre a pleine vitesse (comme uc V2) ; false : 1 pas / 17
        -- cycles (ancien rythme enCore, requetes tenues longtemps)
        FAST : boolean := true
    );
end entity;

architecture sim of tb_peripherals is

    constant BAUD      : natural := 115200;
    constant BIT_T     : time    := 1 sec / BAUD;
    -- phase_inc = baud * 2^32 / 31,5 MHz (comme serialInit dans periph.h)
    constant PHASE_INC : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(natural(real(BAUD) * 4294967296.0 / 31.5e6), 32));

    constant A_GPIO : natural := 16#10#;
    constant A_DIR  : natural := 16#14#;
    constant A_TX   : natural := 16#18#;
    constant A_RX   : natural := 16#1C#;
    constant A_BAUD : natural := 16#20#;
    constant A_NONE : natural := 16#2C#;   -- non decodee
    constant A_TLO  : natural := 16#30#;
    constant A_THI  : natural := 16#34#;
    constant A_ULO  : natural := 16#38#;
    constant A_UHI  : natural := 16#3C#;
    constant TB_CLK_HZ : natural := 31_500_000;   -- 31,5 cycles par us : non entier
    -- Le timer demarre pres de la retenue des bits 31..0 (4096 cycles)
    constant TIME_INIT : std_logic_vector(63 downto 0) := x"00000000FFFFF000";

    signal clk_sys      : std_logic := '0';
    signal rst        : std_logic := '1';
    signal enSlow     : std_logic;
    signal en         : std_logic;
    signal enMem      : std_logic;
    signal sim_done   : boolean := false;

    signal m          : bus_m_t := BUS_M_IDLE;
    signal din_bus    : std_logic_vector(31 downto 0);
    signal rdy        : std_logic;
    signal cs         : std_logic;

    signal gpio       : std_logic_vector(31 downto 0);
    signal gpio_tb    : std_logic_vector(31 downto 0) := (others => 'Z');
    signal uart_tx    : std_logic;
    signal uart_rx    : std_logic := '1';

    -- Moniteur TX
    type byte_arr is array (natural range <>) of std_logic_vector(7 downto 0);
    signal tx_bytes   : byte_arr(0 to 15);
    signal tx_count   : natural := 0;
    signal tx_errs    : natural := 0;

    -- Emetteur RX pilote par le process de stimuli
    signal rx_queue   : byte_arr(0 to 7);
    signal rx_len     : natural := 0;
    signal rx_go      : boolean := false;
    signal rx_done    : boolean := true;

begin

    clk_sys <= not clk_sys after CLK_SYS_PERIOD / 2 when not sim_done;
    en    <= '1' when FAST else enSlow;

    cs <= '1' when m.adr(31 downto 24) = x"00" else '0';

    -- Broches GPIO : le TB pilote fort les entrees, tirage faible ailleurs
    gpio <= gpio_tb;
    gpio <= (others => 'L');

    u_div : entity work.clkDiv
        port map (clk27 => clk_sys, enCore => enSlow, enMem => enMem);

    dut : entity work.peripherals
        generic map (
            CLK_HZ    => TB_CLK_HZ,
            TIME_INIT => TIME_INIT
        )
        port map (
            dout     => din_bus,
            din      => m.dout,
            adr      => m.adr(9 downto 2),
            rdy      => rdy,
            clk      => clk_sys,
            rst      => rst,
            cs       => cs,
            we       => m.we,
            rd       => m.rd,
            GPIO0    => gpio,
            clk_xtal => clk_sys,
            uart_tx  => uart_tx,
            uart_rx  => uart_rx
        );

    -- Moniteur des trames emises (8N1)
    tx_mon : process
        variable b : std_logic_vector(7 downto 0);
    begin
        wait until falling_edge(uart_tx);
        wait for BIT_T / 2;
        if uart_tx /= '0' then
            tx_errs <= tx_errs + 1;
            report "TX : faux bit de start" severity error;
        else
            for i in 0 to 7 loop
                wait for BIT_T;
                b(i) := uart_tx;
            end loop;
            wait for BIT_T;
            if uart_tx /= '1' then
                tx_errs <= tx_errs + 1;
                report "TX : bit de stop absent" severity error;
            end if;
            if tx_count <= tx_bytes'high then
                tx_bytes(tx_count) <= b;
            end if;
            tx_count <= tx_count + 1;
        end if;
    end process;

    -- Emetteur de trames vers uart_rx
    rx_drv : process
    begin
        wait until rx_go;
        rx_done <= false;
        for k in 0 to rx_len - 1 loop
            uart_rx <= '0'; wait for BIT_T;
            for i in 0 to 7 loop
                uart_rx <= rx_queue(k)(i); wait for BIT_T;
            end loop;
            uart_rx <= '1'; wait for BIT_T;
        end loop;
        rx_done <= true;   -- rx_go est deja retombe (stim le baisse des le debut)
    end process;

    stim : process
        constant TIMEOUT : natural := 50;
        variable errs    : natural := 0;
        variable n_acc   : natural := 0;
        variable r       : std_logic_vector(31 downto 0);
        variable n       : natural;
        -- T8
        variable t8_lo, t8_hi     : std_logic_vector(31 downto 0);
        variable t8_v, t8_prev    : unsigned(63 downto 0);
        variable t8_t, t8_tprev   : time := 0 ns;
        variable t8_after, t8_n   : natural;

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                if errs <= 40 then
                    report "TB @" & time'image(now) & " : " & msg severity error;
                end if;
            end if;
        end procedure;

        procedure access_io(is_write : boolean; a : natural; val : std_logic_vector(31 downto 0);
                            v : out std_logic_vector(31 downto 0)) is
            variable ad : std_logic_vector(31 downto 0) := std_logic_vector(to_unsigned(a, 32));
            variable ok : boolean;
            variable rd : std_logic_vector(31 downto 0);
        begin
            bus_fetch(clk_sys, en, m);
            bus_cycle(clk_sys, en, rdy, din_bus, m, is_write, ad, val, "1111", rd, ok, TIMEOUT);
            n_acc := n_acc + 1;
            check(ok, "pas de rdy pour l'acces a 0x" & to_hstring(ad));
            v := to_x01(rd);
        end procedure;

        procedure wr(a : natural; val : std_logic_vector(31 downto 0)) is
            variable dummy : std_logic_vector(31 downto 0);
        begin
            access_io(true, a, val, dummy);
        end procedure;

        procedure rd(a : natural; v : out std_logic_vector(31 downto 0)) is
        begin
            access_io(false, a, x"00000000", v);
        end procedure;

        procedure expect(a : natural; exp : std_logic_vector(31 downto 0); what : string) is
            variable v : std_logic_vector(31 downto 0);
        begin
            rd(a, v);
            check(v = exp, what & " : lu 0x" & to_hstring(v) & ", attendu 0x" & to_hstring(exp));
        end procedure;

        -- Envoie un octet par l'UART (polling de busy comme serialWrite)
        procedure uart_send(b : std_logic_vector(7 downto 0)) is
            variable v : std_logic_vector(31 downto 0);
            variable k : natural := 0;
        begin
            wr(A_TX, x"000000" & b);
            rd(A_TX, v);
            check(v(0) = '1', "TX : busy pas vu juste apres l'ecriture");
            while v(0) = '1' and k < 2000 loop
                rd(A_TX, v);
                k := k + 1;
            end loop;
            check(k < 2000, "TX : busy ne retombe jamais");
        end procedure;

        -- Lance l'envoi de 'bytes' sur uart_rx et lit RX en boucle comme
        -- serialRead : chaque octet doit etre vu une et une seule fois
        procedure uart_receive(bytes : byte_arr) is
            variable v     : std_logic_vector(31 downto 0);
            variable got   : natural := 0;
            variable extra : natural := 0;
        begin
            for i in bytes'range loop
                rx_queue(i - bytes'low) <= bytes(i);
            end loop;
            rx_len <= bytes'length;
            rx_go  <= true;
            wait until not rx_done;
            rx_go  <= false;
            while not rx_done loop
                rd(A_RX, v);
                if v(8) = '1' then
                    if got < bytes'length then
                        check(v(7 downto 0) = bytes(bytes'low + got), "RX : octet " & integer'image(got)
                              & " = 0x" & to_hstring(v(7 downto 0)) & ", attendu 0x"
                              & to_hstring(bytes(bytes'low + got)));
                    end if;
                    got := got + 1;
                end if;
            end loop;
            -- Encore quelques lectures : le dernier octet, puis plus rien
            for k in 1 to 100 loop
                rd(A_RX, v);
                if v(8) = '1' then
                    if got < bytes'length then
                        check(v(7 downto 0) = bytes(bytes'low + got), "RX : dernier octet = 0x"
                              & to_hstring(v(7 downto 0)));
                    end if;
                    got := got + 1;
                end if;
            end loop;
            check(got = bytes'length, "RX : " & integer'image(got) & " octet(s) vu(s) avec bit 8 = 1 au lieu de "
                  & integer'image(bytes'length));
            check(v(31 downto 9) = (31 downto 9 => '0'), "RX : bits 31..9 non nuls");
        end procedure;

    begin
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
        rst <= '0';

        ------------------------------------------------------------------------
        report "TB : T1 - GPIO";
        gpio_tb <= x"A5C3" & (15 downto 0 => 'Z');
        expect(A_DIR, x"00000000", "DIR apres reset");
        expect(A_GPIO, x"A5C30000", "GPIO en entree");
        wr(A_DIR, x"0000FFFF");
        wr(A_GPIO, x"12345678");
        check(to_x01(gpio) = x"A5C35678", "broches GPIO = 0x" & to_hstring(to_x01(gpio))
              & " (conflit ou sortie absente)");
        expect(A_GPIO, x"A5C35678", "GPIO sorties + entrees");
        expect(A_DIR, x"0000FFFF", "DIR relu");
        gpio_tb <= x"5A3C" & (15 downto 0 => 'Z');
        expect(A_GPIO, x"5A3C5678", "GPIO apres changement des entrees");
        wr(A_GPIO, x"FFFF0001");
        check(to_x01(gpio(15 downto 0)) = x"0001", "sorties GPIO apres 2e ecriture = 0x"
              & to_hstring(to_x01(gpio(15 downto 0))));
        wr(A_DIR, x"00000000");
        check(to_x01(gpio(15 downto 0)) = x"0000", "GPIO pas relachees apres DIR = 0");
        expect(A_GPIO, x"5A3C0000", "GPIO toutes en entree");

        ------------------------------------------------------------------------
        report "TB : T2 - UART TX";
        wr(A_BAUD, PHASE_INC);
        expect(A_BAUD, PHASE_INC, "BAUD relu");
        uart_send(x"55");
        uart_send(x"4F");
        uart_send(x"4B");
        wait for 2 * BIT_T;
        check(tx_count = 3, "TX : " & integer'image(tx_count) & " trame(s) au lieu de 3");
        if tx_count >= 3 then
            check(tx_bytes(0) = x"55" and tx_bytes(1) = x"4F" and tx_bytes(2) = x"4B",
                  "TX : octets 0x" & to_hstring(tx_bytes(0)) & " 0x" & to_hstring(tx_bytes(1))
                  & " 0x" & to_hstring(tx_bytes(2)) & " au lieu de 55 4F 4B");
        end if;
        check(tx_errs = 0, "TX : erreur de trame");

        ------------------------------------------------------------------------
        report "TB : T3 - UART RX (chaque octet vu exactement une fois)";
        expect(A_RX, x"00000000", "RX sans octet recu");
        uart_receive((0 => x"3C"));
        uart_receive((x"11", x"A2", x"33", x"F4"));

        ------------------------------------------------------------------------
        report "TB : T4 - adresse non decodee";
        expect(A_NONE, x"00000000", "lecture 0x3C");
        wr(A_NONE, x"FFFFFFFF");
        expect(A_DIR, x"00000000", "DIR apres ecriture a une adresse non decodee");

        ------------------------------------------------------------------------
        report "TB : T5 - reset";
        wr(A_DIR, x"000000FF");
        wait until rising_edge(clk_sys);
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
        rst <= '0';
        expect(A_DIR, x"00000000", "DIR apres reset");
        expect(A_BAUD, x"00000000", "BAUD apres reset");
        check(to_x01(gpio(15 downto 0)) = x"0000", "GPIO pilotees apres reset");

        ------------------------------------------------------------------------
        -- Bug vu sur carte : apres un reset bouton, serialRead sortait tout de
        -- suite car RX relisait le '\r' de la session precedente (bit 8 = 0)
        report "TB : T6 - RX apres consommation et apres reset (pas d'octet perime)";
        wr(A_BAUD, PHASE_INC);
        uart_receive((0 => x"0D"));
        expect(A_RX, x"00000000", "RX relu apres consommation du '\r'");
        wait until rising_edge(clk_sys);
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
        rst <= '0';
        wr(A_BAUD, PHASE_INC);
        expect(A_RX, x"00000000", "RX apres reset (octet de la session precedente)");

        -- Octet recu et jamais lu (programme termine), puis reset : la
        -- reception doit repartir
        report "TB : T7 - octet non lu au moment du reset, puis reception";
        rx_queue(0) <= x"78";
        rx_len <= 1;
        rx_go  <= true;
        wait until not rx_done;
        rx_go  <= false;
        wait until rx_done;
        wait for 2 * BIT_T;
        wait until rising_edge(clk_sys);
        rst <= '1';
        for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
        rst <= '0';
        wr(A_BAUD, PHASE_INC);
        expect(A_RX, x"00000000", "RX apres reset (octet non lu avant le reset)");
        uart_receive((x"79", x"0D"));

        ------------------------------------------------------------------------
        report "TB : T8 - timer 64 bits (cycles, microsecondes)";
        for ph in 0 to 7 loop
            wait until rising_edge(clk_sys);
            rst <= '1';
            for i in 1 to 20 loop wait until rising_edge(clk_sys); end loop;
            rst <= '0';
            for i in 1 to ph loop wait until rising_edge(clk_sys); end loop;
            t8_prev   := (others => '0');
            t8_after  := 0;
            t8_n      := 0;
            -- Lectures LO puis HI jusqu'a 3 paires apres la retenue
            while t8_after < 3 and t8_n < 3000 loop
                rd(A_TLO, t8_lo);
                t8_t := now;
                rd(A_THI, t8_hi);
                t8_v := unsigned(std_logic_vector'(t8_hi & t8_lo));
                if t8_n = 0 then
                    check(t8_v >= unsigned(TIME_INIT) and t8_v < unsigned(TIME_INIT) + 200,
                          "T8 : 1re lecture apres reset = 0x" & to_hstring(t8_v));
                else
                    check(t8_v - t8_prev = to_unsigned((t8_t - t8_tprev + CLK_SYS_PERIOD / 2) / CLK_SYS_PERIOD, 64),
                          "T8 (dephasage " & integer'image(ph) & ") : 0x" & to_hstring(t8_prev)
                          & " puis 0x" & to_hstring(t8_v) & ", " & integer'image((t8_t - t8_tprev + CLK_SYS_PERIOD / 2) / CLK_SYS_PERIOD)
                          & " cycles ecoules");
                end if;
                if t8_hi /= x"00000000" then
                    t8_after := t8_after + 1;
                end if;
                t8_prev  := t8_v;
                t8_tprev := t8_t;
                t8_n     := t8_n + 1;
            end loop;
            check(t8_after >= 3, "T8 : la retenue vers TIME_HI n'a jamais ete vue");
        end loop;
        -- Microsecondes : 31500 cycles a 31,5 MHz = 1 ms
        rd(A_ULO, t8_lo);
        t8_t := now;
        rd(A_UHI, t8_hi);
        t8_prev := unsigned(std_logic_vector'(t8_hi & t8_lo));
        for i in 1 to 31500 loop wait until rising_edge(clk_sys); end loop;
        rd(A_ULO, t8_lo);
        t8_tprev := now;
        rd(A_UHI, t8_hi);
        t8_v := unsigned(std_logic_vector'(t8_hi & t8_lo));
        n := (t8_tprev - t8_t + CLK_SYS_PERIOD / 2) / CLK_SYS_PERIOD;      -- cycles entre les 2 lectures
        check(abs(to_integer(t8_v - t8_prev) - n * 1000 / (TB_CLK_HZ / 1000)) <= 1,
              "T8 : " & integer'image(to_integer(t8_v - t8_prev)) & " us comptees pour "
              & integer'image(n) & " cycles");
        check(t8_hi = x"00000000", "T8 : USEC_HI = 0x" & to_hstring(t8_hi));

        ------------------------------------------------------------------------
        wait for 1 us;
        report "======== tb_peripherals : " & integer'image(n_acc) & " acces, "
               & integer'image(errs) & " erreur(s) ========";
        if errs = 0 then
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
        wait for 50 ms;
        report "TB_RESULT: ECHEC (watchdog 50 ms)" severity failure;
        wait;
    end process;

end architecture;
