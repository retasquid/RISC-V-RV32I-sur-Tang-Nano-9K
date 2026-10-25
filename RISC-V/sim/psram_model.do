# Autotest du modele PSRAM LY68L6400 (doit afficher "MODEL_SELFTEST: SUCCES").
#   batch : cd RISC-V/sim && vsim -c -do "do psram_model.do; quit -f"
if {[file exists work]} { vdel -lib work -all }
vlib work
vcom -2008 -quiet ../tb/psram_model.vhd ../tb/psram_model_tb.vhd
vsim -quiet tb_psram_model
run -all
