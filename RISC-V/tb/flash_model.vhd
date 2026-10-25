--------------------------------------------------------------------------------
-- flash_model.vhd
-- Modele comportemental (simulation uniquement) de la flash SPI GigaDevice
-- GD25Q32C (32 Mbit), sous-ensemble utilise par qspi_flash. QE = 1 suppose
-- (bit S9 non volatile, deja positionne par le flasher) : WP#/HOLD# inactifs.
--
-- Commandes supportees (mode SPI, commande sur SIO0) :
--   EBh   Quad I/O Fast Read : adresse quad (6 coups), M7-0 (2 coups),
--         4 dummy, donnees quad. M5-4 = "10" -> mode continu : la
--         transaction suivante commence directement par l'adresse.
--   66h / 99h  reset logiciel (99h doit suivre immediatement 66h), tRST
--   FFh   sans effet hors mode continu (sortie du mode continu = CRMR)
--   9Fh   Read ID (C8h 40h 16h), 05h / 35h  lecture SR1 / SR2
-- Sortie du mode continu (CRMR) : une transaction "continue" dont les bits
-- M5-4 /= "10" (8 coups a FFh) ; CS# peut remonter pendant les dummy.
--
-- Verifications (chaque violation incremente 'errors') :
--   * CS# active avant tVSL = 1.8 ms apres la mise sous tension
--   * commande pendant tRST apres un reset 66h/99h
--   * SCLK pas bas a la descente de CS# (mode SPI 0 attendu)
--   * tSHSL, tSLCH, tCHSH, setup/hold des entrees (tDVCH / tCHDX)
--   * ligne non pilotee (Z, H, X...) echantillonnee en phase d'entree
--   * conflit de bus pendant que la flash sort des donnees
--   * commande inconnue, commande/adresse/mode tronques par CS#,
--     lecture continue abandonnee pendant les dummy
--
-- Contenu : 2**MEM_ADDR_BITS octets (adresses plus hautes repliees).
--   INIT_FILE = "" : octet a l'adresse a = flash_pattern(a) (tb_pkg)
--   sinon fichier texte, un mot 32 bits hexa par ligne (little endian),
--   mot 0 = adresse flash 0 (sortie de elf2rom.py --format hex).
-- 'last_addr' donne l'adresse 24 bits complete recue, 'cmd_count' le nombre
-- de commandes EBh recues (n'augmente pas en mode continu).
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.tb_pkg.all;

entity flash_model is
    generic (
        MEM_ADDR_BITS : natural := 16;
        INIT_FILE     : string  := "";
        T_VSL         : time    := 1.8 ms;
        T_RST         : time    := 30 us;
        T_CLQV        : time    := 7 ns;
        T_SHQZ        : time    := 6 ns;
        T_SHSL        : time    := 20 ns;
        T_SLCH        : time    := 5 ns;
        T_CHSH        : time    := 5 ns;
        T_DVCH        : time    := 2 ns;
        T_CHDX        : time    := 2 ns;
        MAX_REPORTS   : natural := 30
    );
    port (
        cs_n      : in    std_logic;
        sclk      : in    std_logic;
        sio0      : inout std_logic := 'Z';
        sio1      : inout std_logic := 'Z';
        sio2      : inout std_logic := 'Z';
        sio3      : inout std_logic := 'Z';
        cont_mode : out   std_logic := '0';
        txn_count : out   natural := 0;
        cmd_count : out   natural := 0;
        last_addr : out   std_logic_vector(23 downto 0) := (others => '0');
        errors    : out   natural := 0
    );
end entity;

architecture behav of flash_model is

    type phase_t is (P_IDLE, P_CMD, P_ADDR, P_MODE, P_DUMMY, P_DOUT, P_SOUT, P_DONE, P_IGNORE);
    type mem_t   is array (0 to 2**MEM_ADDR_BITS - 1) of std_logic_vector(7 downto 0);

    constant N_DUMMY : natural := 4;

    impure function init_mem return mem_t is
        file     f : text;
        variable m : mem_t;
        variable l : line;
        variable w : std_logic_vector(31 downto 0);
        variable a : natural := 0;
    begin
        for i in m'range loop
            m(i) := flash_pattern(i);
        end loop;
        if INIT_FILE /= "" then
            file_open(f, INIT_FILE, read_mode);
            while not endfile(f) and a + 3 <= m'high loop
                readline(f, l);
                if l'length > 0 then
                    hread(l, w);
                    m(a)     := w(7 downto 0);
                    m(a + 1) := w(15 downto 8);
                    m(a + 2) := w(23 downto 16);
                    m(a + 3) := w(31 downto 24);
                    a := a + 4;
                end if;
            end loop;
            file_close(f);
            -- Le reste de la flash est efface
            for i in a to m'high loop
                m(i) := x"FF";
            end loop;
            report "FLASH : " & integer'image(a) & " octets charges depuis " & INIT_FILE;
        end if;
        return m;
    end function;

begin

    process (cs_n, sclk, sio0, sio1, sio2, sio3)
        variable mem         : mem_t := init_mem;
        variable phase       : phase_t := P_IDLE;
        variable cont        : boolean := false;
        variable rst_en      : boolean := false;
        variable rst_pending : boolean := false;
        variable t_rst_end   : time := 0 ns;
        variable cmd         : std_logic_vector(7 downto 0) := x"00";
        variable mode        : std_logic_vector(7 downto 0) := x"00";
        variable cnt         : natural := 0;
        variable addr        : unsigned(23 downto 0) := (others => '0');
        variable sbytes      : std_logic_vector(23 downto 0) := (others => '0');
        variable idx         : natural := 0;
        variable nsampled    : natural := 0;   -- nibbles de donnees lus par l'hote
        variable obyte       : std_logic_vector(7 downto 0) := x"00";
        variable odrv        : std_logic_vector(3 downto 0) := "ZZZZ";
        variable omask       : std_logic_vector(3 downto 0) := "0000";
        variable cs_low      : boolean := false;
        variable t_fall      : time := 0 ns;
        variable t_rise      : time := 0 ns;
        variable t_lrise     : time := 0 ns;
        variable had_cs_rise : boolean := false;
        variable first_clk   : boolean := false;
        variable any_clk     : boolean := false;
        variable last_in     : boolean := false;
        variable last_in_q   : boolean := false;
        variable extra_warn  : boolean := false;
        variable nerr        : natural := 0;
        variable ntxn        : natural := 0;
        variable ncmd        : natural := 0;
        variable nib         : std_logic_vector(3 downto 0);

        procedure err(msg : string) is
        begin
            nerr   := nerr + 1;
            errors <= nerr;
            if nerr <= MAX_REPORTS then
                report "FLASH @" & time'image(now) & " : " & msg severity error;
            elsif nerr = MAX_REPORTS + 1 then
                report "FLASH : trop d'erreurs, les suivantes ne sont plus affichees" severity error;
            end if;
        end procedure;

        procedure warn(msg : string) is
        begin
            report "FLASH @" & time'image(now) & " : " & msg severity warning;
        end procedure;

        function is_driven(s : std_logic) return boolean is
        begin
            return s = '0' or s = '1';
        end function;

        -- Verifie qu'une ligne echantillonnee est pilotee et stable (tDVCH)
        procedure check_in(s : std_logic; t_ev : time; name : string) is
        begin
            if not is_driven(s) then
                err(name & " non pilotee ('" & std_logic'image(s) & "') au front montant de SCLK"
                    & " (phase " & phase_t'image(phase) & ")");
            elsif t_ev < T_DVCH then
                err(name & " : setup tDVCH viole (" & time'image(t_ev) & " < " & time'image(T_DVCH) & ")");
            end if;
        end procedure;

        procedure check_in_quad is
        begin
            check_in(sio0, sio0'last_event, "SIO0");
            check_in(sio1, sio1'last_event, "SIO1");
            check_in(sio2, sio2'last_event, "SIO2");
            check_in(sio3, sio3'last_event, "SIO3");
        end procedure;

        procedure drive(v : std_logic_vector(3 downto 0); mask : std_logic_vector(3 downto 0)) is
        begin
            if mask(0) = '1' then sio0 <= v(0) after T_CLQV; end if;
            if mask(1) = '1' then sio1 <= v(1) after T_CLQV; end if;
            if mask(2) = '1' then sio2 <= v(2) after T_CLQV; end if;
            if mask(3) = '1' then sio3 <= v(3) after T_CLQV; end if;
            odrv  := v;
            omask := mask;
        end procedure;

        procedure release_bus is
        begin
            sio0 <= 'Z' after T_SHQZ;
            sio1 <= 'Z' after T_SHQZ;
            sio2 <= 'Z' after T_SHQZ;
            sio3 <= 'Z' after T_SHQZ;
            omask := "0000";
        end procedure;

        function mem_idx(a : unsigned(23 downto 0)) return natural is
        begin
            return to_integer(a(MEM_ADDR_BITS - 1 downto 0));
        end function;

        procedure decode is
            variable prev_rst_en : boolean;
        begin
            prev_rst_en := rst_en;
            rst_en      := (cmd = x"66");
            phase       := P_DONE;
            cnt         := 0;
            idx         := 0;
            addr        := (others => '0');

            case cmd is
                when x"EB" =>
                    phase := P_ADDR;
                    ncmd  := ncmd + 1;
                    cmd_count <= ncmd;
                when x"66" =>
                    null;
                when x"99" =>
                    if prev_rst_en then
                        rst_pending := true;
                    else
                        err("99h recu sans 66h dans la transaction precedente : reset ignore");
                    end if;
                when x"FF" =>
                    null;
                when x"9F" =>
                    phase := P_SOUT; sbytes := x"C84016";
                when x"05" =>
                    phase := P_SOUT; sbytes := x"000000";
                when x"35" =>
                    phase := P_SOUT; sbytes := x"020202";
                when others =>
                    err("commande inconnue ou non supportee " & to_hstring(cmd) & "h");
                    phase := P_IGNORE;
            end case;
        end procedure;

    begin
        ------------------------------------------------------------------------
        -- CS#
        ------------------------------------------------------------------------
        if falling_edge(cs_n) then
            if now < T_VSL then
                err("CS# active a " & time'image(now) & ", avant tVSL = " & time'image(T_VSL));
            end if;
            if now < t_rst_end then
                err("CS# active pendant tRST (reset 66h/99h en cours jusqu'a "
                    & time'image(t_rst_end) & ")");
            end if;
            if had_cs_rise and now - t_rise < T_SHSL then
                err("tSHSL viole : CS# haut " & time'image(now - t_rise) & " < " & time'image(T_SHSL));
            end if;
            if to_x01(sclk) /= '0' then
                err("SCLK n'est pas bas a la descente de CS# (mode SPI 0 attendu)");
            end if;
            cs_low     := true;
            t_fall     := now;
            first_clk  := true;
            any_clk    := false;
            last_in    := false;
            extra_warn := false;
            cnt        := 0;
            idx        := 0;
            cmd        := x"00";
            mode       := x"00";
            addr       := (others => '0');
            omask      := "0000";
            if cont then
                phase := P_ADDR;     -- mode continu : pas de commande
            else
                phase := P_CMD;
            end if;

        elsif rising_edge(cs_n) and cs_low then
            cs_low      := false;
            t_rise      := now;
            had_cs_rise := true;
            if any_clk and now - t_lrise < T_CHSH then
                err("tCHSH viole : CS# remonte " & time'image(now - t_lrise)
                    & " apres le dernier front montant de SCLK (< " & time'image(T_CHSH) & ")");
            end if;
            case phase is
                when P_CMD =>
                    if cnt > 0 then
                        err("CS# remonte au milieu de la commande (" & integer'image(cnt) & " fronts recus)");
                    end if;
                when P_ADDR =>
                    if cnt > 0 then
                        err("CS# remonte au milieu de l'adresse (" & integer'image(cnt) & " fronts recus)");
                    end if;
                when P_MODE =>
                    err("CS# remonte au milieu des bits de mode M7-0");
                when P_DUMMY =>
                    -- Normal pour une sortie du mode continu (CRMR), anormal sinon
                    if cont then
                        err("lecture continue abandonnee pendant les dummy");
                    end if;
                when P_DOUT =>
                    -- Le nibble presente au dernier front descendant (flux)
                    -- n'est pas lu : seuls comptent les fronts montants
                    if nsampled mod 2 /= 0 then
                        warn("lecture terminee sur un octet partiel");
                    end if;
                when others =>
                    null;
            end case;
            if rst_pending then
                rst_pending := false;
                cont        := false;
                cont_mode   <= '0';
                t_rst_end   := now + T_RST;
            end if;
            release_bus;
            phase := P_IDLE;
            if any_clk then
                ntxn      := ntxn + 1;
                txn_count <= ntxn;
            end if;
        end if;

        ------------------------------------------------------------------------
        -- Front montant de SCLK : echantillonnage des entrees
        ------------------------------------------------------------------------
        if rising_edge(sclk) and cs_low then
            if first_clk then
                if now - t_fall < T_SLCH then
                    err("tSLCH viole : premier front SCLK " & time'image(now - t_fall)
                        & " apres CS# (< " & time'image(T_SLCH) & ")");
                end if;
                first_clk := false;
            end if;
            any_clk := true;
            t_lrise := now;
            last_in := false;
            nib     := to_x01(sio3) & to_x01(sio2) & to_x01(sio1) & to_x01(sio0);

            case phase is
                when P_CMD =>
                    -- Commande sur 1 bit (SIO0), SIO1-3 ignores (QE = 1)
                    last_in   := true;
                    last_in_q := false;
                    cnt       := cnt + 1;
                    check_in(sio0, sio0'last_event, "SIO0");
                    cmd := cmd(6 downto 0) & nib(0);
                    if cnt = 8 then decode; end if;

                when P_ADDR =>
                    last_in   := true;
                    last_in_q := true;
                    cnt       := cnt + 1;
                    check_in_quad;
                    addr := addr(19 downto 0) & unsigned(nib);
                    if cnt = 6 then
                        last_addr <= std_logic_vector(addr);
                        phase := P_MODE;
                        cnt   := 0;
                    end if;

                when P_MODE =>
                    last_in   := true;
                    last_in_q := true;
                    cnt       := cnt + 1;
                    check_in_quad;
                    mode := mode(3 downto 0) & nib;
                    if cnt = 2 then
                        -- M5-4 = "10" : la prochaine transaction sera continue
                        cont := mode(5 downto 4) = "10";
                        if cont then cont_mode <= '1'; else cont_mode <= '0'; end if;
                        phase := P_DUMMY;
                        cnt   := 0;
                    end if;

                when P_DUMMY =>
                    cnt := cnt + 1;
                    if cnt = N_DUMMY then
                        phase    := P_DOUT;
                        idx      := 0;
                        nsampled := 0;
                    end if;

                when P_DOUT | P_SOUT =>
                    nsampled := nsampled + 1;
                    -- L'hote ne doit plus piloter les lignes que la flash pilote
                    if (omask(0) = '1' and sio0 /= odrv(0)) or
                       (omask(1) = '1' and sio1 /= odrv(1)) or
                       (omask(2) = '1' and sio2 /= odrv(2)) or
                       (omask(3) = '1' and sio3 /= odrv(3)) then
                        err("conflit de bus pendant la sortie de donnees : l'hote pilote encore SIO");
                    end if;

                when P_DONE =>
                    if not extra_warn then
                        warn("fronts SCLK supplementaires apres la commande " & to_hstring(cmd) & "h");
                        extra_warn := true;
                    end if;

                when P_IDLE | P_IGNORE =>
                    null;
            end case;
        end if;

        ------------------------------------------------------------------------
        -- Front descendant de SCLK : sortie des donnees (tCLQV apres)
        ------------------------------------------------------------------------
        if falling_edge(sclk) and cs_low then
            if phase = P_DOUT then
                if idx = 0 then
                    obyte := mem(mem_idx(addr));
                    addr  := addr + 1;
                    drive(obyte(7 downto 4), "1111");
                else
                    drive(obyte(3 downto 0), "1111");
                end if;
                idx := (idx + 1) mod 2;
            elsif phase = P_SOUT then
                -- Sortie SPI sur SO = SIO1, octets de sbytes en boucle
                if idx = 0 then
                    obyte  := sbytes(23 downto 16);
                    sbytes := sbytes(15 downto 0) & sbytes(23 downto 16);
                end if;
                drive("ZZ" & obyte(7 - idx) & 'Z', "0010");
                idx := (idx + 1) mod 8;
            end if;
        end if;

        ------------------------------------------------------------------------
        -- Hold (tCHDX) : l'hote ne doit pas changer une entree juste apres le
        -- front montant qui l'a echantillonnee
        ------------------------------------------------------------------------
        if cs_low and last_in and not sclk'event and not cs_n'event then
            if sio0'event or (last_in_q and (sio1'event or sio2'event or sio3'event)) then
                if now - t_lrise < T_CHDX then
                    err("hold tCHDX viole : SIO change " & time'image(now - t_lrise)
                        & " apres le front montant de SCLK");
                end if;
            end if;
        end if;
    end process;

end architecture;
