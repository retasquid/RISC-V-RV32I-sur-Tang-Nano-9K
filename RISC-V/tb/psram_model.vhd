--------------------------------------------------------------------------------
-- psram_model.vhd
-- Modele comportemental (simulation uniquement) de la PSRAM Lyontek
-- LY68L6400 (64 Mbit, SPI/QPI), d'apres la datasheet Rev 0.7.
--
-- Commandes supportees :
--   mode SPI : 03h, 0Bh, EBh, 02h, 38h, 35h, 66h, 99h, C0h, 9Fh
--   mode QPI : EBh (6 wait), 02h/38h, F5h, 66h, 99h, C0h
--
-- Verifications (chaque violation incremente 'errors') :
--   * CE# active avant tPU = 150 us apres la mise sous tension (§9)
--   * commande autre que 66h/99h avant le RESET obligatoire (§9)
--   * SCLK pas bas a la descente de CE# (mode SPI 0)
--   * tCSP, tCHD, tCPH, tCEM, setup/hold des entrees (tSP/tHD)
--   * ligne non pilotee (Z, H, X...) echantillonnee en phase d'entree
--   * conflit de bus pendant que la PSRAM sort des donnees
--   * commande inconnue, commande invalide dans le mode courant,
--     commande/adresse tronquee par CE#
--
-- La memoire simulee fait 2**MEM_ADDR_BITS octets : les adresses plus hautes
-- sont repliees (alias). 'last_addr' donne l'adresse 24 bits complete recue
-- pour que le TB puisse verifier les bits de poids fort.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity psram_model is
    generic (
        MEM_ADDR_BITS : natural := 16;
        T_PU          : time    := 150 us;
        T_ACLK        : time    := 5 ns;
        T_HZ          : time    := 5 ns;
        T_CEM         : time    := 8 us;
        T_CPH         : time    := 50 ns;
        T_CHD         : time    := 20 ns;
        T_CSP         : time    := 2.5 ns;
        T_SP          : time    := 2 ns;
        T_HD          : time    := 2 ns;
        REQUIRE_RESET : boolean := true;
        MAX_REPORTS   : natural := 30
    );
    port (
        ce_n      : in    std_logic;
        sclk      : in    std_logic;
        sio0      : inout std_logic := 'Z';
        sio1      : inout std_logic := 'Z';
        sio2      : inout std_logic := 'Z';
        sio3      : inout std_logic := 'Z';
        qpi_mode  : out   std_logic := '0';
        txn_count : out   natural := 0;
        last_addr : out   std_logic_vector(23 downto 0) := (others => '0');
        errors    : out   natural := 0
    );
end entity;

architecture behav of psram_model is

    type phase_t is (P_IDLE, P_CMD, P_ADDR, P_WAIT, P_DIN, P_DOUT, P_DONE, P_IGNORE);
    type mem_t   is array (0 to 2**MEM_ADDR_BITS - 1) of std_logic_vector(7 downto 0);

    constant ID_MF  : std_logic_vector(7 downto 0) := x"0D";
    constant ID_KGD : std_logic_vector(7 downto 0) := x"5D";

