--------------------------------------------------------------------------------
-- UART.vhd
-- Version compacte. Corrige un point important : "busy" (= transmitting)
-- s'active des le cycle clk_xtal ou 'send' est vu, sans attendre le
-- prochain tick de baud (baud_en). Avant, busy restait a 0 pendant une
-- bonne partie d'une periode de baud apres l'ecriture, ce qui permettait
-- a une lecture immediate de croire, a tort, que le coeur n'etait pas
-- occupe.
-- RX : chaque octet recu fait basculer rx_toggle (DataIn reste stable jusqu'a
-- l'octet suivant). Pas de poignee de main read/read_ready : rien ne peut
-- rester bloque si le cote bus est remis a zero avec un octet non lu.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY UART IS
    PORT(
        phase_inc  : in  std_logic_vector(31 downto 0); -- phase_inc = (baud * 2^32) / clk_xtal
        clk_xtal   : in  std_logic;
        clk_CPU    : in  std_logic;  -- non utilisee dans le coeur (compat. d'interface)
        send       : in  std_logic;
        DataOut    : in  std_logic_vector(7 downto 0);
        rx         : in  std_logic;
        tx         : out std_logic;
        DataIn     : out std_logic_vector(7 downto 0);
        busy       : out std_logic;
        rx_toggle  : out std_logic   -- bascule a chaque octet recu
    );
END ENTITY UART;

ARCHITECTURE rtl OF UART IS

    -- NCO baud (TX) et 8x baud (RX) : enables 1 cycle clk_xtal a la place
    -- des anciennes horloges derivees clk_baud/clk_8x.
    SIGNAL cnt, acc             : unsigned(31 downto 0) := (others => '0');
    SIGNAL baud_msb, baud_msb_d : std_logic := '0';
    SIGNAL x8_msb, x8_msb_d     : std_logic := '0';
    SIGNAL baud_en, x8_en       : std_logic := '0';

    -- TX
    SIGNAL transmitting : std_logic := '0';
    SIGNAL tx_shift_reg : std_logic_vector(9 downto 0) := (others => '0');
    SIGNAL tx_bit_count : unsigned(3 downto 0) := (others => '0');
    SIGNAL tx_i         : std_logic := '1';

    -- RX
    SIGNAL rx_sync1, rx_sync2 : std_logic := '1';
    SIGNAL sample_cnt   : unsigned(2 downto 0) := (others => '0');
    SIGNAL bit_cnt      : unsigned(3 downto 0) := (others => '0');
    SIGNAL shiftreg     : std_logic_vector(9 downto 0) := (others => '0');
    SIGNAL receiving    : std_logic := '0';
    SIGNAL rx_toggle_i  : std_logic := '0';
    SIGNAL DataIn_i     : std_logic_vector(7 downto 0) := (others => '0');

BEGIN

    tx         <= tx_i;
    busy       <= transmitting; -- busy = transmitting, plus de registre separe
    rx_toggle  <= rx_toggle_i;
    DataIn     <= DataIn_i;

    ----------------------------------------------------------------
    -- NCO baud / 8x-baud + synchro rx (un seul process, domaine clk_xtal)
    ----------------------------------------------------------------
    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;

            cnt        <= cnt + unsigned(phase_inc);
            baud_msb   <= cnt(31);
            baud_msb_d <= baud_msb;
            baud_en    <= baud_msb AND (NOT baud_msb_d);

            acc      <= acc + shift_left(unsigned(phase_inc), 3);
            x8_msb   <= acc(31);
            x8_msb_d <= x8_msb;
            x8_en    <= x8_msb AND (NOT x8_msb_d);
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- TX : transmitting (= busy) s'active des que 'send' est vu, meme
    -- si baud_en ne pulse pas encore. Le decalage des bits, lui, reste
    -- cadence par baud_en. Plus besoin de "latch" : tant que
    -- transmitting = '1', la branche qui teste 'send' n'est meme plus
    -- evaluee, donc pas de re-declenchement possible en cours de trame.
    ----------------------------------------------------------------
    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            IF transmitting = '0' THEN
                IF send = '1' THEN
                    transmitting <= '1';
                    tx_shift_reg <= '1' & DataOut & '0'; -- {stop, data, start}
                    tx_bit_count <= (others => '0');
                END IF;
            ELSIF baud_en = '1' THEN
                IF tx_bit_count < 10 THEN
                    tx_i         <= tx_shift_reg(to_integer(tx_bit_count));
                    tx_bit_count <= tx_bit_count + 1;
                ELSE
                    tx_i         <= '1';
                    transmitting <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    ----------------------------------------------------------------
    -- RX : surechantillonnage 8x, cadence par x8_en
    ----------------------------------------------------------------
    PROCESS(clk_xtal)
    BEGIN
        IF rising_edge(clk_xtal) THEN
            IF x8_en = '1' THEN
                IF (receiving = '0') AND (rx_sync2 = '0') THEN
                    receiving  <= '1';
                    sample_cnt <= (others => '0');
                    bit_cnt    <= (others => '0');
                ELSIF receiving = '1' THEN
                    sample_cnt <= sample_cnt + 1;

                    IF sample_cnt = 4 THEN
                        shiftreg(to_integer(bit_cnt)) <= rx_sync2;
                        bit_cnt <= bit_cnt + 1;

                        IF bit_cnt = 9 THEN
                            receiving  <= '0';
                            sample_cnt <= (others => '0');

                            IF (shiftreg(0) = '0') AND (rx_sync2 = '1') THEN
                                DataIn_i     <= shiftreg(8 downto 1);
                                rx_toggle_i  <= NOT rx_toggle_i;
                            END IF;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE rtl;