# Simulation du controleur flash (qspi_flash) avec le modele GD25Q32C.
#   GUI   : dans ModelSim, cd RISC-V/sim puis "do qspi_flash.do"
#   batch : cd RISC-V/sim && vsim -c -do "do qspi_flash.do; quit -f"
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet ../src/clkDiv.vhd ../src/qspi_master.vhd ../src/qspi_flash.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/flash_model.vhd ../tb/qspi_flash_tb.vhd

vsim -quiet tb_qspi_flash

if {![batch_mode]} {
    add wave -divider BUS
    add wave /tb_qspi_flash/enCore /tb_qspi_flash/cs /tb_qspi_flash/m /tb_qspi_flash/rdy /tb_qspi_flash/din_bus
    add wave -divider QSPI
    add wave /tb_qspi_flash/flash_cs_n /tb_qspi_flash/flash_clk
    add wave /tb_qspi_flash/sio0 /tb_qspi_flash/sio1 /tb_qspi_flash/sio2 /tb_qspi_flash/sio3
    add wave -divider MODELE
    add wave /tb_qspi_flash/cont_mode /tb_qspi_flash/txn_count /tb_qspi_flash/cmd_count
    add wave /tb_qspi_flash/last_addr /tb_qspi_flash/model_errors
    add wave -divider DUT
    add wave /tb_qspi_flash/dut/state /tb_qspi_flash/dut/cont
}

run -all
