LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY core IS
    PORT(
        --MEMORY BUS
        dout              : out std_logic_vector(31 downto 0);
        din               : in std_logic_vector(31 downto 0);
        adr               : out std_logic_vector(31 downto 0);
        rdy               : in std_logic;
        we, rd            : out std_logic;
        wenb              : out std_logic_vector(3 downto 0);
        instRet           : out std_logic;  -- 1 cycle a la fin de chaque instruction
        --CLOCK & RESET
        clk                 : in std_logic;
        rst                 : in std_logic
    );
END ENTITY;

ARCHITECTURE coreV1 OF core IS
    COMPONENT mulDiv
        PORT(
            clk, rst    : in  std_logic;
            start       : in  std_logic;
            f3          : in  std_logic_vector(2 downto 0);
            a, b        : in  std_logic_vector(31 downto 0);
            done        : out std_logic;
            res         : out std_logic_vector(31 downto 0)
        );
    END COMPONENT;

    COMPONENT alu
        PORT(
            s1, s2          : in std_logic_vector(31 downto 0);
            opcode          : in std_logic_vector(2 downto 0);
            alt, brchEn     : in std_logic;
            d               : out std_logic_vector(31 downto 0);
            branch          : out std_logic
        );
    END COMPONENT;

    COMPONENT regFile
        PORT(
            s1, s2      : out std_logic_vector(31 downto 0);
            rs1, rs2    : in std_logic_vector(4 downto 0);
            d           : in std_logic_vector(31 downto 0);
            rd          : in std_logic_vector(4 downto 0);
            clk, we     : in std_logic
        );
    END COMPONENT;

    COMPONENT immDecoder
        PORT(
            inst    : in std_logic_vector(31 downto 0);
            instype : in std_logic_vector(2 downto 0);
            imm     : out std_logic_vector(31 downto 0)
        );
    END COMPONENT;

    COMPONENT pc
        PORT(
            imm, d                          : in std_logic_vector(31 downto 0);
            adr, adr4                       : out std_logic_vector(31 downto 0);
            pcsrc, brch, clk, rst, en       : in std_logic
        );
    END COMPONENT;

    COMPONENT MUX2_32
        PORT(
            in0, in1        : in    std_logic_vector(31 downto 0);
            output          : out   std_logic_vector(31 downto 0);
            sel             : in    std_logic
        );
    END COMPONENT;

    COMPONENT MUX4_32
        PORT(
            in0, in1, in2, in3      : in    std_logic_vector(31 downto 0);
            output                  : out   std_logic_vector(31 downto 0);
            sel                     : in    std_logic_vector(1 downto 0)
        );
    END COMPONENT;

    COMPONENT uc
        PORT(
            opcode                  : in    std_logic_vector(6 downto 0);
            fun3                    : in    std_logic_vector(2 downto 0);
            fun7                    : in    std_logic_vector(6 downto 0);
            rdy                     : in    std_logic;
            mdDone                  : in    std_logic;

            enPc, rd, enIR          : out   std_logic;
            we, pcSrc               : out   std_logic;
            selInRd                 : out   std_logic_vector(1 downto 0);
            insType, opAlu          : out   std_logic_vector(2 downto 0);
            wEn, selS1Alu, selS2Alu : out   std_logic;
            altAlu, brchEn          : out   std_logic;
            adrSel                  : out   std_logic;
            enAdr                   : out   std_logic;
            mdStart, selMd          : out   std_logic;
            clk, rst                : in    std_logic
        );
    END COMPONENT;

    COMPONENT signExtender
        PORT(
            d_din       : in  std_logic_vector(31 downto 0);
            func3       : in  std_logic_vector(2 downto 0);
            adr2        : in  std_logic_vector(1 downto 0);
            dLsu        : out std_logic_vector(31 downto 0)
        );
    END COMPONENT;

    SIGNAL s1, s2, d, inst, imm, dAlu, s2Alu, s1Alu, adr4       : std_logic_vector(31 downto 0);
    SIGNAL d_din_ext, adrPc, adresse                            : std_logic_vector(31 downto 0);
    SIGNAL opcode, f7                                           : std_logic_vector(6 downto 0);
    SIGNAL rs1, rs2, rdest                                      : std_logic_vector(4 downto 0);
    SIGNAL wenb_unshift, wenb_shift                             : std_logic_vector(3 downto 0);
    SIGNAL insType, opAlu, f3                                   : std_logic_vector(2 downto 0);
    SIGNAL selInRd                                              : std_logic_vector(1 downto 0);
    SIGNAL pcSrc, enPc, selS2Alu, selS1Alu , brch, wEn          : std_logic;
    SIGNAL brchEn, altAlu, enIR, adrSel, enAdr                  : std_logic;
    SIGNAL adrMem                                               : std_logic_vector(31 downto 0) := (OTHERS => '0');
    -- Extension M
    SIGNAL mdStart, mdDone, selMd                               : std_logic;
    SIGNAL mdRes, dWb                                           : std_logic_vector(31 downto 0);

