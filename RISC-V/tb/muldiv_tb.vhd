--------------------------------------------------------------------------------
-- muldiv_tb.vhd
-- Testbench auto-verifiant de l'unite RV32M (mulDiv) : chaque resultat est
-- compare a un calcul de reference (numeric_std sur 64 bits), et la latence
-- (cycles entre le front du start et le front ou done est vu, comme uc) :
--   multiplication : exactement 2 cycles
--   division       : 2 cycles si diviseur nul, sinon 7 a 35 cycles, et 14 au
--                    plus si le dividende tient sur 8 bits (sortie anticipee)
--   T1 cas limites croises (0, +-1, +-2, 2^31-1, -2^31, -2^31+1, 0xFFFF,
--      0x10000, 0xFFFFFFFE) pour les 8 operations : division par 0 et
--      debordement -2^31 / -1 compris
--   T2 20 000 operations aleatoires, operandes de toutes tailles (exerce la
--      sortie anticipee du diviseur)
-- Le resultat final est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
-- Lancement : voir RISC-V/sim/muldiv.do
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.tb_pkg.all;

entity tb_muldiv is
end entity;

architecture sim of tb_muldiv is
    signal clk      : std_logic := '0';
    signal rst      : std_logic := '1';
    signal start    : std_logic := '0';
    signal f3       : std_logic_vector(2 downto 0) := "000";
    signal a, b     : std_logic_vector(31 downto 0) := (others => '0');
    signal done     : std_logic;
    signal res      : std_logic_vector(31 downto 0);
    signal sim_done : boolean := false;

    type names_t is array (0 to 7) of string(1 to 6);
    constant NAMES : names_t := ("MUL   ", "MULH  ", "MULHSU", "MULHU ",
                                 "DIV   ", "DIVU  ", "REM   ", "REMU  ");

    -- Resultat attendu selon la specification RV32M
    function expected(op : natural; x, y : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable p   : signed(65 downto 0);
        constant MIN : std_logic_vector(31 downto 0) := x"80000000";
        constant M1  : std_logic_vector(31 downto 0) := x"FFFFFFFF";
    begin
        case op is
            when 0 | 1 =>
                p := resize(signed(x), 33) * resize(signed(y), 33);
                if op = 0 then return std_logic_vector(p(31 downto 0)); end if;
                return std_logic_vector(p(63 downto 32));
            when 2 =>
                p := resize(signed(x), 33) * signed('0' & y);
                return std_logic_vector(p(63 downto 32));
            when 3 =>
                p := signed('0' & x) * signed('0' & y);
                return std_logic_vector(p(63 downto 32));
            when 4 =>
                if y = x"00000000" then return M1; end if;
                if x = MIN and y = M1 then return MIN; end if;
                return std_logic_vector(signed(x) / signed(y));
            when 5 =>
                if y = x"00000000" then return M1; end if;
                return std_logic_vector(unsigned(x) / unsigned(y));
            when 6 =>
                if y = x"00000000" then return x; end if;
                if x = MIN and y = M1 then return x"00000000"; end if;
                return std_logic_vector(signed(x) rem signed(y));
            when others =>
                if y = x"00000000" then return x; end if;
                return std_logic_vector(unsigned(x) rem unsigned(y));
        end case;
    end function;

begin

    clk <= not clk after CLK_SYS_PERIOD / 2 when not sim_done;

    dut : entity work.mulDiv
        port map (clk => clk, rst => rst, start => start, f3 => f3,
                  a => a, b => b, done => done, res => res);

    stim : process
        variable errs  : natural := 0;
        variable n_ops : natural := 0;
        variable lat_max : natural := 0;
        variable seed  : unsigned(31 downto 0) := x"6A09E667";
        variable r1, r2, r3 : std_logic_vector(31 downto 0);

        type vals_t is array (natural range <>) of std_logic_vector(31 downto 0);
        constant EDGE : vals_t := (x"00000000", x"00000001", x"FFFFFFFF", x"00000002",
                                   x"FFFFFFFE", x"7FFFFFFF", x"80000000", x"80000001",
                                   x"0000FFFF", x"00010000", x"12345678", x"FEDCBA98");

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

        -- Une operation, au rythme de uc : start sur un front, done teste aux
        -- fronts suivants ; un cycle de repos entre deux operations
        procedure do_op(op : natural; x, y : std_logic_vector(31 downto 0)) is
            variable n   : natural := 0;
            variable exp : std_logic_vector(31 downto 0) := expected(op, x, y);
            variable mag : unsigned(31 downto 0);
            constant what : string := NAMES(op) & " 0x" & to_hstring(x) & ", 0x" & to_hstring(y);
        begin
            wait until rising_edge(clk);
            start <= '1';
            f3    <= std_logic_vector(to_unsigned(op, 3));
            a     <= x;
            b     <= y;
            wait until rising_edge(clk);         -- front du start
            start <= '0';
            a     <= (others => 'X');            -- les operandes doivent etre figes au start
            b     <= (others => 'X');
            -- comme uc : done n'est regarde qu'a partir du front qui suit le
            -- start (au front du start, done vaut encore celui de l'operation
            -- precedente)
            loop
                wait until rising_edge(clk);
                n := n + 1;
                exit when done = '1' or n > 60;
            end loop;
            n_ops := n_ops + 1;
            check(done = '1', what & " : pas de done");
            check(res = exp, what & " = 0x" & to_hstring(res) & ", attendu 0x" & to_hstring(exp));
            if op < 4 then
                check(n = 2, what & " : latence " & integer'image(n) & " cycles au lieu de 2");
            elsif y = x"00000000" then
                check(n = 2, what & " : division par 0 en " & integer'image(n) & " cycles au lieu de 2");
            else
                check(n >= 7 and n <= 35, what & " : latence " & integer'image(n) & " cycles (7..35)");
                if n > lat_max then lat_max := n; end if;
                -- sortie anticipee : dividende de moins de 8 bits -> 14 cycles au plus
                if (op = 4 or op = 6) and x(31) = '1' then
                    mag := unsigned(-signed(x));
                else
                    mag := unsigned(x);
                end if;
                if mag < 256 then
                    check(n <= 14, what & " : dividende sur 8 bits, latence " & integer'image(n)
                          & " cycles au lieu de 14 au plus (sortie anticipee)");
                end if;
            end if;
        end procedure;

    begin
        rst <= '1';
        for i in 1 to 4 loop wait until rising_edge(clk); end loop;
        rst <= '0';

        report "TB : T1 - cas limites croises, 8 operations";
        for op in 0 to 7 loop
            for i in EDGE'range loop
                for j in EDGE'range loop
                    do_op(op, EDGE(i), EDGE(j));
                end loop;
            end loop;
        end loop;

        report "TB : T2 - 20000 operations aleatoires";
        for k in 1 to 20000 loop
            rnd(r1); rnd(r2); rnd(r3);
            -- tailles variees : masque les bits hauts selon r3
            r1 := std_logic_vector(shift_right(unsigned(r1), to_integer(unsigned(r3(4 downto 0)))));
            r2 := std_logic_vector(shift_right(unsigned(r2), to_integer(unsigned(r3(9 downto 5)))));
            if r3(10) = '1' then r1 := std_logic_vector(-signed(r1)); end if;
            if r3(11) = '1' then r2 := std_logic_vector(-signed(r2)); end if;
            do_op(to_integer(unsigned(r3(14 downto 12))), r1, r2);
        end loop;

        report "======== tb_muldiv : " & integer'image(n_ops) & " operations, latence de division max "
               & integer'image(lat_max) & " cycles, " & integer'image(errs) & " erreur(s) ========";
        if errs = 0 then
            report "TB_RESULT: SUCCES";
        else
            report "TB_RESULT: ECHEC" severity error;
        end if;
        sim_done <= true;
        std.env.finish;
        wait;
    end process;

end architecture;
