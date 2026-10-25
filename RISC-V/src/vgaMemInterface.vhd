LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY vgaMemInterface IS
    PORT (
        RST       : in  STD_LOGIC;
        -- CPU interface
        CLK_VRAM  : in  STD_LOGIC;
        CS_VRAM   : in  STD_LOGIC;
        WR_VRAM   : in  STD_LOGIC;
        RD_VRAM   : in  STD_LOGIC;
        RDY_VRAM  : out  STD_LOGIC;
        WENB_VRAM : in  STD_LOGIC_VECTOR(3 DOWNTO 0);
        ADDR_VRAM : in  STD_LOGIC_VECTOR(14 DOWNTO 0);
        DIN_VRAM  : in  STD_LOGIC_VECTOR(31 DOWNTO 0);
        DOUT_VRAM : out STD_LOGIC_VECTOR(31 DOWNTO 0);
        -- VGA interface
        CLK_VGA  : in  STD_LOGIC;
        CS_VGA   : in  STD_LOGIC;
        ADDR_VGA : in  STD_LOGIC_VECTOR(12 DOWNTO 0);
        DOUT_VGA : out STD_LOGIC_VECTOR(31 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE vgaMemInterfaceV1 OF vgaMemInterface IS
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

    SIGNAL RAM0_WR, RAM1_WR, RAM2_WR, RAM3_WR               : std_logic;
    SIGNAL RDY_VRAM_Z_TMP, RDY_VRAM_Z                       : std_logic;
    SIGNAL RAM0_DIN, RAM1_DIN, RAM2_DIN, RAM3_DIN           : std_logic_vector(7 downto 0);
    SIGNAL DOUT_VRAM_Z                                      : std_logic_vector(31 downto 0);
BEGIN
    RDY_VRAM <= RDY_VRAM_Z WHEN CS_VRAM = '1' ELSE 'Z';
    DOUT_VRAM <= DOUT_VRAM_Z WHEN CS_VRAM = '1' ELSE (OTHERS => 'Z');

    PROCESS(CLK_VRAM)
    BEGIN
        IF(rising_edge(CLK_VRAM)) THEN
            RDY_VRAM_Z_TMP <= RD_VRAM OR WR_VRAM;
            RDY_VRAM_Z <= RDY_VRAM_Z_TMP;
        END IF;
    END PROCESS;

    ram0_8k_8b: Gowin_DPB
    PORT MAP (
        douta => DOUT_VRAM_Z(7 downto 0),
        doutb => DOUT_VGA(7 downto 0),
        clka => CLK_VRAM,
        ocea => CS_VRAM,
        cea => CS_VRAM,
        reseta => RST,
        wrea => RAM0_WR,
        clkb => CLK_VGA,
        oceb => CS_VGA,
        ceb => CS_VGA,
        resetb => RST,
        wreb => '0',
        ada => ADDR_VRAM(14 downto 2),
        dina => RAM0_DIN,
        adb => ADDR_VGA,
        dinb => x"00"
    );
    
    ram1_8k_8b: Gowin_DPB
    PORT MAP (
        douta => DOUT_VRAM_Z(15 downto 8),
        doutb => DOUT_VGA(15 downto 8),
        clka => CLK_VRAM,
        ocea => CS_VRAM,
        cea => CS_VRAM,
        reseta => RST,
        wrea => RAM1_WR,
        clkb => CLK_VGA,
        oceb => CS_VGA,
        ceb => CS_VGA,
        resetb => RST,
        wreb => '0',
        ada => ADDR_VRAM(14 downto 2),
        dina => RAM1_DIN,
        adb => ADDR_VGA,
        dinb => x"00"
    );
    
    ram2_8k_8b : Gowin_DPB
    PORT MAP (
        douta => DOUT_VRAM_Z(23 downto 16),
        doutb => DOUT_VGA(23 downto 16),
        clka => CLK_VRAM,
        ocea => CS_VRAM,
        cea => CS_VRAM,
        reseta => RST,
        wrea => RAM2_WR,
        clkb => CLK_VGA,
        oceb => CS_VGA,
        ceb => CS_VGA,
        resetb => RST,
        wreb => '0',
        ada => ADDR_VRAM(14 downto 2),
        dina => RAM2_DIN,
        adb => ADDR_VGA,
        dinb => x"00"
    );
    
    ram3_8k_8b: Gowin_DPB
    PORT MAP (
        douta => DOUT_VRAM_Z(31 downto 24),
        doutb => DOUT_VGA(31 downto 24),
        clka => CLK_VRAM,
        ocea => CS_VRAM,
        cea => CS_VRAM,
        reseta => RST,
        wrea => RAM3_WR,
        clkb => CLK_VGA,
        oceb => CS_VGA,
        ceb => CS_VGA,
        resetb => RST,
        wreb => '0',
        ada => ADDR_VRAM(14 downto 2),
        dina => RAM3_DIN,
        adb => ADDR_VGA,
        dinb => x"00"
    );

    -- WENB logic for Data In
    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM0_DIN <= DIN_VRAM(7 downto 0)    WHEN "00",
                x"00"                   WHEN "01",
                x"00"                   WHEN "10",
                x"00"                   WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM1_DIN <= DIN_VRAM(15 downto 8)   WHEN "00",
                DIN_VRAM(7 downto 0)    WHEN "01",
                x"00"                   WHEN "10",
                x"00"                   WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM2_DIN <= DIN_VRAM(23 downto 16)  WHEN "00",
                DIN_VRAM(15 downto 8)   WHEN "01",
                DIN_VRAM(7 downto 0)    WHEN "10",
                x"00"                   WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM3_DIN <= DIN_VRAM(31 downto 24)  WHEN "00",
                DIN_VRAM(23 downto 16)  WHEN "01",
                DIN_VRAM(15 downto 8)   WHEN "10",
                DIN_VRAM(7 downto 0)    WHEN OTHERS;


    -- WENB logic for Write
    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM0_WR  <= WENB_VRAM(0) WHEN "00",
                '0'          WHEN "01",
                '0'          WHEN "10",
                '0'          WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM1_WR  <= WENB_VRAM(1) WHEN "00",
                WENB_VRAM(0) WHEN "01",
                '0'          WHEN "10",
                '0'          WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM2_WR  <= WENB_VRAM(2) WHEN "00",
                WENB_VRAM(1) WHEN "01",
                WENB_VRAM(0) WHEN "10",
                '0'          WHEN OTHERS;

    WITH ADDR_VRAM(1 downto 0) SELECT
    RAM3_WR  <= WENB_VRAM(3) WHEN "00",
                WENB_VRAM(2) WHEN "01",
                WENB_VRAM(1) WHEN "10",
                WENB_VRAM(0) WHEN OTHERS;

END ARCHITECTURE;