BEGIN

    instRet <= enPc;
    rs1     <= inst(19 downto 15);
    rs2     <= inst(24 downto 20);
    rdest   <= inst(11 downto 7);
    opcode  <= inst(6 downto 0);
    f3      <= inst(14 downto 12);
    f7      <= inst(31 downto 25);
    adresse <= adrMem WHEN adrSel = '1' ELSE adrPc;
    adr     <= adresse;
    dout    <= s2;
    
    wenb_unshift <= "0001" WHEN f3="000" ELSE
                    "0011" WHEN f3="001" ELSE
                    "1111";
    wenb_shift <= wenb_unshift(2 downto 0) & '0' WHEN adresse(0)='1' ELSE wenb_unshift;
    wenb <= wenb_shift(1 downto 0) & "00" WHEN adresse(1)='1' ELSE wenb_shift;

    -- Adresse des loads/stores, enregistree a la fin de S_DECODE
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF enAdr = '1' THEN
                adrMem <= dAlu;
            END IF;
        END IF;
    END PROCESS;

    -- Instruction Register
    PROCESS(clk)
    BEGIN
        IF rising_edge(clk) THEN
            IF rst = '1' THEN
                inst <= x"00000000";
            ELSIF enIR = '1' THEN
                inst <= din;
            ELSE
                inst <= inst;
            END iF;
        END iF;
    END PROCESS;

    u1 : alu PORT MAP(
        s1      =>   s1Alu,
        s2      =>   s2Alu,
        opcode  =>   opAlu,
        alt  =>   altAlu,
        brchEn  =>   brchEn,
        d       =>   dAlu,
        branch  =>   brch
    );

    u2 : regFile PORT MAP(
        s1 =>   s1,
        s2 =>   s2,
        rs1 =>  rs1,
        rs2 =>  rs2,
        d =>    dWb,
        rd =>   rdest,
        clk =>  clk,
        we =>   wEn
    );
    
    u3 : immDecoder PORT MAP(
        inst =>     inst,
        instype =>  insType,
        imm =>      imm
    );

    u4 : pc PORT MAP(
        imm =>      imm,
        d =>        dAlu,
        adr =>      adrPc,
        adr4 =>     adr4,
        pcsrc =>    pcSrc,
        brch =>     brch,
        clk =>      clk,
        rst =>      rst,
        en =>       enPc    
    );

    u5 : MUX2_32 PORT MAP(
        in0 =>      s1,
        in1 =>      adrPc,
        sel =>      selS1Alu,
        output =>   s1Alu
    );

    u6 : MUX2_32 PORT MAP(
        in0 =>      s2,
        in1 =>      imm,
        sel =>      selS2Alu,
        output =>   s2Alu
    );

    u7 : MUX4_32 PORT MAP(
        in0 =>      dAlu,
        in1 =>      d_din_ext,
        in2 =>      imm,
        in3 =>      adr4,
        sel =>      selInRd,
        output =>   d
    );

    u8 : uc PORT MAP(
        opcode => opcode,
        fun3 => f3,
        fun7 => f7,
        rdy =>rdy,
        mdDone => mdDone,

        enPc=> enPc,
        rd => rd,
        enIR => enIR,
        we => we,
        pcSrc => pcSrc,
        selInRd => selInRd,
        insType => insType,
        opAlu => opAlu,
        wEn => wEn,
        selS1Alu => selS1Alu,
        selS2Alu => selS2Alu,
        altAlu => altAlu,
        brchEn => brchEn,
        adrSel => adrSel,
        enAdr => enAdr,
        mdStart => mdStart,
        selMd => selMd,
        clk => clk,
        rst => rst
    );

    -- Extension M : MUL* / DIV* / REM* (operandes rs1, rs2)
    u10 : mulDiv PORT MAP(
        clk   => clk,
        rst   => rst,
        start => mdStart,
        f3    => f3,
        a     => s1,
        b     => s2,
        done  => mdDone,
        res   => mdRes
    );
    dWb <= mdRes WHEN selMd = '1' ELSE d;

    u9 : signExtender PORT MAP(
        d_din =>   din,
        func3 =>   f3,
        adr2 =>    adresse(1 downto 0),
        dLsu =>    d_din_ext
    );
END ARCHITECTURE;