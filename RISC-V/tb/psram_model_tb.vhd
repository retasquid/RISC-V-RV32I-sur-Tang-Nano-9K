--------------------------------------------------------------------------------
-- psram_model_tb.vhd
-- Autotest du modele psram_model : un hote "ideal" pilote bit a bit
-- (SCLK 10 MHz, donnees changees SCLK bas, lecture au front montant) doit
-- passer sans aucune erreur ; puis des fautes volontaires doivent etre
-- detectees. Sert a valider le modele avant de s'en servir comme reference.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_psram_model is
end entity;

architecture sim of tb_psram_model is
    constant TH : time := 50 ns;   -- demi-periode SCLK

    signal ce_n     : std_logic := '1';
    signal sclk     : std_logic := '0';
    signal hdrv     : std_logic_vector(3 downto 0) := "ZZZZ";   -- pilotes de l'hote
    signal s0, s1   : std_logic;
    signal s2, s3   : std_logic;
    signal qpi_mode : std_logic;
    signal txn      : natural;
    signal laddr    : std_logic_vector(23 downto 0);
    signal nerr     : natural;
begin
    s0 <= hdrv(0); s1 <= hdrv(1); s2 <= hdrv(2); s3 <= hdrv(3);
    s0 <= 'H';     s1 <= 'H';     s2 <= 'H';     s3 <= 'H';

    u_psram : entity work.psram_model
        port map (
            ce_n => ce_n, sclk => sclk,
            sio0 => s0, sio1 => s1, sio2 => s2, sio3 => s3,
            qpi_mode => qpi_mode, txn_count => txn, last_addr => laddr, errors => nerr
        );

    process
        variable errs : natural := 0;
        variable e0   : natural;
        variable b    : std_logic_vector(7 downto 0);
        variable w    : std_logic_vector(31 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "SELFTEST : " & msg severity error;
            end if;
        end procedure;

        procedure cs_low  is begin ce_n <= '0'; wait for TH; end procedure;
        procedure cs_high is begin ce_n <= '1'; hdrv <= "ZZZZ"; wait for 2*TH; end procedure;

        -- Un coup d'horloge : SCLK est bas, les donnees viennent d'etre posees ;
        -- phase basse, front montant, phase haute, front descendant
        procedure pulse is
        begin
            wait for TH;
            sclk <= '1'; wait for TH;
            sclk <= '0';
        end procedure;

        -- Idem, mais echantillonne les lignes 1 ns avant le front montant
        procedure pulse_read(v : out std_logic_vector(3 downto 0)) is
        begin
            wait for TH - 1 ns;
            v := to_x01(s3 & s2 & s1 & s0);
            wait for 1 ns;
            sclk <= '1'; wait for TH;
            sclk <= '0';
        end procedure;

        procedure spi_byte(v : std_logic_vector(7 downto 0)) is
        begin
            for i in 7 downto 0 loop
                hdrv <= "ZZZ" & v(i);
                pulse;
            end loop;
        end procedure;

        procedure qpi_byte(v : std_logic_vector(7 downto 0)) is
        begin
            hdrv <= v(7 downto 4); pulse;
            hdrv <= v(3 downto 0); pulse;
        end procedure;

        procedure spi_read_byte(v : out std_logic_vector(7 downto 0)) is
            variable n : std_logic_vector(3 downto 0);
        begin
            hdrv <= "ZZZZ";
            for i in 7 downto 0 loop
                pulse_read(n);
                v(i) := n(1);
            end loop;
        end procedure;

        procedure qpi_read_byte(v : out std_logic_vector(7 downto 0)) is
            variable n : std_logic_vector(3 downto 0);
        begin
            hdrv <= "ZZZZ";
            pulse_read(n); v(7 downto 4) := n;
            pulse_read(n); v(3 downto 0) := n;
        end procedure;

        procedure qpi_addr(a : std_logic_vector(23 downto 0)) is
        begin
            qpi_byte(a(23 downto 16)); qpi_byte(a(15 downto 8)); qpi_byte(a(7 downto 0));
        end procedure;

    begin
        wait for 160 us;   -- > tPU

        -- Reset SPI 66h / 99h
        cs_low; spi_byte(x"66"); cs_high;
        cs_low; spi_byte(x"99"); cs_high;

        -- Read ID (9Fh) : MF = 0Dh, KGD = 5Dh
        cs_low; spi_byte(x"9F"); spi_byte(x"00"); spi_byte(x"00"); spi_byte(x"00");
        spi_read_byte(b); check(b = x"0D", "MF ID = " & to_hstring(b));
        spi_read_byte(b); check(b = x"5D", "KGD = " & to_hstring(b));
        cs_high;

        -- SPI Write 02h puis SPI Read 03h
        cs_low; spi_byte(x"02"); spi_byte(x"00"); spi_byte(x"01"); spi_byte(x"00");
        spi_byte(x"C3"); spi_byte(x"3C"); cs_high;
        cs_low; spi_byte(x"03"); spi_byte(x"00"); spi_byte(x"01"); spi_byte(x"00");
        spi_read_byte(b); check(b = x"C3", "SPI 03h octet 0 = " & to_hstring(b));
        spi_read_byte(b); check(b = x"3C", "SPI 03h octet 1 = " & to_hstring(b));
        cs_high;

        -- Passage en QPI
        cs_low; spi_byte(x"35"); cs_high;
        check(qpi_mode = '1', "35h n'a pas active le mode QPI");

        -- QPI Write 38h : DE AD BE EF @ 0x001234
        cs_low; qpi_byte(x"38"); qpi_addr(x"001234");
        qpi_byte(x"DE"); qpi_byte(x"AD"); qpi_byte(x"BE"); qpi_byte(x"EF"); cs_high;
        check(laddr = x"001234", "last_addr = " & to_hstring(laddr));

        -- QPI Read EBh, 6 wait
        cs_low; qpi_byte(x"EB"); qpi_addr(x"001234");
        hdrv <= "ZZZZ";
        for i in 1 to 6 loop pulse; end loop;
        for i in 0 to 3 loop
            qpi_read_byte(b);
            w(31 - 8*i downto 24 - 8*i) := b;
        end loop;
        cs_high;
        check(w = x"DEADBEEF", "QPI EBh = " & to_hstring(w));

        -- Lecture non alignee
        cs_low; qpi_byte(x"EB"); qpi_addr(x"001236");
        hdrv <= "ZZZZ";
        for i in 1 to 6 loop pulse; end loop;
        qpi_read_byte(b); check(b = x"BE", "QPI EBh @1236 = " & to_hstring(b));
        cs_high;

        -- Sortie du QPI
        cs_low; qpi_byte(x"F5"); cs_high;
        check(qpi_mode = '0', "F5h n'a pas desactive le mode QPI");

        check(nerr = 0, "le modele a signale " & integer'image(nerr) & " erreur(s) sur une sequence correcte");
        check(txn = 10, "txn_count = " & integer'image(txn) & " au lieu de 10");

        ------------------------------------------------------------------------
        -- Fautes volontaires : chacune doit incrementer 'errors'
        ------------------------------------------------------------------------
        report "SELFTEST : debut des fautes volontaires (erreurs PSRAM attendues)";
        cs_low; spi_byte(x"35"); cs_high;

        -- 1) nibble flottant pendant l'adresse
        e0 := nerr;
        cs_low; qpi_byte(x"38"); qpi_byte(x"00");
        hdrv <= "ZZZZ"; wait for 1 ns; pulse; pulse;
        qpi_byte(x"00"); qpi_byte(x"AA"); cs_high;
        check(nerr > e0, "nibble flottant non detecte");

        -- 2) tCPH : CE# remonte puis redescend apres 20 ns
        e0 := nerr;
        cs_low; qpi_byte(x"66"); ce_n <= '1'; wait for 20 ns;
        cs_low; qpi_byte(x"99"); cs_high;
        check(nerr > e0, "tCPH non detecte");
        -- le reset 66h/99h a remis la PSRAM en SPI : retour en QPI
        cs_low; spi_byte(x"35"); cs_high;
        check(qpi_mode = '1', "retour en QPI apres reset");

        -- 3) conflit de bus : l'hote pilote pendant la sortie de donnees
        e0 := nerr;
        cs_low; qpi_byte(x"EB"); qpi_addr(x"001234");
        hdrv <= "ZZZZ";
        for i in 1 to 6 loop pulse; end loop;
        hdrv <= "0000"; wait for 1 ns; pulse; pulse; pulse;
        cs_high;
        check(nerr > e0, "conflit de bus non detecte");

        -- 4) tCEM : CE# bas plus de 8 us
        e0 := nerr;
        cs_low; qpi_byte(x"EB"); qpi_addr(x"001234");
        hdrv <= "ZZZZ";
        for i in 1 to 100 loop pulse; end loop;   -- 100 x 100 ns > 8 us
        cs_high;
        check(nerr > e0, "tCEM non detecte");

        -- 5) commande inconnue
        e0 := nerr;
        cs_low; qpi_byte(x"77"); cs_high;
        check(nerr > e0, "commande inconnue non detectee");

        if errs = 0 then
            report "MODEL_SELFTEST: SUCCES";
        else
            report "MODEL_SELFTEST: ECHEC (" & integer'image(errs) & ")" severity error;
        end if;
        std.env.finish;
        wait;
    end process;
end architecture;
