# Simulation du controleur PSRAM (qspi_sram) avec le modele LY68L6400.
#   GUI   : dans ModelSim, cd RISC-V/sim puis "do qspi_sram.do"
#   batch : cd RISC-V/sim && vsim -c -do "do qspi_sram.do; quit -f"
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet ../src/clkDiv.vhd ../src/qspi_master.vhd ../src/qspi_sram.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/psram_model.vhd ../tb/qspi_sram_tb.vhd

vsim -quiet tb_qspi_sram

if {![batch_mode]} {
    add wave -divider BUS
    add wave /tb_qspi_sram/enCore /tb_qspi_sram/cs /tb_qspi_sram/m /tb_qspi_sram/rdy /tb_qspi_sram/din_bus
    add wave -divider QSPI
    add wave /tb_qspi_sram/sram_cs_n /tb_qspi_sram/sram_clk
    add wave /tb_qspi_sram/sio0 /tb_qspi_sram/sio1 /tb_qspi_sram/sio2 /tb_qspi_sram/sio3
    add wave -divider MODELE
    add wave /tb_qspi_sram/qpi_mode /tb_qspi_sram/txn_count /tb_qspi_sram/last_addr /tb_qspi_sram/model_errors
    add wave -divider DUT
    add wave /tb_qspi_sram/dut/state
}

run -all