begin

    process (ce_n, sclk, sio0, sio1, sio2, sio3)
        variable mem         : mem_t := (others => (others => 'U'));
        variable phase       : phase_t := P_IDLE;
        variable qpi         : boolean := false;
        variable rst_done    : boolean := false;
        variable rst_en      : boolean := false;
        variable wrap32      : boolean := false;
        variable cmd         : std_logic_vector(7 downto 0) := x"00";
        variable cnt         : natural := 0;
        variable addr        : unsigned(23 downto 0) := (others => '0');
        variable a_quad      : boolean := false;
        variable d_quad      : boolean := false;
        variable is_read     : boolean := false;
        variable id_mode     : boolean := false;
        variable id_idx      : natural := 0;
        variable nwait       : natural := 0;
        variable shreg       : std_logic_vector(7 downto 0) := x"00";
        variable idx         : natural := 0;
        variable obyte       : std_logic_vector(7 downto 0) := x"00";
        variable odrv        : std_logic_vector(3 downto 0) := "ZZZZ";
        variable omask       : std_logic_vector(3 downto 0) := "0000";
        variable ce_low      : boolean := false;
        variable t_fall      : time := 0 ns;
        variable t_rise      : time := 0 ns;
        variable t_lrise     : time := 0 ns;
        variable had_ce_rise : boolean := false;
        variable first_clk   : boolean := false;
        variable any_clk     : boolean := false;
        variable last_in     : boolean := false;
        variable last_in_q   : boolean := false;
        variable extra_warn  : boolean := false;
        variable nerr        : natural := 0;
        variable ntxn        : natural := 0;
        variable nib         : std_logic_vector(3 downto 0);

        procedure err(msg : string) is
        begin
            nerr   := nerr + 1;
            errors <= nerr;
            if nerr <= MAX_REPORTS then
                report "PSRAM @" & time'image(now) & " : " & msg severity error;
            elsif nerr = MAX_REPORTS + 1 then
                report "PSRAM : trop d'erreurs, les suivantes ne sont plus affichees" severity error;
            end if;
        end procedure;

        procedure warn(msg : string) is
        begin
            report "PSRAM @" & time'image(now) & " : " & msg severity warning;
        end procedure;

        function is_driven(s : std_logic) return boolean is
        begin
            return s = '0' or s = '1';
        end function;

        -- Verifie qu'une ligne echantillonnee est pilotee et stable (tSP)
        procedure check_in(s : std_logic; t_ev : time; name : string) is
        begin
            if not is_driven(s) then
                err(name & " non pilotee ('" & std_logic'image(s) & "') au front montant de SCLK"
                    & " (phase " & phase_t'image(phase) & ")");
            elsif t_ev < T_SP then
                err(name & " : setup tSP viole (" & time'image(t_ev) & " < " & time'image(T_SP) & ")");
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
            if mask(0) = '1' then sio0 <= v(0) after T_ACLK; end if;
            if mask(1) = '1' then sio1 <= v(1) after T_ACLK; end if;
            if mask(2) = '1' then sio2 <= v(2) after T_ACLK; end if;
            if mask(3) = '1' then sio3 <= v(3) after T_ACLK; end if;
            odrv  := v;
            omask := mask;
        end procedure;

        procedure release_bus is
        begin
            sio0 <= 'Z' after T_HZ;
            sio1 <= 'Z' after T_HZ;
            sio2 <= 'Z' after T_HZ;
            sio3 <= 'Z' after T_HZ;
            omask := "0000";
        end procedure;

        function next_addr(a : unsigned(23 downto 0); w32 : boolean) return unsigned is
        begin
            if w32 then
                return a(23 downto 5) & (a(4 downto 0) + 1);
            else
                return a + 1;
            end if;
        end function;

        function mem_idx(a : unsigned(23 downto 0)) return natural is
        begin
            return to_integer(a(MEM_ADDR_BITS - 1 downto 0));
        end function;

        procedure decode is
            variable prev_rst_en : boolean;
        begin
            if REQUIRE_RESET and not rst_done and cmd /= x"66" and cmd /= x"99" then
                err("commande " & to_hstring(cmd) & "h avant la sequence RESET 66h/99h"
                    & " obligatoire apres la mise sous tension (datasheet §9)");
            end if;

            prev_rst_en := rst_en;
            rst_en      := (cmd = x"66");
            phase       := P_DONE;
            cnt         := 0;
            idx         := 0;
            nwait       := 0;
            is_read     := false;
            id_mode     := false;
            addr        := (others => '0');

            case cmd is
                when x"66" =>
                    null;
                when x"99" =>
                    if prev_rst_en then
                        qpi      := false;
                        wrap32   := false;
                        rst_done := true;
                        qpi_mode <= '0';
                    else
                        err("99h recu sans 66h dans la transaction precedente : reset ignore");
                    end if;
                when x"35" =>
                    if qpi then
                        err("35h (Enter Quad Mode) n'existe pas en mode QPI");
                    else
                        qpi      := true;
                        qpi_mode <= '1';
                    end if;
                when x"F5" =>
                    if qpi then
                        qpi      := false;
                        qpi_mode <= '0';
                    else
                        err("F5h (Exit Quad Mode) n'existe pas en mode SPI");
                    end if;
                when x"C0" =>
                    wrap32 := not wrap32;
                when x"EB" =>
                    phase := P_ADDR; a_quad := true; d_quad := true; is_read := true; nwait := 6;
                when x"38" =>
                    phase := P_ADDR; a_quad := true; d_quad := true;
                when x"02" =>
                    phase := P_ADDR; a_quad := qpi; d_quad := qpi;
                when x"03" =>
                    if qpi then
                        err("03h non supporte en mode QPI");
                        phase := P_IGNORE;
                    else
                        phase := P_ADDR; a_quad := false; d_quad := false; is_read := true;
                    end if;
                when x"0B" =>
                    if qpi then
                        err("0Bh non supporte en mode QPI (retire en Rev 0.5)");
                        phase := P_IGNORE;
                    else
                        phase := P_ADDR; a_quad := false; d_quad := false; is_read := true; nwait := 8;
                    end if;
                when x"9F" =>
                    if qpi then
                        err("9Fh non supporte en mode QPI");
                        phase := P_IGNORE;
                    else
                        phase := P_ADDR; a_quad := false; d_quad := false; is_read := true;
                        id_mode := true; id_idx := 0;
                    end if;
                when others =>
                    if qpi then
                        err("commande inconnue " & to_hstring(cmd) & "h en mode QPI");
                    else
                        err("commande inconnue " & to_hstring(cmd) & "h en mode SPI");
                    end if;
                    phase := P_IGNORE;
            end case;
        end procedure;

        procedure end_addr is
        begin
            last_addr <= std_logic_vector(addr);
            cnt := 0;
            idx := 0;
            if is_read then
                if nwait = 0 then
                    phase := P_DOUT;
                else
                    phase := P_WAIT;
                end if;
            else
                phase := P_DIN;
            end if;
        end procedure;

    begin
        ------------------------------------------------------------------------
        -- CE#
        ------------------------------------------------------------------------
        if falling_edge(ce_n) then
            if now < T_PU then
                err("CE# active a " & time'image(now) & ", avant la fin de tPU = "
                    & time'image(T_PU) & " (datasheet §9)");
            end if;
            if had_ce_rise and now - t_rise < T_CPH then
                err("tCPH viole : CE# haut " & time'image(now - t_rise) & " < " & time'image(T_CPH));
            end if;
            if to_x01(sclk) /= '0' then
                err("SCLK n'est pas bas a la descente de CE# (mode SPI 0 attendu)");
            end if;
            ce_low     := true;
            t_fall     := now;
            first_clk  := true;
            any_clk    := false;
            last_in    := false;
            extra_warn := false;
            phase      := P_CMD;
            cnt        := 0;
            idx        := 0;
            cmd        := x"00";
            omask      := "0000";

        elsif rising_edge(ce_n) and ce_low then
            ce_low      := false;
            t_rise      := now;
            had_ce_rise := true;
            if now - t_fall > T_CEM then
                err("tCEM viole : CE# bas pendant " & time'image(now - t_fall) & " > " & time'image(T_CEM));
            end if;
            if any_clk and now - t_lrise < T_CHD then
                err("tCHD viole : CE# remonte " & time'image(now - t_lrise)
                    & " apres le dernier front montant de SCLK (< " & time'image(T_CHD) & ")");
            end if;
            case phase is
                when P_CMD =>
                    -- Commande incomplete : ignoree par la puce (cas du F5h quad
                    -- envoye a l'init alors que la PSRAM est en SPI) -> warning
                    if cnt > 0 then
                        warn("CE# remonte au milieu de la commande (" & integer'image(cnt)
                             & " fronts recus) : commande ignoree");
                    end if;
                when P_ADDR =>
                    err("CE# remonte au milieu de l'adresse (" & integer'image(cnt) & " fronts recus)");
                when P_DIN =>
                    if idx /= 0 then
                        warn("ecriture terminee sur un octet partiel : octet ignore");
                    end if;
                when others =>
                    null;
            end case;
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
        if rising_edge(sclk) and ce_low then
            if first_clk then
                if now - t_fall < T_CSP then
                    err("tCSP viole : premier front SCLK " & time'image(now - t_fall)
                        & " apres CE# (< " & time'image(T_CSP) & ")");
                end if;
                first_clk := false;
            end if;
            any_clk := true;
            t_lrise := now;
            last_in := false;
            nib     := to_x01(sio3) & to_x01(sio2) & to_x01(sio1) & to_x01(sio0);

            case phase is
                when P_CMD =>
                    last_in   := true;
                    last_in_q := qpi;
                    cnt       := cnt + 1;
                    if qpi then
                        check_in_quad;
                        cmd := cmd(3 downto 0) & nib;
                        if cnt = 2 then decode; end if;
                    else
                        check_in(sio0, sio0'last_event, "SIO0");
                        cmd := cmd(6 downto 0) & nib(0);
                        if cnt = 8 then decode; end if;
                    end if;

                when P_ADDR =>
                    last_in   := true;
                    last_in_q := a_quad;
                    cnt       := cnt + 1;
                    if a_quad then
                        check_in_quad;
                        addr := addr(19 downto 0) & unsigned(nib);
                        if cnt = 6 then end_addr; end if;
                    else
                        check_in(sio0, sio0'last_event, "SIO0");
                        addr := addr(22 downto 0) & nib(0);
                        if cnt = 24 then end_addr; end if;
                    end if;

                when P_WAIT =>
                    cnt := cnt + 1;
                    if cnt >= nwait then
                        phase := P_DOUT;
                        idx   := 0;
                    end if;

                when P_DOUT =>
                    -- L'hote ne doit plus piloter les lignes que la PSRAM pilote
                    if (omask(0) = '1' and sio0 /= odrv(0)) or
                       (omask(1) = '1' and sio1 /= odrv(1)) or
                       (omask(2) = '1' and sio2 /= odrv(2)) or
                       (omask(3) = '1' and sio3 /= odrv(3)) then
                        err("conflit de bus pendant la sortie de donnees : l'hote pilote encore SIO");
                    end if;

                when P_DIN =>
                    last_in   := true;
                    last_in_q := d_quad;
                    idx       := idx + 1;
                    if d_quad then
                        check_in_quad;
                        shreg := shreg(3 downto 0) & nib;
                        if idx = 2 then
                            mem(mem_idx(addr)) := shreg;
                            addr := next_addr(addr, wrap32);
                            idx  := 0;
                        end if;
                    else
                        check_in(sio0, sio0'last_event, "SIO0");
                        shreg := shreg(6 downto 0) & nib(0);
                        if idx = 8 then
                            mem(mem_idx(addr)) := shreg;
                            addr := next_addr(addr, wrap32);
                            idx  := 0;
                        end if;
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
        -- Front descendant de SCLK : sortie des donnees (tACLK apres)
        ------------------------------------------------------------------------
        if falling_edge(sclk) and ce_low and phase = P_DOUT then
            if idx = 0 then
                if id_mode then
                    if id_idx = 0 then
                        obyte := ID_MF;
                    elsif id_idx = 1 then
                        obyte := ID_KGD;
                    else
                        obyte := x"00";
                    end if;
                    id_idx := id_idx + 1;
                else
                    obyte := mem(mem_idx(addr));
                    addr  := next_addr(addr, wrap32);
                end if;
            end if;
            if d_quad then
                if idx = 0 then
                    drive(obyte(7 downto 4), "1111");
                else
                    drive(obyte(3 downto 0), "1111");
                end if;
                idx := (idx + 1) mod 2;
            else
                drive("ZZ" & obyte(7 - idx) & 'Z', "0010");
                idx := (idx + 1) mod 8;
            end if;
        end if;

        ------------------------------------------------------------------------
        -- Hold (tHD) : l'hote ne doit pas changer une entree juste apres le
        -- front montant qui l'a echantillonnee
        ------------------------------------------------------------------------
        if ce_low and last_in and not sclk'event and not ce_n'event then
            if sio0'event or (last_in_q and (sio1'event or sio2'event or sio3'event)) then
                if now - t_lrise < T_HD then
                    err("hold tHD viole : SIO change " & time'image(now - t_lrise)
                        & " apres le front montant de SCLK");
                end if;
            end if;
        end if;
    end process;

end architecture;
