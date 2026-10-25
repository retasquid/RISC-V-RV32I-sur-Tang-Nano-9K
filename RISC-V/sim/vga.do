# Simulation du module VGA (VRAM double port + generateur 640x400) avec les
# primitives Gowin (rPLL, DPB) de la bibliotheque de simulation de Gowin EDA.
#   batch : cd RISC-V/sim && vsim -c -do "do vga.do; quit -f"
# Le resultat est la ligne "TB_RESULT: SUCCES" ou "TB_RESULT: ECHEC".
# Adapter GOWIN_SIMLIB si Gowin est installe ailleurs (ou : set GOWIN_SIMLIB ... avant do).

if {![info exists GOWIN_SIMLIB]} {
    set GOWIN_SIMLIB D:/logiciel/TangNano/Gowin/Gowin_V1.9.11.01_Education_x64/IDE/simlib/gw1n
}

if {[file exists work]} { vdel -lib work -all }
vlib work

vcom -2008 -quiet $GOWIN_SIMLIB/prim_sim.vhd
vcom -2008 -quiet ../src/gowin_rpll/gowin_rpll.vhd ../src/gowin_dpb/gowin_dpb.vhd
vcom -2008 -quiet ../src/vgaSigGen.vhd ../src/vgaMemInterface.vhd ../src/vgaModule.vhd
vcom -2008 -quiet ../tb/tb_pkg.vhd ../tb/vga_tb.vhd

vsim -quiet vga_tb

if {![batch_mode]} {
    add wave /vga_tb/clk_pix /vga_tb/hs /vga_tb/vs /vga_tb/r
    add wave /vga_tb/m /vga_tb/rdy /vga_tb/din_bus
    add wave /vga_tb/dut/addr_vga /vga_tb/dut/cs_vga
}

run -all
