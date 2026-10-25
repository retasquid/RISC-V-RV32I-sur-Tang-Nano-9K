# Autotest du modele flash GD25Q32C (doit afficher "MODEL_SELFTEST: SUCCES").
#   batch : cd RISC-V/sim && vsim -c -do "do flash_model.do; quit -f"
if {[file exists work]} { vdel -lib work -all }
vlib work
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/flash_model.vhd ../tb/flash_model_tb.vhd
vsim -quiet tb_flash_model
run -all
