--------------------------------------------------------------------------------
-- muldiv.vhd
-- Unite de l'extension M (RV32M) : MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM,
-- REMU (funct3 = f3). Pilotee par uc (etat S_MULDIV) :
--   start (1 cycle, fin de S_DECODE) : operandes a = rs1, b = rs2 et f3 figes
--   done  : resultat valide sur res ; reste a '1' jusqu'au start suivant
--
-- Multiplication (f3(2) = '0') : operandes etendus a 33 bits selon le signe
-- demande (MULH : signe x signe, MULHSU : signe x non signe, MULHU : non
-- signe x non signe), produit signe 66 bits infere sur les multiplieurs
-- 18x18 du GW1NR-9. Operandes figes au start, produit fige au cycle suivant,
-- done et res pendant le cycle d'apres : uc ecrit rd 2 cycles apres le start.
-- res = bits 31..0 (MUL) ou 63..32 (MULH*).
--
-- Division (f3(2) = '1') : division "restaurante" sur les valeurs absolues,
-- un bit de quotient par cycle, puis correction des signes (quotient negatif
-- si les signes different, reste du signe du dividende). Sortie anticipee :
-- quand le reste partiel vaut 0 et que les 8 bits suivants du dividende sont
-- nuls, les 8 bits de quotient correspondants sont nuls et le reste reste a
-- 0 : on les traite en un cycle. Du start a l'ecriture de rd : 3 + nombre
-- d'iterations, soit 7 cycles (dividende nul), 14 (dividende de moins de
-- 8 bits), 35 au pire (32 bits utiles) ; division par 0 : 2 cycles.
-- Cas imposes par la specification :
--   division par 0 : quotient = tous les bits a 1, reste = dividende
--   -2^31 / -1     : quotient = -2^31, reste = 0 (vient naturellement des
--                    valeurs absolues : 2^31 / 1, signes egaux)
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY mulDiv IS
    PORT(
        clk, rst    : in  std_logic;
        start       : in  std_logic;
        f3          : in  std_logic_vector(2 downto 0);
        a, b        : in  std_logic_vector(31 downto 0);
        done        : out std_logic;
        res         : out std_logic_vector(31 downto 0)
    );
END ENTITY;

ARCHITECTURE mulDivV1 OF mulDiv IS
    TYPE state_t IS (S_IDLE, S_MUL, S_MULR, S_ABS, S_DIV, S_SIGN, S_DONE);
    SIGNAL state                : state_t := S_IDLE;
    SIGNAL op                   : std_logic_vector(2 downto 0) := (OTHERS => '0');

    -- Multiplieur
    SIGNAL ma, mb               : signed(32 downto 0) := (OTHERS => '0');
    SIGNAL prod                 : signed(65 downto 0) := (OTHERS => '0');

    -- Diviseur
    SIGNAL ra, rb               : std_logic_vector(31 downto 0) := (OTHERS => '0');   -- operandes bruts
    SIGNAL dvd, dvs, quo        : unsigned(31 downto 0) := (OTHERS => '0');
    SIGNAL rem_r                : unsigned(32 downto 0) := (OTHERS => '0');
    SIGNAL cnt                  : unsigned(5 downto 0) := (OTHERS => '0');
    SIGNAL neg_q, neg_r         : std_logic := '0';
    SIGNAL res_r                : std_logic_vector(31 downto 0) := (OTHERS => '0');
    SIGNAL mres                 : std_logic_vector(31 downto 0);
