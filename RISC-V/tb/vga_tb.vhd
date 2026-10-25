-------------------------------------------------------------------------------
-- tb_vgaSignalGen.vhd
--
-- Testbench pour l'entite vgaSignalGen (vgaSigGen.vhd).
-- Necessite VHDL-2008 (package std.env pour std.env.stop).
--   GHDL : ghdl -a --std=08 vgaSigGen.vhd tb_vgaSignalGen.vhd
--          ghdl -e --std=08 tb_vgaSignalGen
--          ghdl -r --std=08 tb_vgaSignalGen
--
-- Verifie :
--   1) Polarite/duree de Hsync et Vsync (par rapport a un compteur de
--      reference h_ref/v_ref independant, recopiant les memes constantes).
--   2) addr_vram reste toujours dans la plage valide [0 ; 7999].
--   3) Alignement des pixels RED/GREEN/BLUE par rapport a h_cnt, sous
--      deux hypotheses :
--        (a) aucun decalage      -> doit echouer si le bug est present
--        (b) decalage de 2 cycles -> doit passer si le bug est exactement
--                                     un retard de 2 cycles d'horloge
--
-- Modele VRAM comportemental : latence de 2 cycles (registre d'adresse +
-- registre de sortie), gelee quand en_vram = '0', conformement a
-- l'hypothese "latence BRAM + 1" codee dans pre_a/pre_b du DUT.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_tb is
end entity;

architecture sim of vga_tb is

  constant CLK_PERIOD : time := 10 ns;

  constant H_VISIBLE : natural := 640;
  constant H_FRONT   : natural := 16;
  constant H_SYNC    : natural := 96;
  constant H_TOTAL   : natural := 800;

  constant V_VISIBLE : natural := 400;
  constant V_FRONT   : natural := 12;
  constant V_SYNC    : natural := 2;
  constant V_TOTAL   : natural := 449;

  constant WORDS_PER_LINE  : natural := H_VISIBLE / 32;          -- 20
  constant WORDS_PER_FRAME : natural := WORDS_PER_LINE * V_VISIBLE; -- 8000

  signal clk_xtal  : std_logic := '0';
  signal rst       : std_logic := '1';
  signal Hsync, Vsync     : std_logic;
  signal RED, GREEN, BLUE : std_logic;
  signal en_vram   : std_logic;
  signal addr_vram : std_logic_vector(12 downto 0);
  signal dout_vram : std_logic_vector(31 downto 0) := (others => '0');

  -- Contenu VRAM : mot i = valeur binaire de i (facile a decoder / a
  -- comparer bit a bit dans les checkers ci-dessous)
  type mem_t is array (0 to WORDS_PER_FRAME-1) of std_logic_vector(31 downto 0);
  function init_mem return mem_t is
    variable m : mem_t;
  begin
    for i in 0 to WORDS_PER_FRAME-1 loop
      m(i) := std_logic_vector(to_unsigned(i, 32));
    end loop;
    return m;
  end function;
  signal mem : mem_t := init_mem;

  signal addr_latched : unsigned(12 downto 0) := (others => '0');

  -- Compteur de reference (h_ref, v_ref), independant du DUT
  signal h_ref     : integer := 0;
  signal v_ref     : integer := 0;
  signal ref_valid : std_logic := '0';

  signal err_no_shift : integer := 0;
  signal err_shift2   : integer := 0;

