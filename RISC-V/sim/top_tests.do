# Tests systeme : top complet + modeles flash/PSRAM, un programme par test.
# Les programmes sont compiles par : python soft/tests/build_tests.py
#
#   tous les tests (batch) : cd RISC-V/sim && vsim -c -do "do top_tests.do; quit -f"
#   un seul test           : vsim -c -do "set TEST rv32ui-jalr; do top_tests.do; quit -f"
#   GUI, avec les waves    : dans ModelSim, cd RISC-V/sim ; set TEST rv32ui-jalr ; do top_tests.do
# Resume final : "TB_RESULT: SUCCES (n/n)" ou "TB_RESULT: ECHEC (...)".

# Les IP Gowin rPLL et DPB (BRAM du VGA) sont remplacees par des modeles
# legers (tb/gowin_rpll_fast.vhd, tb/gowin_dpb_fast.vhd) : les modeles
# detailles de prim_sim ralentissent ces tests d'un facteur ~40. vga_tb, lui,
# utilise les vraies IP. prim_sim n'est donc plus necessaire ici.

if {[file exists work]} { vdel -lib work -all }
vlib work

set SRC ../src
vcom -2008 -quiet -suppress 1514 \
    ../tb/gowin_rpll_fast.vhd ../tb/gowin_dpb_fast.vhd \
    $SRC/vgaSigGen.vhd $SRC/vgaMemInterface.vhd $SRC/vgaModule.vhd \
    $SRC/MUX2_32.vhd $SRC/MUX4_32.vhd $SRC/alu.vhd $SRC/barrelShifter.vhd \
    $SRC/immDecoder.vhd $SRC/signExtender.vhd $SRC/regFile.vhd $SRC/pc.vhd \
    $SRC/uc.vhd $SRC/core.vhd $SRC/clkDiv.vhd $SRC/ROM.vhd $SRC/RAM.vhd \
    $SRC/uart.vhd $SRC/peripherals.vhd \
    $SRC/qspi_master.vhd $SRC/qspi_sram.vhd $SRC/qspi_flash.vhd $SRC/top.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/psram_model.vhd ../tb/flash_model.vhd ../tb/top_tb.vhd

if {[info exists TEST]} {
    set tests [list tests/$TEST.hex]
} else {
    set tests [lsort [glob -nocomplain tests/*.hex]]
}
if {[llength $tests] == 0} {
    echo "Aucun programme dans sim/tests : lancer d'abord python soft/tests/build_tests.py"
    return
}

set names {0 "en cours" 1 "SUCCES" 2 "ECHEC" 3 "TIMEOUT" 4 "ERREUR PROTOCOLE"}
set npass 0
set failed {}
foreach t $tests {
    set name [file rootname [file tail $t]]
    vsim -quiet -onfinish stop -gHEX_FILE=$t work.tb_top
    if {![batch_mode] && [llength $tests] == 1} {
        add wave /tb_top/dut/adr /tb_top/dut/rd /tb_top/dut/we /tb_top/dut/rdy /tb_top/dut/din /tb_top/dut/dout
        add wave /tb_top/dut/u4/adrPc /tb_top/dut/u4/inst /tb_top/dut/u4/u8/state
        add wave /tb_top/tohost_val /tb_top/status
    }
    run -all
    set st [examine -radix decimal /tb_top/status]
    set tv [examine -radix hex /tb_top/tohost_val]
    if {$st == 1} {
        incr npass
    } else {
        lappend failed "$name ([dict get $names $st], TOHOST=$tv)"
    }
    if {[batch_mode] || [llength $tests] > 1} { quit -sim }
}

echo "================ top_tests : $npass / [llength $tests] ================"
foreach f $failed { echo "  ECHEC : $f" }
if {[llength $failed] == 0} {
    echo "TB_RESULT: SUCCES ($npass/[llength $tests])"
} else {
    echo "TB_RESULT: ECHEC ([llength $failed] test(s) sur [llength $tests])"
}
