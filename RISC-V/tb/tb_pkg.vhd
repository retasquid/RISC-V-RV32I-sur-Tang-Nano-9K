--------------------------------------------------------------------------------
-- tb_pkg.vhd
-- Outils communs aux testbenches : horloge, et un "maitre de bus" qui
-- reproduit le handshake de uc.vhd (V2, etape 6) :
--   * rd/we/adr changent juste apres un front montant de clk ou en = '1'
--   * rdy est teste sur ces memes fronts ; des que rdy = '1', la donnee est
--     capturee sur ce front (comme IR / regFile) et rd/we retombent
--   * entre deux requetes, rd = we = 0 pendant au moins un pas (S_DECODE /
--     S_GAP) ; entre deux acces memoire, le coeur fait un fetch : bus_fetch
-- en = '1' : maitre a pleine vitesse, comme le coeur actuel. en = enCore de
-- clkDiv (1 pas / 17 cycles) : maitre lent, requetes tenues longtemps.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_pkg is

    constant CLK27_PERIOD  : time := 37.037 ns;

    -- Adresse "ROM" utilisee pour simuler les fetchs (cs SRAM = 0)
    constant ROM_FETCH_ADR : std_logic_vector(31 downto 0) := x"40000000";

    -- funct3 des loads/stores RV32I
    constant F3_B  : std_logic_vector(2 downto 0) := "000";
    constant F3_H  : std_logic_vector(2 downto 0) := "001";
    constant F3_W  : std_logic_vector(2 downto 0) := "010";
    constant F3_BU : std_logic_vector(2 downto 0) := "100";
    constant F3_HU : std_logic_vector(2 downto 0) := "101";

    -- Signaux pilotes par le coeur sur le bus memoire
    type bus_m_t is record
        adr  : std_logic_vector(31 downto 0);
        dout : std_logic_vector(31 downto 0);
        rd   : std_logic;
        we   : std_logic;
        wenb : std_logic_vector(3 downto 0);
    end record;

    constant BUS_M_IDLE : bus_m_t := (
        adr  => ROM_FETCH_ADR,
        dout => (others => '0'),
        rd   => '0',
        we   => '0',
        wenb => "1111"
    );

    -- Calcul de wenb identique a core.vhd (donnee NON decalee sur dout)
    function core_wenb(f3 : std_logic_vector(2 downto 0);
                       a  : std_logic_vector(31 downto 0)) return std_logic_vector;

    -- Nombre d'octets ecrits par un store de funct3 donne
    function store_bytes(f3 : std_logic_vector(2 downto 0)) return natural;

    -- Attend le prochain front montant de clk ou en = '1' (pas de uc)
    procedure wait_tick(signal clk, en : in std_logic);

    -- Un acces load/store complet, cote coeur.
    -- ok = false si rdy n'arrive pas en 'timeout' pas de uc.
    procedure bus_cycle(
        signal   clk, en, rdy : in  std_logic;
        signal   din          : in  std_logic_vector(31 downto 0);
        signal   m            : out bus_m_t;
        constant is_write     : in  boolean;
        constant adr          : in  std_logic_vector(31 downto 0);
        constant data         : in  std_logic_vector(31 downto 0);
        constant wenb         : in  std_logic_vector(3 downto 0);
        variable rdata        : out std_logic_vector(31 downto 0);
        variable ok           : out boolean;
        constant timeout      : in  natural);

    -- Fetch d'instruction minimal entre deux acces (2 pas de uc, cs SRAM = 0)
    procedure bus_fetch(signal clk, en : in std_logic; signal m : out bus_m_t);

    -- Contenu par defaut de flash_model (sans INIT_FILE) : octet pseudo-aleatoire
    -- fonction de l'adresse, pour que le TB connaisse la valeur attendue
    function flash_pattern(a : natural) return std_logic_vector;

end package;

package body tb_pkg is

    function core_wenb(f3 : std_logic_vector(2 downto 0);
                       a  : std_logic_vector(31 downto 0)) return std_logic_vector is
        variable u, s : std_logic_vector(3 downto 0);
    begin
        if f3 = "000" then
            u := "0001";
        elsif f3 = "001" then
            u := "0011";
        else
            u := "1111";
        end if;
        if a(0) = '1' then s := u(2 downto 0) & '0'; else s := u; end if;
        if a(1) = '1' then return s(1 downto 0) & "00"; else return s; end if;
    end function;

    function store_bytes(f3 : std_logic_vector(2 downto 0)) return natural is
    begin
        case f3(1 downto 0) is
            when "00"   => return 1;
            when "01"   => return 2;
            when others => return 4;
        end case;
    end function;

    procedure wait_tick(signal clk, en : in std_logic) is
    begin
        loop
            wait until rising_edge(clk);
            exit when en = '1';
        end loop;
    end procedure;

    procedure bus_cycle(
        signal   clk, en, rdy : in  std_logic;
        signal   din          : in  std_logic_vector(31 downto 0);
        signal   m            : out bus_m_t;
        constant is_write     : in  boolean;
        constant adr          : in  std_logic_vector(31 downto 0);
        constant data         : in  std_logic_vector(31 downto 0);
        constant wenb         : in  std_logic_vector(3 downto 0);
        variable rdata        : out std_logic_vector(31 downto 0);
        variable ok           : out boolean;
        constant timeout      : in  natural) is
        variable n : natural := 0;
    begin
        -- S_DECODE -> S_MEM : adresse de l'ALU + rd/we leves sur le meme front
        wait_tick(clk, en);
        m.adr  <= adr;
        m.dout <= data;
        m.wenb <= wenb;
        if is_write then
            m.we <= '1'; m.rd <= '0';
        else
            m.rd <= '1'; m.we <= '0';
        end if;

        -- S_MEM : rdy et din lus sur le front (valeurs d'avant le front)
        loop
            wait_tick(clk, en);
            if rdy = '1' then
                rdata := din;                  -- capture regFile sur ce front
                m.rd  <= '0';
                m.we  <= '0';
                ok    := true;
                return;
            end if;
            n := n + 1;
            if n >= timeout then
                m.rd  <= '0';
                m.we  <= '0';
                rdata := (others => 'X');
                ok    := false;
                return;
            end if;
        end loop;
    end procedure;

    procedure bus_fetch(signal clk, en : in std_logic; signal m : out bus_m_t) is
    begin
        wait_tick(clk, en);        -- S_GAP -> S_FETCH : adr = PC (ROM), rd = 1
        m.adr <= ROM_FETCH_ADR;
        m.rd  <= '1';
        m.we  <= '0';
        wait_tick(clk, en);        -- instruction recue -> S_DECODE, rd = 0
        m.rd  <= '0';
    end procedure;

    function flash_pattern(a : natural) return std_logic_vector is
        variable x : unsigned(31 downto 0) := to_unsigned(a, 32);
    begin
        x := resize(x * unsigned'(x"9E3779B1"), 32);
        x := x xor shift_right(x, 15);
        return std_logic_vector(x(7 downto 0));
    end function;

end package body;
