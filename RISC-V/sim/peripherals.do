# Simulation des peripheriques (GPIO + UART).
#   GUI   : dans ModelSim, cd RISC-V/sim puis "do peripherals.do"
#   batch : cd RISC-V/sim && vsim -c -do "do peripherals.do; quit -f"
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet ../src/clkDiv.vhd ../src/uart.vhd ../src/peripherals.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/peripherals_tb.vhd

vsim -quiet tb_peripherals

if {![batch_mode]} {
    add wave -divider BUS
    add wave /tb_peripherals/enCore /tb_peripherals/cs /tb_peripherals/m /tb_peripherals/rdy /tb_peripherals/din_bus
    add wave -divider IO
    add wave /tb_peripherals/gpio /tb_peripherals/uart_tx /tb_peripherals/uart_rx
    add wave -divider DUT
    add wave /tb_peripherals/dut/ack /tb_peripherals/dut/uart_rx_pending /tb_peripherals/dut/uart_rx_toggle /tb_peripherals/dut/rx_byte
}

run -all
