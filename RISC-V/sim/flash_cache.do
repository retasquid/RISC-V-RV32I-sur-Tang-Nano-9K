# Simulation du cache flash (flash_cache + qspi_flash) avec le modele GD25Q32C.
#   GUI   : dans ModelSim, cd RISC-V/sim puis "do flash_cache.do"
#   batch : cd RISC-V/sim && vsim -c -do "do flash_cache.do; quit -f"
# Generics : vsim ... -gFAST=false (maitre lent), -gSCLK_DIV=1|2|3
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet ../src/clkDiv.vhd ../src/qspi_master.vhd ../src/qspi_flash.vhd ../src/flash_cache.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/flash_model.vhd ../tb/flash_cache_tb.vhd

vsim -quiet tb_flash_cache

if {![batch_mode]} {
    add wave -divider BUS
    add wave /tb_flash_cache/m /tb_flash_cache/rdy /tb_flash_cache/din_bus
    add wave -divider CACHE
    add wave /tb_flash_cache/dut/state /tb_flash_cache/dut/hit /tb_flash_cache/dut/miss
    add wave /tb_flash_cache/dut/f_idx /tb_flash_cache/dut/f_w /tb_flash_cache/dut/f_val
    add wave /tb_flash_cache/dut/q_rd /tb_flash_cache/dut/q_rdy
    add wave -divider QSPI
    add wave /tb_flash_cache/flash_cs_n /tb_flash_cache/flash_clk
}

run -all
