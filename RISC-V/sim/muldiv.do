# Simulation de l'unite RV32M (mulDiv).
#   GUI   : dans ModelSim, cd RISC-V/sim puis "do muldiv.do"
#   batch : cd RISC-V/sim && vsim -c -do "do muldiv.do; quit -f"
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet ../src/muldiv.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/muldiv_tb.vhd

vsim -quiet tb_muldiv

if {![batch_mode]} {
    add wave /tb_muldiv/clk /tb_muldiv/start /tb_muldiv/f3 /tb_muldiv/a /tb_muldiv/b
    add wave /tb_muldiv/done /tb_muldiv/res /tb_muldiv/dut/state /tb_muldiv/dut/cnt
}

run -all
