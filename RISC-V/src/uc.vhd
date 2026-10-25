--------------------------------------------------------------------------------
-- uc.vhd
-- Unite de controle du coeur multicycle. Tout est sur le front MONTANT de clk,
-- sans clock-enable : le coeur avance a chaque cycle, rdy gere seul les attentes.
--
--   S_FETCH  : rd = 1, adr = PC. Quand rdy = 1 : IR <= din (enIR, Mealy),
--              rd retombe -> S_DECODE
--   S_DECODE : IR valide. Load/store : rd/we leves, adr = resultat ALU
--              (enregistre dans core : enAdr)
--              -> S_MEM. Sinon : ecriture de rd et mise a jour du PC dans ce
--              cycle (wEn/enPc, Mealy), rd leve pour le fetch suivant -> S_FETCH
--   S_MEM    : attente de rdy. Load : ecriture de rd avec din ; PC + 4 ;
--              rd/we retombent -> S_GAP
--   S_GAP    : rd = we = 0 pendant un cycle, puis -> S_FETCH
--   S_MULDIV : extension M (opcode OP, funct7 = 0000001) : mdStart a la fin
--              de S_DECODE fige les operandes dans mulDiv ; attente de
--              mdDone, puis ecriture de rd (selMd) et PC + 4 (Mealy), rd leve
--              pour le fetch suivant -> S_FETCH. rd = we = 0 pendant l'attente.
-- Entre deux requetes, rd et we restent a 0 au moins un cycle (S_DECODE ou
-- S_GAP) : l'esclave precedent voit la fin de la requete et baisse rdy avant
-- que uc ne recommence a l'echantillonner (protocole commun, CLAUDE.md §3).
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY uc IS
    PORT(
        opcode                  : in    std_logic_vector(6 downto 0);
        fun3                    : in    std_logic_vector(2 downto 0);
        fun7                    : in    std_logic_vector(6 downto 0);
        rdy                     : in    std_logic;
        mdDone                  : in    std_logic;   -- resultat de mulDiv pret

        enPc, rd, enIR          : out   std_logic;
        we, pcSrc               : out   std_logic;
        selInRd                 : out   std_logic_vector(1 downto 0);
        insType, opAlu          : out   std_logic_vector(2 downto 0);
        wEn, selS1Alu, selS2Alu : out   std_logic;
        altAlu, brchEn          : out   std_logic;
        adrSel                  : out   std_logic;
        enAdr                   : out   std_logic;   -- capture de l'adresse load/store
        mdStart                 : out   std_logic;   -- demarrage de mulDiv
        selMd                   : out   std_logic;   -- rd <= resultat de mulDiv
        clk, rst                : in    std_logic
    );
END ENTITY;

ARCHITECTURE ucV2 OF uc IS
    TYPE state_t IS (S_FETCH, S_DECODE, S_MEM, S_GAP, S_MULDIV);

    SIGNAL state                                            : state_t := S_GAP;
    SIGNAL store, load, opi, op, jal, brch, funSlt, funSra  : std_logic;
    SIGNAL lui, sys, fence, jalr, auipc                     : std_logic;
    SIGNAL mem, writesRd, md                                : std_logic;
    SIGNAL rd_r, we_r, adrSel_r                             : std_logic := '0';
