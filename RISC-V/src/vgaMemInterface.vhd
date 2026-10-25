--------------------------------------------------------------------------------
-- vgaMemInterface.vhd
-- VRAM de 32 Kio (8192 mots de 32 bits) en 4 BRAM double port 8K x 8 (une par
-- octet), lecture "bypass" : 1 cycle de latence.
--   port A : coeur (CLK_VRAM = clk27), lecture/ecriture, protocole esclave
--            commun : requete traitee une fois quand CS AND (RD XOR WR),
--            RDY et DOUT tenus jusqu'a ce que RD et WR retombent
--   port B : generateur video (CLK_VGA), lecture seule
-- Ecritures par octets : WENB_VRAM vient du coeur deja positionne sur les
-- octets vises ; la donnee n'est pas decalee (octet 0 de DIN = premier octet
-- ecrit), elle est donc placee selon ADDR_VRAM(1:0).
--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaMemInterface IS
    PORT (
        RST       : in  std_logic;
        -- CPU interface
        CLK_VRAM  : in  std_logic;
        CS_VRAM   : in  std_logic;
        WR_VRAM   : in  std_logic;
        RD_VRAM   : in  std_logic;
        RDY_VRAM  : out std_logic;
        WENB_VRAM : in  std_logic_vector(3 DOWNTO 0);
        ADDR_VRAM : in  std_logic_vector(14 DOWNTO 0);
        DIN_VRAM  : in  std_logic_vector(31 DOWNTO 0);
        DOUT_VRAM : out std_logic_vector(31 DOWNTO 0);
        -- VGA interface
        CLK_VGA   : in  std_logic;
        RST_VGA   : in  std_logic;
        CS_VGA    : in  std_logic;
        ADDR_VGA  : in  std_logic_vector(12 DOWNTO 0);
        DOUT_VGA  : out std_logic_vector(31 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE vgaMemInterfaceV2 OF vgaMemInterface IS
    COMPONENT Gowin_DPB
    PORT (
        douta: out std_logic_vector(7 downto 0);
        doutb: out std_logic_vector(7 downto 0);
        clka: in std_logic;
        ocea: in std_logic;
        cea: in std_logic;
        reseta: in std_logic;
        wrea: in std_logic;
        clkb: in std_logic;
        oceb: in std_logic;
        ceb: in std_logic;
        resetb: in std_logic;
        wreb: in std_logic;
        ada: in std_logic_vector(12 downto 0);
        dina: in std_logic_vector(7 downto 0);
        adb: in std_logic_vector(12 downto 0);
        dinb: in std_logic_vector(7 downto 0)
    );
    END COMPONENT;

    SIGNAL ack      : std_logic := '0';
    SIGNAL accept   : std_logic;
    SIGNAL dinSh    : std_logic_vector(31 downto 0);
    SIGNAL wrByte   : std_logic_vector(3 downto 0);
BEGIN

    RDY_VRAM <= ack;
    accept   <= CS_VRAM AND (RD_VRAM XOR WR_VRAM) AND NOT ack;

    -- Ecriture au cycle d'acceptation seulement, sur les octets de WENB
    gen_wr : FOR i IN 0 TO 3 GENERATE
        wrByte(i) <= accept AND WR_VRAM AND WENB_VRAM(i);
    END GENERATE;

    WITH ADDR_VRAM(1 downto 0) SELECT
    dinSh <= DIN_VRAM                          WHEN "00",
             DIN_VRAM(23 downto 0) & x"00"     WHEN "01",
             DIN_VRAM(15 downto 0) & x"0000"   WHEN "10",
             DIN_VRAM(7 downto 0)  & x"000000" WHEN OTHERS;

    PROCESS(CLK_VRAM)
    BEGIN
        IF rising_edge(CLK_VRAM) THEN
            IF RST = '1' THEN
                ack <= '0';
            ELSIF accept = '1' THEN
                ack <= '1';
            ELSIF RD_VRAM = '0' AND WR_VRAM = '0' THEN
                ack <= '0';
            END IF;
        END IF;
    END PROCESS;

    -- Port A lu en continu : la donnee de l'adresse presentee au cycle
    -- d'acceptation est disponible quand RDY monte, et reste stable ensuite
    gen_ram : FOR i IN 0 TO 3 GENERATE
        ram_8k_8b : Gowin_DPB
        PORT MAP (
            douta  => DOUT_VRAM(8*i+7 downto 8*i),
            doutb  => DOUT_VGA(8*i+7 downto 8*i),
            clka   => CLK_VRAM,
            ocea   => '1',
            cea    => '1',
            reseta => RST,
            wrea   => wrByte(i),
            clkb   => CLK_VGA,
            oceb   => '1',
            ceb    => CS_VGA,
            resetb => RST_VGA,
            wreb   => '0',
            ada    => ADDR_VRAM(14 downto 2),
            dina   => dinSh(8*i+7 downto 8*i),
            adb    => ADDR_VGA,
            dinb   => x"00"
        );
    END GENERATE;

END ARCHITECTURE;