BEGIN

    -- Resultat d'une multiplication, pris directement sur le produit fige
    mres <= std_logic_vector(prod(31 downto 0)) WHEN op(1 downto 0) = "00" ELSE
            std_logic_vector(prod(63 downto 32));

    done <= '1' WHEN state = S_DONE OR state = S_MULR ELSE '0';
    res  <= mres WHEN state = S_MULR ELSE res_r;

    PROCESS(clk)
        VARIABLE sa, sb     : std_logic;
        VARIABLE t          : unsigned(32 downto 0);
        VARIABLE r1         : unsigned(32 downto 0);
    BEGIN
        IF rising_edge(clk) THEN
            -- Produit sur les operandes figes (multiplieurs DSP)
            prod <= ma * mb;

            IF rst = '1' THEN
                state <= S_IDLE;
            ELSIF start = '1' THEN
                op <= f3;
                IF f3(2) = '0' THEN
                    -- Multiplication : extension de signe selon l'operation
                    sa := a(31) AND NOT (f3(1) AND f3(0));     -- rs1 signe sauf MULHU
                    sb := b(31) AND NOT f3(1);                   -- rs2 signe : MUL, MULH
                    ma <= signed(sa & a);
                    mb <= signed(sb & b);
                    state <= S_MUL;
                ELSE
                    ra    <= a;
                    rb    <= b;
                    state <= S_ABS;
                END IF;
            ELSE
                CASE state IS
                    WHEN S_MUL =>
                        -- prod est fige a ce front : done et res au cycle suivant
                        state <= S_MULR;

                    WHEN S_MULR =>
                        -- uc ecrit rd a ce front ; res reste valide ensuite
                        res_r <= mres;
                        state <= S_DONE;

                    WHEN S_ABS =>
                        -- Valeurs absolues et signes du resultat
                        sa := ra(31) AND NOT op(0);              -- DIV, REM : signe
                        sb := rb(31) AND NOT op(0);
                        IF sa = '1' THEN dvd <= unsigned(-signed(ra)); ELSE dvd <= unsigned(ra); END IF;
                        IF sb = '1' THEN dvs <= unsigned(-signed(rb)); ELSE dvs <= unsigned(rb); END IF;
                        neg_q <= sa XOR sb;
                        neg_r <= sa;
                        rem_r <= (OTHERS => '0');
                        quo   <= (OTHERS => '0');
                        cnt   <= to_unsigned(32, 6);
                        IF rb = x"00000000" THEN
                            -- Division par 0 : quotient = -1, reste = dividende
                            IF op(1) = '0' THEN
                                res_r <= (OTHERS => '1');
                            ELSE
                                res_r <= ra;
                            END IF;
                            state <= S_DONE;
                        ELSE
                            state <= S_DIV;
                        END IF;

                    WHEN S_DIV =>
                        IF rem_r = 0 AND dvd(31 downto 24) = 0 AND cnt >= 8 THEN
                            -- Sortie anticipee : 8 bits de quotient nuls d'un coup
                            dvd <= dvd(23 downto 0) & x"00";
                            quo <= quo(23 downto 0) & x"00";
                            cnt <= cnt - 8;
                            IF cnt = 8 THEN
                                state <= S_SIGN;
                            END IF;
                        ELSE
                            r1 := rem_r(31 downto 0) & dvd(31);
                            t  := r1 - ('0' & dvs);
                            dvd <= dvd(30 downto 0) & '0';
                            IF t(32) = '0' THEN                   -- r1 >= dvs
                                rem_r <= t;
                                quo   <= quo(30 downto 0) & '1';
                            ELSE
                                rem_r <= r1;
                                quo   <= quo(30 downto 0) & '0';
                            END IF;
                            cnt <= cnt - 1;
                            IF cnt = 1 THEN
                                state <= S_SIGN;
                            END IF;
                        END IF;

                    WHEN S_SIGN =>
                        -- Fin de division : signes du quotient et du reste
                        IF op(1) = '0' THEN
                            IF neg_q = '1' THEN
                                res_r <= std_logic_vector(-signed(quo));
                            ELSE
                                res_r <= std_logic_vector(quo);
                            END IF;
                        ELSE
                            IF neg_r = '1' THEN
                                res_r <= std_logic_vector(-signed(rem_r(31 downto 0)));
                            ELSE
                                res_r <= std_logic_vector(rem_r(31 downto 0));
                            END IF;
                        END IF;
                        state <= S_DONE;

                    WHEN OTHERS =>
                        NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END ARCHITECTURE;