BEGIN

    rd     <= rd_r;
    we     <= we_r;
    adrSel <= adrSel_r;

    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                state    <= S_GAP;
                rd_r     <= '0';
                we_r     <= '0';
                adrSel_r <= '0';
            ELSE
                CASE state IS
                    WHEN S_FETCH =>
                        IF rdy = '1' THEN
                            rd_r  <= '0';
                            state <= S_DECODE;
                        END IF;

                    WHEN S_DECODE =>
                        IF mem = '1' THEN
                            rd_r     <= load;
                            we_r     <= store;
                            adrSel_r <= '1';
                            state    <= S_MEM;
                        ELSIF md = '1' THEN
                            state    <= S_MULDIV;
                        ELSE
                            rd_r     <= '1';
                            state    <= S_FETCH;
                        END IF;

                    WHEN S_MEM =>
                        IF rdy = '1' THEN
                            rd_r     <= '0';
                            we_r     <= '0';
                            adrSel_r <= '0';
                            state    <= S_GAP;
                        END IF;

                    WHEN S_GAP =>
                        rd_r  <= '1';
                        state <= S_FETCH;

                    WHEN S_MULDIV =>
                        IF mdDone = '1' THEN
                            rd_r  <= '1';
                            state <= S_FETCH;
                        END IF;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

    -- Validations du chemin de donnees (Mealy) : prises en compte au front
    -- montant qui termine le cycle courant
    enIR <= '1' WHEN state = S_FETCH AND rdy = '1' ELSE '0';
    -- L'adresse d'un load/store est enregistree a la fin de S_DECODE : en
    -- S_MEM, le bus voit un registre et non la sortie de l'ALU (timing)
    enAdr <= '1' WHEN state = S_DECODE ELSE '0';
    enPc <= '1' WHEN (state = S_DECODE AND mem = '0' AND md = '0') OR (state = S_MEM AND rdy = '1') OR
                     (state = S_MULDIV AND mdDone = '1') ELSE '0';
    wEn  <= '1' WHEN writesRd = '1' AND ((state = S_DECODE AND mem = '0' AND md = '0') OR
                                         (state = S_MEM AND rdy = '1' AND load = '1') OR
                                         (state = S_MULDIV AND mdDone = '1')) ELSE '0';
    -- Extension M : operandes figes dans mulDiv a la fin de S_DECODE
    mdStart <= '1' WHEN state = S_DECODE AND md = '1' ELSE '0';
    selMd   <= md;

    store <= '1' WHEN (opcode="0100011") ELSE '0';
    load  <= '1' WHEN (opcode="0000011") ELSE '0';
    opi   <= '1' WHEN (opcode="0010011") ELSE '0';
    op    <= '1' WHEN (opcode="0110011") ELSE '0';
    jal   <= '1' WHEN (opcode="1101111") ELSE '0';
    brch  <= '1' WHEN (opcode="1100011") ELSE '0';
    lui   <= '1' WHEN (opcode="0110111") ELSE '0';
    sys   <= '1' WHEN (opcode="1110011") ELSE '0';
    fence <= '1' WHEN (opcode="0001111") ELSE '0';
    jalr  <= '1' WHEN (opcode="1100111") ELSE '0';
    auipc <= '1' WHEN (opcode="0010111") ELSE '0';

    mem      <= load XOR store;
    md       <= '1' WHEN op = '1' AND fun7 = "0000001" ELSE '0';
    writesRd <= op OR opi OR load OR lui OR auipc OR jal OR jalr;

    pcSrc <= jal OR jalr;
    selInRd <= "01" WHEN load = '1' ELSE
               "10" WHEN lui = '1' ELSE
               "11" WHEN (jal OR jalr)='1' ELSE
               "00";
    insType <= "010" WHEN store = '1' ELSE
               "011" WHEN brch = '1' ELSE
               "100" WHEN (lui OR auipc)='1' ELSE
               "101" WHEN jal = '1' ELSE
               "001";
    selS1Alu <= jal OR auipc;
    selS2Alu <= NOT(fence OR brch OR op);

    funSlt <= '1' WHEN fun3(2 downto 1)="01" ELSE '0';
    funSra <= '1' WHEN fun3="101" ELSE '0';
    altAlu <= ((fun7(5) OR funSlt) AND op) OR (((fun7(5) AND funSra) OR funSlt) AND opi) OR brch;

    opAlu <= fun3 WHEN (opi OR op OR brch)='1' ELSE "000";
    brchEn <= brch;

END ARCHITECTURE;
