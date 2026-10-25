LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaSignalGen IS
  PORT (
    clk_xtal  : in  std_logic;                      -- pixel clock
    rst       : in  std_logic;

    Hsync     : out std_logic;
    Vsync     : out std_logic;
    RED       : out std_logic;
    GREEN     : out std_logic;
    BLUE      : out std_logic;

    en_vram   : out std_logic;
    addr_vram : out std_logic_vector(12 downto 0);
    dout_vram : in  std_logic_vector(31 downto 0)
  );
END ENTITY vgaSignalGen;

ARCHITECTURE vgaSignalGenV1 OF vgaSignalGen IS
  -- Timings VGA 640x400@70Hz
  CONSTANT H_VISIBLE : NATURAL := 640;
  CONSTANT H_FRONT   : NATURAL := 16;
  CONSTANT H_SYNC    : NATURAL := 96;
  CONSTANT H_BACK    : NATURAL := 48;
  CONSTANT H_TOTAL   : NATURAL := 800;

  CONSTANT V_VISIBLE : NATURAL := 400;
  CONSTANT V_FRONT   : NATURAL := 12;
  CONSTANT V_SYNC    : NATURAL := 2;
  CONSTANT V_BACK    : NATURAL := 35;
  constant V_TOTAL   : NATURAL := 449;

  SIGNAL h_cnt        : unsigned(9 downto 0) := (OTHERS => '0');
  SIGNAL v_cnt        : unsigned(8 downto 0) := (OTHERS => '0');
  SIGNAL end_of_line  : std_logic;
  SIGNAL end_of_frame : std_logic;
  SIGNAL pixel_en     : std_logic;
  SIGNAL new_frame    : std_logic;

  SIGNAL addr_r       : unsigned(12 downto 0) := (OTHERS => '0');
  SIGNAL bit_cnt      : unsigned(4 downto 0)  := to_unsigned(31, 5);
  SIGNAL shift_reg    : std_logic_vector(31 downto 0) := (OTHERS => '0');

  SIGNAL pixel        : std_logic := '0';
  SIGNAL pixel_en_d   : std_logic := '0';

  SIGNAL pre_a : std_logic;
  SIGNAL pre_b : std_logic;
BEGIN

  end_of_line  <= '1' WHEN h_cnt = H_TOTAL-1 ELSE '0';
  end_of_frame <= '1' WHEN v_cnt = V_TOTAL-1 ELSE '0';

  -- Compteurs H/V
  PROCESS (clk_xtal, rst)
  BEGIN
    IF rst = '1' THEN
      h_cnt <= (OTHERS => '0');
      v_cnt <= (OTHERS => '0');
    ELSIF rising_edge(clk_xtal) THEN
      IF end_of_line = '1' THEN
        h_cnt <= (OTHERS => '0');
        IF end_of_frame = '1' THEN
          v_cnt <= (OTHERS => '0');
        ELSE
          v_cnt <= v_cnt + 1;
        END IF;
      ELSE
        h_cnt <= h_cnt + 1;
      END IF;
    END IF;
  END PROCESS;

  -- Zone visible
  pixel_en <= '1' WHEN (h_cnt < H_VISIBLE) AND (v_cnt < V_VISIBLE) ELSE '0';

  -- Syncs (actifs bas)
  Hsync <= '0' WHEN (h_cnt >= H_VISIBLE + H_FRONT) AND
                    (h_cnt <  H_VISIBLE + H_FRONT + H_SYNC) ELSE '1';
  Vsync <= '0' WHEN (v_cnt >= V_VISIBLE + V_FRONT) AND
                    (v_cnt <  V_VISIBLE + V_FRONT + V_SYNC) ELSE '1';


  -- Adressage VRAM
  pre_a   <= '1' WHEN (v_cnt = V_TOTAL-1 AND h_cnt = 0) ELSE '0';
  pre_b   <= '1' WHEN (v_cnt = V_TOTAL-1 AND h_cnt = 2) ELSE '0';  -- 2 = latence BRAM + 1
  en_vram <= '1' WHEN (pixel_en = '1') OR (v_cnt = V_TOTAL-1 AND h_cnt < 3) ELSE '0';

  addr_vram <= std_logic_vector(addr_r);
  new_frame <= '1' WHEN (h_cnt = 0 AND v_cnt = 0) ELSE '0';

  PROCESS (clk_xtal, rst)
  BEGIN
    IF rst = '1' THEN
      addr_r    <= (OTHERS => '0');
      bit_cnt   <= to_unsigned(31, 5);
      shift_reg <= (OTHERS => '0');
    ELSIF rising_edge(clk_xtal) THEN
      IF pre_a = '1' THEN
        addr_r <= (OTHERS => '0');
      ELSIF pre_b = '1' THEN
        shift_reg <= dout_vram;          -- mot 0
        bit_cnt   <= to_unsigned(31, 5);
        addr_r    <= to_unsigned(1, 13); -- adresse du mot suivant
      ELSIF pixel_en = '1' THEN
        IF bit_cnt = 0 THEN
          shift_reg <= dout_vram;
          bit_cnt   <= to_unsigned(31, 5);
          addr_r    <= addr_r + 1;
        ELSE
          bit_cnt <= bit_cnt - 1;
        END IF;
      END IF;
    END IF;
  END PROCESS;

  -- Pipeline pixel (1 cycle)
  PROCESS (clk_xtal)
  BEGIN
    IF rising_edge(clk_xtal) THEN
      pixel      <= shift_reg(to_integer(bit_cnt));
      pixel_en_d <= pixel_en;
    END IF;
  END PROCESS;

  -- Sortie RGB
  PROCESS (clk_xtal)
  BEGIN
    IF rising_edge(clk_xtal) THEN
      IF pixel_en_d = '1' THEN
        RED   <= pixel;
        GREEN <= pixel;
        BLUE  <= pixel;
      ELSE
        RED   <= '0';
        GREEN <= '0';
        BLUE  <= '0';
      END IF;
    END IF;
  END PROCESS;

END ARCHITECTURE;