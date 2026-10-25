--------------------------------------------------------------------------------
-- vga_tb.vhd
-- Testbench auto-verifiant de vgaModule avec les vraies primitives Gowin
-- (rPLL -> horloge pixel 25.07 MHz, BRAM DPB), simulees par prim_sim.vhd :
--   cote coeur (clk27, maitre de bus de tb_pkg) :
--     T1 remplissage des 8000 mots de l'ecran (SW)
--     T2 relecture (LW) : une lecture ne doit rien ecrire
--     T3 SB aux offsets 0..3 et SH aux offsets 0/2, puis relecture
--   cote video (horloge pixel) :
--     T4 largeur et periode de Hsync (96 / 800 pixels, active basse) et de
--        Vsync (2 lignes ; 525 lignes active basse en 640x480, 449 active
--        haute en 640x400), adresse VRAM < 8000
--     T5 chaque pixel d'une image complete = bit (31 - x mod 32) du mot
--        (y - V_TOP)*20 + x/32 ; noir hors de l'image
-- Generic MODE_480 : mode teste (true : 640x480@60, false : 640x400@70).
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/vga.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity vga_tb is
    generic (
        MODE_480 : boolean := true
    );
end entity;

architecture sim of vga_tb is
    constant WORDS : natural := 8000;

    function sel(c : boolean; a, b : integer) return integer is
    begin
        if c then return a; else return b; end if;
    end function;
    constant V_TOTAL  : integer := sel(MODE_480, 525, 449);
    constant V_TOP    : integer := sel(MODE_480, 40, 0);
    constant V_SSTART : integer := sel(MODE_480, 490, 412);   -- premiere ligne de Vsync
    constant VS_ACT   : std_logic := std_logic'val(sel(MODE_480, 2, 3));   -- '0' / '1'
    type mem_t is array (0 to 8191) of std_logic_vector(31 downto 0);
    shared variable ref : mem_t;

    signal clk27, clk50, clk_pix : std_logic := '0';
    signal rst      : std_logic := '1';
    signal en       : std_logic := '1';
    signal sim_done : boolean := false;

    signal m        : bus_m_t := BUS_M_IDLE;
    signal din_bus  : std_logic_vector(31 downto 0);
    signal rdy      : std_logic;
    signal cs       : std_logic;

    signal hs, vs, r, g, b : std_logic;

    signal writes_done : boolean := false;
    signal frame_done  : boolean := false;
    signal vid_errs    : natural := 0;

    function pattern(i : natural) return std_logic_vector is
        variable x : unsigned(31 downto 0) := to_unsigned(i, 32);
    begin
        x := resize(x * unsigned'(x"9E3779B1"), 32);
        return std_logic_vector(x xor shift_right(x, 13));
    end function;
begin

    clk27 <= not clk27 after CLK27_PERIOD / 2 when not sim_done;
    cs    <= '1' when m.adr(31 downto 24) = x"C0" else '0';

    u_pll : entity work.Gowin_rPLL
        port map (clkout => clk50, clkoutd => clk_pix, clkin => clk27);

    dut : entity work.vgaModule
        generic map (MODE_480 => MODE_480)
        port map (
            clk_xtal  => clk_pix,
            rst       => rst,
            hSync     => hs,
            vSync     => vs,
            red       => r,
            green     => g,
            blue      => b,
            clk_vram  => clk27,
            cs_vram   => cs,
            we_vram   => m.we,
            rd_vram   => m.rd,
            rdy_vram  => rdy,
            wenb_vram => m.wenb,
            addr_vram => m.adr(14 downto 0),
            din_vram  => m.dout,
            dout_vram => din_bus
        );

    ----------------------------------------------------------------------------
    -- Cote coeur
    ----------------------------------------------------------------------------
    stim : process
        variable errs : natural := 0;
        variable seed : unsigned(31 downto 0) := x"1F2E3D4C";
        variable rv   : std_logic_vector(31 downto 0);

        procedure check(cond : boolean; msg : string) is
        begin
            if not cond then
                errs := errs + 1;
                if errs <= 30 then
                    report "TB @" & time'image(now) & " : " & msg severity error;
                end if;
            end if;
        end procedure;

        procedure rnd(v : out std_logic_vector(31 downto 0)) is
            variable x : unsigned(31 downto 0) := seed;
        begin
            x := x xor shift_left(x, 13); x := x xor shift_right(x, 17); x := x xor shift_left(x, 5);
            seed := x; v := std_logic_vector(x);
        end procedure;

        procedure access_vram(is_write : boolean; byte_adr : natural; f3 : std_logic_vector(2 downto 0);
                              val : std_logic_vector(31 downto 0); v : out std_logic_vector(31 downto 0)) is
            variable a  : std_logic_vector(31 downto 0) := std_logic_vector(x"C0000000" + to_unsigned(byte_adr, 32));
            variable ok : boolean;
        begin
            bus_fetch(clk27, en, m);
            bus_cycle(clk27, en, rdy, din_bus, m, is_write, a, val, core_wenb(f3, a), v, ok, 50);
            check(ok, "pas de rdy pour l'acces a 0x" & to_hstring(a));
        end procedure;

        procedure store(byte_adr : natural; f3 : std_logic_vector(2 downto 0); val : std_logic_vector(31 downto 0)) is
            variable dummy : std_logic_vector(31 downto 0);
            variable w     : natural := byte_adr / 4;
            variable o     : natural := byte_adr mod 4;
        begin
            access_vram(true, byte_adr, f3, val, dummy);
            for k in 0 to store_bytes(f3) - 1 loop
                ref(w)(8*(o+k)+7 downto 8*(o+k)) := val(8*k+7 downto 8*k);
            end loop;
        end procedure;

        procedure expect_word(w : natural; what : string) is
            variable v : std_logic_vector(31 downto 0);
        begin
            access_vram(false, 4*w, F3_W, x"00000000", v);
            check(v = ref(w), what & " : mot " & integer'image(w) & " = 0x" & to_hstring(v)
                  & ", attendu 0x" & to_hstring(ref(w)));
        end procedure;

    begin
        for i in ref'range loop ref(i) := (others => '0'); end loop;
        rst <= '1';
        wait for 25 us;                      -- verrouillage du rPLL simule
        wait until rising_edge(clk27);
        rst <= '0';

        report "TB : T1 - remplissage de l'ecran (8000 mots)";
        for i in 0 to WORDS - 1 loop
            store(4*i, F3_W, pattern(i));
        end loop;

        report "TB : T2 - relecture";
        for k in 1 to 300 loop
            rnd(rv);
            expect_word(to_integer(unsigned(rv(12 downto 0))) mod WORDS, "T2");
        end loop;
        expect_word(0, "T2"); expect_word(WORDS - 1, "T2");

        report "TB : T3 - SB / SH a tous les offsets";
        for o in 0 to 3 loop
            rnd(rv);
            store(4*100 + o, F3_B, rv);
        end loop;
        expect_word(100, "T3 SB");
        rnd(rv); store(4*101, F3_H, rv);
        rnd(rv); store(4*101 + 2, F3_H, rv);
        expect_word(101, "T3 SH");
        expect_word(99, "T3 voisin"); expect_word(102, "T3 voisin");

        writes_done <= true;
        wait until frame_done for 45 ms;   -- jusqu'a 2 images de 14.3 / 16.8 ms
        check(frame_done, "T5 : aucune image complete verifiee");

        report "======== vga_tb : " & integer'image(errs) & " erreur(s) bus, "
               & integer'image(vid_errs) & " erreur(s) video ========";
        if errs = 0 and vid_errs = 0 then
            report "TB_RESULT: SUCCES";
        else
            report "TB_RESULT: ECHEC" severity error;
        end if;
        sim_done <= true;
        std.env.finish;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Cote video : verification des synchros et des pixels
    ----------------------------------------------------------------------------
    video : process (clk_pix)
        variable hs_p, vs_p   : std_logic := '1';
        variable x, y         : integer := -1;
        variable h_lock       : boolean := false;
        variable v_lock       : boolean := false;
        variable hs_len, hs_per, vs_len : natural := 0;
        variable vs_lines     : natural := 0;
        variable checking     : boolean := false;
        variable checked      : natural := 0;
        variable exp          : std_logic;
        variable w            : std_logic_vector(31 downto 0);

        procedure verr(msg : string) is
        begin
            vid_errs <= vid_errs + 1;
            if vid_errs < 20 then
                report "VIDEO @" & time'image(now) & " : " & msg severity error;
            end if;
        end procedure;
    begin
        if rising_edge(clk_pix) and rst = '0' then
            -- Position du pixel present sur les sorties
            if hs = '0' and hs_p = '1' then           -- debut de Hsync = pixel 656
                if h_lock and hs_per /= 800 then
                    verr("periode Hsync = " & integer'image(hs_per) & " au lieu de 800");
                end if;
                h_lock := true; hs_per := 0; hs_len := 0;
                x := 656;
            elsif h_lock then
                x := (x + 1) mod 800;
                if x = 0 and v_lock then y := (y + 1) mod V_TOTAL; end if;
            end if;
            hs_per := hs_per + 1;
            if hs = '0' then hs_len := hs_len + 1; end if;
            if h_lock and hs = '1' and hs_p = '0' and hs_len /= 96 then
                verr("largeur Hsync = " & integer'image(hs_len) & " au lieu de 96");
            end if;

            if vs = VS_ACT and vs_p /= VS_ACT then    -- debut de Vsync = ligne V_SSTART, x = 0
                if v_lock and y /= V_SSTART then
                    verr("Vsync en ligne " & integer'image(y) & " au lieu de " & integer'image(V_SSTART));
                end if;
                if h_lock and x /= 0 then
                    verr("Vsync pas aligne sur le debut de ligne (x = " & integer'image(x) & ")");
                end if;
                if checking then
                    checking := false;
                    if checked = 640 * 400 then frame_done <= true; end if;
                end if;
                v_lock := true; y := V_SSTART; vs_lines := 0;
                if writes_done and h_lock and not checking and not frame_done then
                    checking := true; checked := 0;
                end if;
            end if;
            if v_lock and vs /= VS_ACT and vs_p = VS_ACT and vs_lines /= 2 then
                verr("largeur Vsync = " & integer'image(vs_lines) & " ligne(s) au lieu de 2");
            end if;
            if vs = VS_ACT and x = 0 then vs_lines := vs_lines + 1; end if;

            -- Pixels (une image complete, apres la fin des ecritures)
            if checking and h_lock and v_lock then
                if x < 640 and y >= V_TOP and y < V_TOP + 400 then
                    w   := ref((y - V_TOP) * 20 + x / 32);
                    exp := w(31 - x mod 32);
                    checked := checked + 1;
                else
                    exp := '0';
                end if;
                if r /= exp or g /= exp or b /= exp then
                    verr("pixel (" & integer'image(x) & "," & integer'image(y) & ") = "
                         & std_logic'image(r) & ", attendu " & std_logic'image(exp));
                end if;
            end if;
            hs_p := hs; vs_p := vs;
        end if;
    end process;

    -- Adresse VRAM lue par le generateur toujours dans l'ecran
    addr_chk : process (clk_pix)
        alias en_v   is <<signal .vga_tb.dut.cs_vga   : std_logic>>;
        alias addr_v is <<signal .vga_tb.dut.addr_vga : std_logic_vector(12 downto 0)>>;
    begin
        if rising_edge(clk_pix) and rst = '0' and en_v = '1' then
            assert to_integer(unsigned(addr_v)) < WORDS
                report "adresse VRAM video hors ecran : " & integer'image(to_integer(unsigned(addr_v)))
                severity error;
        end if;
    end process;

end architecture;