begin

  ----------------------------------------------------------------
  -- Horloge
  ----------------------------------------------------------------
  clk_xtal <= not clk_xtal after CLK_PERIOD/2;

  ----------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------
  dut : entity work.vgaSignalGen
    port map (
      clk_xtal  => clk_xtal,
      rst       => rst,
      Hsync     => Hsync,
      Vsync     => Vsync,
      RED       => RED,
      GREEN     => GREEN,
      BLUE      => BLUE,
      en_vram   => en_vram,
      addr_vram => addr_vram,
      dout_vram => dout_vram
    );

  ----------------------------------------------------------------
  -- Modele VRAM comportemental (2 cycles de latence, gel si en_vram='0')
  ----------------------------------------------------------------
  process (clk_xtal)
  begin
    if rising_edge(clk_xtal) then
      if en_vram = '1' then
        addr_latched <= unsigned(addr_vram);
        dout_vram    <= mem(to_integer(addr_latched));
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Reset
  ----------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 20 * CLK_PERIOD;
    wait until rising_edge(clk_xtal);
    rst <= '0';
    wait;
  end process;

  ----------------------------------------------------------------
  -- Compteur de reference h_ref / v_ref
  ----------------------------------------------------------------
  process (clk_xtal, rst)
  begin
    if rst = '1' then
      h_ref     <= 0;
      v_ref     <= 0;
      ref_valid <= '0';
    elsif rising_edge(clk_xtal) then
      ref_valid <= '1';
      if h_ref = H_TOTAL-1 then
        h_ref <= 0;
        if v_ref = V_TOTAL-1 then
          v_ref <= 0;
        else
          v_ref <= v_ref + 1;
        end if;
      else
        h_ref <= h_ref + 1;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Verification Hsync / Vsync
  ----------------------------------------------------------------
  process (clk_xtal)
  begin
    if rising_edge(clk_xtal) and ref_valid = '1' then
      if (h_ref >= H_VISIBLE+H_FRONT) and (h_ref < H_VISIBLE+H_FRONT+H_SYNC) then
        assert Hsync = '0'
          report "Hsync devrait etre actif (bas) a h_ref=" & integer'image(h_ref)
          severity error;
      else
        assert Hsync = '1'
          report "Hsync ne devrait pas etre actif a h_ref=" & integer'image(h_ref)
          severity error;
      end if;

      if (v_ref >= V_VISIBLE+V_FRONT) and (v_ref < V_VISIBLE+V_FRONT+V_SYNC) then
        assert Vsync = '0'
          report "Vsync devrait etre actif (bas) a v_ref=" & integer'image(v_ref)
          severity error;
      else
        assert Vsync = '1'
          report "Vsync ne devrait pas etre actif a v_ref=" & integer'image(v_ref)
          severity error;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- addr_vram doit toujours rester dans la plage valide
  ----------------------------------------------------------------
  process (clk_xtal)
  begin
    if rising_edge(clk_xtal) and ref_valid = '1' then
      assert to_integer(unsigned(addr_vram)) < WORDS_PER_FRAME
        report "addr_vram hors plage : " & integer'image(to_integer(unsigned(addr_vram)))
        severity error;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Hypothese (a) : RED(h_ref) == bit attendu de pixel h_ref (aucun
  -- decalage). Doit echouer massivement si le bug de pipeline existe.
  ----------------------------------------------------------------
  process (clk_xtal)
    variable word_idx, bit_idx : integer;
    variable expected_bit : std_logic;
  begin
    if rising_edge(clk_xtal) and ref_valid = '1' then
      if (v_ref < V_VISIBLE) and (h_ref < H_VISIBLE) then
        word_idx := v_ref * WORDS_PER_LINE + (h_ref / 32);
        bit_idx  := 31 - (h_ref mod 32);
        expected_bit := mem(word_idx)(bit_idx);
        if RED /= expected_bit then
          err_no_shift <= err_no_shift + 1;
        end if;
      end if;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Hypothese (b) : RED, observe 2 cycles plus tard, correspond au
  -- pixel h_ref. Doit passer (0 erreur) si le decalage est exactement
  -- de 2 cycles d'horloge.
  ----------------------------------------------------------------
  process (clk_xtal)
    type ref_pipe_t is array (0 to 1) of integer;
    variable h_pipe, v_pipe : ref_pipe_t := (others => -1);
    variable word_idx, bit_idx : integer;
    variable expected_bit : std_logic;
  begin
    if rising_edge(clk_xtal) then
      if ref_valid = '1' and h_pipe(1) >= 0 and v_pipe(1) >= 0 then
        if (v_pipe(1) < V_VISIBLE) and (h_pipe(1) < H_VISIBLE) then
          word_idx := v_pipe(1) * WORDS_PER_LINE + (h_pipe(1) / 32);
          bit_idx  := 31 - (h_pipe(1) mod 32);
          expected_bit := mem(word_idx)(bit_idx);
          if RED /= expected_bit then
            err_shift2 <= err_shift2 + 1;
          end if;
        end if;
      end if;
      h_pipe(1) := h_pipe(0);
      v_pipe(1) := v_pipe(0);
      h_pipe(0) := h_ref;
      v_pipe(0) := v_ref;
    end if;
  end process;

  ----------------------------------------------------------------
  -- Sequencement : 2 frames completes puis rapport final
  ----------------------------------------------------------------
  process
  begin
    wait until rst = '0';
    wait for 2 * H_TOTAL * V_TOTAL * CLK_PERIOD;

    report "=================================================";
    report "Erreurs (hypothese : aucun decalage)   : " & integer'image(err_no_shift);
    report "Erreurs (hypothese : decalage 2 cycles) : " & integer'image(err_shift2);
    report "=================================================";
    if err_shift2 = 0 and err_no_shift > 0 then
      report "CONFIRME : le pixel affiche est decale de 2 cycles d'horloge (2 pixels) par rapport a h_cnt / Hsync.";
    elsif err_no_shift = 0 then
      report "Aucun decalage detecte : alignement correct.";
    else
      report "Comportement inattendu : ni l'hypothese 0, ni +2 cycles ne correspond exactement."
        severity warning;
    end if;

    std.env.stop;
  end process;

end architecture sim;