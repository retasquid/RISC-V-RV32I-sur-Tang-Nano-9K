--------------------------------------------------------------------------------
-- flash_model_tb.vhd
-- Autotest du modele flash_model (GD25Q32C) : un hote "ideal" pilote bit a
-- bit (SCLK 10 MHz, donnees changees SCLK bas, lecture au front montant) doit
-- passer sans aucune erreur ; puis des fautes volontaires doivent etre
-- detectees. Sert a valider le modele avant de s'en servir comme reference.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_flash_model is
end entity;

architecture sim of tb_flash_model is
    constant TH : time := 50 ns;   -- demi-periode SCLK

    signal cs_n     : std_logic := '1';
    signal sclk     : std_logic := '0';
    signal hdrv     : std_logic_vector(3 downto 0) := "ZZZZ";   -- pilotes de l'hote
    signal s0, s1   : std_logic;
    signal s2, s3   : std_logic;
    signal cont     : std_logic;
    signal txn      : natural;
    signal ncmd     : natural;
    signal laddr    : std_logic_vector(23 downto 0);
    signal nerr     : natural;
begin
    s0 <= hdrv(0); s1 <= hdrv(1); s2 <= hdrv(2); s3 <= hdrv(3);
    s0 <= 'H';     s1 <= 'H';     s2 <= 'H';     s3 <= 'H';

    u_flash : entity work.flash_model
        port map (
            cs_n => cs_n, sclk => sclk,
            sio0 => s0, sio1 => s1, sio2 => s2, sio3 => s3,
            cont_mode => cont, txn_count => txn, cmd_count => ncmd,
            last_addr => laddr, errors => nerr
        );

    process
        variable errs : natural := 0;
        variable e0   : natural;
        variable b    : std_logic_vector(7 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                report "SELFTEST : " & msg severity error;
            end if;
        end procedure;

        procedure cs_low  is begin cs_n <= '0'; wait for TH; end procedure;
        procedure cs_high is begin cs_n <= '1'; hdrv <= "ZZZZ"; wait for 2*TH; end procedure;

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

        procedure quad_byte(v : std_logic_vector(7 downto 0)) is
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

        procedure quad_read_byte(v : out std_logic_vector(7 downto 0)) is
            variable n : std_logic_vector(3 downto 0);
        begin
            hdrv <= "ZZZZ";
            pulse_read(n); v(7 downto 4) := n;
            pulse_read(n); v(3 downto 0) := n;
        end procedure;

        -- Adresse quad + M7-0 + 4 dummy (la commande EBh est envoyee avant si besoin)
        procedure addr_mode_dummy(a : std_logic_vector(23 downto 0); m : std_logic_vector(7 downto 0)) is
        begin
            quad_byte(a(23 downto 16)); quad_byte(a(15 downto 8)); quad_byte(a(7 downto 0));
            quad_byte(m);
            hdrv <= "ZZZZ";
            for i in 1 to 4 loop pulse; end loop;
        end procedure;

        procedure check_bytes(a : natural; n : natural; what : string) is
        begin
            for i in 0 to n - 1 loop
                quad_read_byte(b);
                check(b = flash_pattern(a + i), what & " octet " & integer'image(i) & " = "
                      & to_hstring(b) & ", attendu " & to_hstring(flash_pattern(a + i)));
            end loop;
        end procedure;

    begin
        wait for 1.9 ms;   -- > tVSL

        -- Read ID (9Fh) : C8h 40h 16h
        cs_low; spi_byte(x"9F");
        spi_read_byte(b); check(b = x"C8", "MF ID = " & to_hstring(b));
        spi_read_byte(b); check(b = x"40", "ID15-8 = " & to_hstring(b));
        spi_read_byte(b); check(b = x"16", "ID7-0 = " & to_hstring(b));
        cs_high;

        -- SR2 (35h) : QE = 1
        cs_low; spi_byte(x"35"); spi_read_byte(b); cs_high;
        check(b = x"02", "SR2 = " & to_hstring(b));

        -- EBh, M = 00h (pas de mode continu)
        cs_low; spi_byte(x"EB"); addr_mode_dummy(x"000100", x"00");
        check_bytes(16#100#, 4, "EBh M=00");
        cs_high;
        check(cont = '0', "mode continu active avec M = 00h");
        check(laddr = x"000100", "last_addr = " & to_hstring(laddr));

        -- EBh, M = 20h -> mode continu
        cs_low; spi_byte(x"EB"); addr_mode_dummy(x"001234", x"20");
        check_bytes(16#1234#, 2, "EBh M=20");
        cs_high;
        check(cont = '1', "M = 20h n'a pas active le mode continu");
        check(ncmd = 2, "cmd_count = " & integer'image(ncmd) & " au lieu de 2");

        -- Lecture continue : adresse directement
        cs_low; addr_mode_dummy(x"00ABCD", x"20");
        check_bytes(16#ABCD#, 3, "lecture continue");
        cs_high;
        check(ncmd = 2, "cmd_count a augmente en mode continu");
        check(laddr = x"00ABCD", "last_addr continu = " & to_hstring(laddr));

        -- Sortie du mode continu : 8 coups a FFh sur SIO0-3
        cs_low; hdrv <= "1111"; for i in 1 to 8 loop pulse; end loop; cs_high;
        check(cont = '0', "CRMR n'a pas quitte le mode continu");

        -- CRMR hors mode continu = commande FFh sans effet
        cs_low; hdrv <= "1111"; for i in 1 to 8 loop pulse; end loop; cs_high;

        -- Reset 66h / 99h puis tRST
        cs_low; spi_byte(x"66"); cs_high;
        cs_low; spi_byte(x"99"); cs_high;
        wait for 35 us;
        cs_low; spi_byte(x"05"); spi_read_byte(b); cs_high;
        check(b = x"00", "SR1 = " & to_hstring(b));

        check(nerr = 0, "le modele a signale " & integer'image(nerr) & " erreur(s) sur une sequence correcte");
        check(txn = 10, "txn_count = " & integer'image(txn) & " au lieu de 10");

        ------------------------------------------------------------------------
        -- Fautes volontaires : chacune doit incrementer 'errors'
        ------------------------------------------------------------------------
        report "SELFTEST : debut des fautes volontaires (erreurs FLASH attendues)";

        -- 1) commande pendant tRST
        e0 := nerr;
        cs_low; spi_byte(x"66"); cs_high;
        cs_low; spi_byte(x"99"); cs_high;
        cs_low; spi_byte(x"05"); spi_read_byte(b); cs_high;
        check(nerr > e0, "commande pendant tRST non detectee");
        wait for 35 us;

        -- 2) nibble flottant pendant l'adresse
        e0 := nerr;
        cs_low; spi_byte(x"EB"); quad_byte(x"00");
        hdrv <= "ZZZZ"; wait for 1 ns; pulse; pulse;
        quad_byte(x"00"); quad_byte(x"00");
        hdrv <= "ZZZZ"; for i in 1 to 4 loop pulse; end loop;
        cs_high;
        check(nerr > e0, "nibble flottant non detecte");

        -- 3) conflit de bus pendant la sortie de donnees
        e0 := nerr;
        cs_low; spi_byte(x"EB"); addr_mode_dummy(x"000010", x"00");
        hdrv <= "0000"; wait for 1 ns; pulse; pulse;
        cs_high;
        check(nerr > e0, "conflit de bus non detecte");

        -- 4) commande SPI envoyee alors que la flash est en mode continu (Q8)
        cs_low; spi_byte(x"EB"); addr_mode_dummy(x"000020", x"20");
        check_bytes(16#20#, 4, "EBh M=20 (faute 4)");
        cs_high;
        e0 := nerr;
        cs_low; spi_byte(x"66"); cs_high;
        check(nerr > e0, "66h en mode continu non detecte");
        check(cont = '0', "le 66h aurait du etre vu comme M5-4 /= 10");

        -- 5) commande non supportee (page program)
        e0 := nerr;
        cs_low; spi_byte(x"02"); cs_high;
        check(nerr > e0, "commande non supportee non detectee");

        -- 6) tSHSL : CS# haut 10 ns
        e0 := nerr;
        cs_low; spi_byte(x"FF"); cs_n <= '1'; wait for 10 ns;
        cs_low; spi_byte(x"FF"); cs_high;
        check(nerr > e0, "tSHSL non detecte");

        -- 7) adresse tronquee
        e0 := nerr;
        cs_low; spi_byte(x"EB"); quad_byte(x"00"); cs_high;
        check(nerr > e0, "adresse tronquee non detectee");

        if errs = 0 then
            report "MODEL_SELFTEST: SUCCES";
        else
            report "MODEL_SELFTEST: ECHEC (" & integer'image(errs) & ")" severity error;
        end if;
        std.env.finish;
        wait;
    end process;
end architecture;
