--------------------------------------------------------------------------------
-- peripherals.vhd
-- Registres memoire-mappes pour le processeur RISC-V (adr = adresse octet / 4) :
--   0x04 (0x10) GPIO0     lecture : sorties pour les bits en sortie, broche
--                         (resynchronisee) pour les bits en entree
--   0x05 (0x14) DIRGPIO0  1 = sortie
--   0x06 (0x18) TX_UART   ecriture : envoie din(7:0) ; lecture : bit 0 = busy
--   0x07 (0x1C) RX_UART   bit 8 = octet disponible, bits 7:0 = cet octet.
--                         Une lecture avec bit 8 = 1 consomme l'octet ; sans
--                         octet disponible, la lecture rend 0 (jamais un octet
--                         deja consomme ou recu avant un reset).
--   0x08 (0x20) BAUD_UART phase_inc = baud * 2^32 / clk_xtal
-- Bus : une requete est traitee UNE seule fois, au premier cycle ou
-- cs = '1' et rd XOR we ; rdy et dout sont tenus jusqu'a ce que rd et we
-- retombent (handshake de uc). Les effets de bord (consommation de l'octet
-- recu, envoi UART) n'ont donc lieu qu'une fois par acces.
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY peripherals IS
    PORT(
        -- MEMORY INTERFACE
        dout            : out std_logic_vector(31 downto 0);
        din             : in std_logic_vector(31 downto 0);
        adr             : in std_logic_vector(7 downto 0);
        rdy             : out std_logic;
        clk, rst        : in std_logic;
        cs, we, rd      : in std_logic;
        -- IO ports
        GPIO0 : inout std_logic_vector(31 downto 0);
        -- UART
        clk_xtal : in std_logic;  -- Horloge XTAL dediee au calcul du baud rate
        uart_tx  : out std_logic;
        uart_rx  : in std_logic
    );

END ENTITY;

ARCHITECTURE peripheralsV2 OF peripherals IS
    SIGNAL dout_r           : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL ack              : std_logic := '0';

    -- GPIO : registre de sortie, direction, entree resynchronisee
    SIGNAL gpio_out         : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL gpio_dir         : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL gpio_s1, gpio_s2 : std_logic_vector(31 downto 0) := (others => '0');

    -- Registres cote bus pour l'UART
    SIGNAL uart_phase_inc  : std_logic_vector(31 downto 0) := (others => '0');
    SIGNAL uart_tx_data    : std_logic_vector(7 downto 0)  := (others => '0');
    SIGNAL uart_send_reg   : std_logic := '0';
    SIGNAL uart_busy       : std_logic;
    SIGNAL uart_rx_data    : std_logic_vector(7 downto 0);
    SIGNAL uart_rx_toggle  : std_logic;

    -- Reception : rx_toggle (domaine clk_xtal) resynchronise ; chaque
    -- changement = un octet, recopie dans rx_byte avec le flag "en attente"
    SIGNAL tog_s1, tog_s2, tog_prev : std_logic := '0';
    SIGNAL rx_byte         : std_logic_vector(7 downto 0) := (others => '0');
    SIGNAL uart_rx_pending : std_logic := '0';

    COMPONENT UART
        PORT(
            phase_inc  : in  std_logic_vector(31 downto 0);
            clk_xtal   : in  std_logic;
            clk_CPU    : in  std_logic;
            send       : in  std_logic;
            DataOut    : in  std_logic_vector(7 downto 0);
            rx         : in  std_logic;
            tx         : out std_logic;
            DataIn     : out std_logic_vector(7 downto 0);
            busy       : out std_logic;
            rx_toggle  : out std_logic
        );
    END COMPONENT;

BEGIN

    dout <= dout_r;
    rdy  <= ack;

    gen_gpio0 : FOR i IN 0 TO 31 GENERATE
        GPIO0(i) <= gpio_out(i) WHEN gpio_dir(i) = '1' ELSE 'Z';
    END GENERATE;

    inst_uart : UART
        PORT MAP(
            phase_inc  => uart_phase_inc,
            clk_xtal   => clk_xtal,
            clk_CPU    => clk,
            send       => uart_send_reg,
            DataOut    => uart_tx_data,
            rx         => uart_rx,
            tx         => uart_tx,
            DataIn     => uart_rx_data,
            busy       => uart_busy,
            rx_toggle  => uart_rx_toggle
        );

    PROCESS(clk)
        VARIABLE consume : std_logic;
    BEGIN
        IF rising_edge(clk) THEN
            gpio_s1 <= GPIO0;
            gpio_s2 <= gpio_s1;

            tog_s1   <= uart_rx_toggle;
            tog_s2   <= tog_s1;
            tog_prev <= tog_s2;

            -- 'send' tenu jusqu'a ce que l'UART confirme le demarrage (busy)
            IF uart_busy = '1' THEN
                uart_send_reg <= '0';
            END IF;

            consume := '0';

            IF rst = '1' THEN
                ack            <= '0';
                gpio_out       <= (others => '0');
                gpio_dir       <= (others => '0');
                uart_phase_inc <= (others => '0');
                uart_send_reg  <= '0';
                consume        := '1';
            ELSIF ack = '0' AND cs = '1' AND (rd XOR we) = '1' THEN
                ack <= '1';
                IF we = '1' THEN
                    CASE adr IS
                        WHEN x"04"  => gpio_out <= din;
                        WHEN x"05"  => gpio_dir <= din;
                        WHEN x"06"  =>
                            uart_send_reg <= '1';
                            uart_tx_data  <= din(7 downto 0);
                        WHEN x"08"  => uart_phase_inc <= din;
                        WHEN OTHERS => NULL;
                    END CASE;
                ELSE
                    CASE adr IS
                        WHEN x"04" =>
                            FOR i IN 0 TO 31 LOOP
                                IF gpio_dir(i) = '1' THEN
                                    dout_r(i) <= gpio_out(i);
                                ELSE
                                    dout_r(i) <= gpio_s2(i);
                                END IF;
                            END LOOP;
                        WHEN x"05" =>
                            dout_r <= gpio_dir;
                        WHEN x"06" =>
                            -- busy des l'ecriture, avant meme que l'UART l'ait vue
                            dout_r <= (0 => uart_busy OR uart_send_reg, others => '0');
                        WHEN x"07" =>
                            dout_r <= (others => '0');
                            IF uart_rx_pending = '1' THEN
                                dout_r(8)          <= '1';
                                dout_r(7 downto 0) <= rx_byte;
                                consume            := '1';
                            END IF;
                        WHEN x"08" =>
                            dout_r <= uart_phase_inc;
                        WHEN OTHERS =>
                            dout_r <= (others => '0');
                    END CASE;
                END IF;
            ELSIF rd = '0' AND we = '0' THEN
                ack <= '0';
            END IF;

            -- Nouvel octet : prioritaire sur la consommation (un octet arrive
            -- pendant la lecture du precedent n'est pas perdu). Un octet non lu
            -- est ecrase par le suivant (debordement).
            IF tog_s2 /= tog_prev AND rst = '0' THEN
                rx_byte         <= uart_rx_data;
                uart_rx_pending <= '1';
            ELSIF consume = '1' THEN
                uart_rx_pending <= '0';
            END IF;
        END IF;
    END PROCESS;
END ARCHITECTURE;
