# CLAUDE.md — RISC-V RV32I sur Tang Nano 9K

Processeur RV32I multicycle en VHDL pour Tang Nano 9K (Gowin GW1NR-LV9QN88PC6/I5), avec PSRAM QSPI externe, flash QSPI externe, UART, GPIO et VGA (désactivé). Le logiciel est en C, compilé avec `riscv-none-elf-gcc`.

**État actuel :** le design est passé d'une architecture multi-horloges (clkCpu, clkQspi, etc.) à **une seule horloge `clk27`**. Les contrôleurs QSPI, cassés pendant la migration, ont été réécrits sur un moteur commun `qspi_master` (étapes 2 et 3). Les bus et périphériques ont été corrigés (étape 4), puis JALR (étape 5).

**Depuis l'étape 6 (2026-10-25), le cœur tourne à chaque cycle de clk27, sans clock-enable** : `uc` est sur front montant, et la flash fonctionne en flux pour les fetchs séquentiels. Les programmes vont environ 3 fois plus vite qu'avant l'étape 6.

La PSRAM, la flash et l'UART sont validés sur carte jusqu'à l'étape 4. JALR (étape 5) et l'étape 6 restent à valider sur carte. La liste des bugs restants se trouve plus bas, par ordre de priorité.

---

## 1. Arborescence

```
RISC-V/RISC-V.gprj        projet Gowin EDA (V1.9.11.01 Education)
RISC-V/src/               RTL VHDL
  top.vhd                 intégration, décodage d'adresses, bus partagé
  clkDiv.vhd              enCore (/17) et enMem (/5) ; plus instancié, sert seulement de rythme « lent » aux TB unitaires
  core.vhd                chemin de données (IR, regFile, ALU, PC, muxes)
  uc.vhd                  FSM de contrôle, front montant, sans enable (S_FETCH / S_DECODE / S_MEM / S_GAP)
  pc.vhd alu.vhd barrelShifter.vhd regFile.vhd immDecoder.vhd signExtender.vhd MUX*.vhd
  ROM.vhd                 GÉNÉRÉ par soft/elf2rom.py — ne pas éditer à la main (plus instancié : u3 commenté dans top)
  RAM.vhd                 RAM interne (instanciation commentée)
  qspi_master.vhd         moteur QSPI générique (CMD/ADDR/MODE/DUMMY/DATA, SCLK sorti d'un registre, tick = demi-période, mode flux hold/resume/hold_end)
  qspi_sram.vhd           contrôleur PSRAM LY68L6400 sur qspi_master (réécrit étape 2)
  qspi_flash.vhd          contrôleur flash GD25Q32C sur qspi_master, EBh + mode continu + flux pour les lectures séquentielles
  obsolete/               anciennes versions des fichiers réécrits (hors projet Gowin, ignoré par git)
  peripherals.vhd uart.vhd   GPIO + UART (peripherals réécrit étape 4 : un traitement par requête, GPIO sans boucle)
  vga*.vhd gowin_dpb/     VGA 640x400 monochrome + VRAM BRAM (désactivé)
  gowin_rpll/ gowin_osc/  IP Gowin (non instanciées ; rPLL = 27*13/7 ≈ 50.14 MHz)
  RISC-V.cst RISC-V.sdc   contraintes
RISC-V/tb/                testbenches (voir §5)
  tb_pkg.vhd              maître de bus qui reproduit le handshake de uc V2 (bus_cycle, bus_fetch, core_wenb) ; TB unitaires : generic FAST
  psram_model.vhd         modèle LY68L6400 avec vérification protocole/timings
  psram_model_tb.vhd      autotest du modèle (doit afficher MODEL_SELFTEST: SUCCES)
  qspi_sram_tb.vhd        TB auto-vérifiant du contrôleur PSRAM
  flash_model.vhd         modèle GD25Q32C (EBh, mode continu, 66h/99h) avec vérification protocole/timings
  flash_model_tb.vhd      autotest du modèle flash
  qspi_flash_tb.vhd       TB auto-vérifiant du contrôleur flash
  peripherals_tb.vhd      TB auto-vérifiant GPIO + UART (B1, B2)
  obsolete/               anciens TB conservés pour mémoire
  top_tb.vhd              TB système : vrai top + flash_model (programme HEX_FILE) + psram_model, résultat lu à TOHOST
RISC-V/sim/               scripts ModelSim (*.do) ; work/ et logs générés ici
  top_tests.do            lance tous les programmes de sim/tests/ sur top_tb (ou un seul : set TEST ...)
  tests/                  GÉNÉRÉ par soft/tests/build_tests.py (*.elf, *.hex, *.dump)
soft/                     C + start.s + link.ld + comp.bat + elf2rom.py + Flasher3.1/
  tests/                  programmes de test système (étape 5)
    build_tests.py        compile tout vers RISC-V/sim/tests/ (filtre optionnel : python build_tests.py jalr)
    env/                  riscv_test.h (environnement minimal sans CSR, TOHOST) + link_test.ld
    riscv-tests/          sous-ensemble des riscv-tests officiels (rv32ui, licence BSD, voir ORIGINE.txt)
    custom/               tests maison : jalr_ra.S (B6), unmapped.S (B4), c_system.c (C complet)
```

### Composants externes (datasheets fournies)

| Rôle | Puce | Points clés pour le RTL |
|---|---|---|
| RAM 0x80 | **Lyontek LY68L6400** (PSRAM 64 Mbit SPI/QPI) | À la mise sous tension : **≥150 µs avec CE# haut et CLK bas, puis RESET 66h/99h obligatoire** (§9). Démarre en SPI ; 35h → QPI, F5h → SPI. QPI 0xEB : 2 clk cmd + 6 adr + **6 wait** + données (sorties tACLK ≤ 6 ns après le front descendant). Écriture QPI 02h/38h sans wait. tCPH ≥ 50 ns, tCHD ≥ 20 ns, tCSP ≥ 2.5 ns, **tCEM ≤ 8 µs**. Page de 1 KiB. |
| FLASH 0x40 | **GigaDevice GD25Q32C** (32 Mbit, compatible Winbond) | QE = S9 (SR2 bit 1, écrit via 31h, déjà activé par le flasher). 0xEB : cmd sur 1 bit (8 clk) + adresse quad (6 clk) + M7-0 (2 clk) + **4 dummy** + données. Mode continu si **M5-4 = `10`** (0x20 ou 0xA5 conviennent). tVSL ≥ 1.8 ms après la mise sous tension. 66h/99h : reset logiciel (tRST 30 µs). tSHSL ≥ 20 ns. |

## 2. Carte mémoire (top.vhd + soft/link.ld)

| Région | adr(31:24) | Esclave actuel | Notes |
|---|---|---|---|
| IO     | 0x00 | `peripherals` (adr(9:2)) | 0x10 GPIO, 0x14 DIR, 0x18 TX, 0x1C RX, 0x20 BAUD. Pour RX : bit8 = octet dispo et bits 7:0 = cet octet ; la lecture le consomme. **Sans octet dispo, la lecture rend 0.** 0x40 = TOHOST : registre non décodé, utilisé par les programmes de test pour écrire leur résultat, que relève `top_tb`. |
| FLASH  | 0x40 | `qspi_flash` (u7, A_WIDTH=22, 4 MiB) | Adresse flash = adr(21:0) ; le flasher tronque lui aussi à 24 bits. PC de reset = 0x40000000. Écritures ignorées mais acquittées. La ROM interne (u3) est commentée. |
| RAM    | 0x80 | `qspi_sram` (A_WIDTH=23, 8 MiB) | .data/.bss/stack |
| VRAM   | 0xC0 | (vgaModule commenté) | 32 000 octets utiles. Non mappée pour l'instant : traitée comme le reste. |
| autres | — | aucun | Mux par défaut dans `top` : `rdy='1'`, `din=0`. Une écriture est perdue, une lecture rend 0, et le cœur ne se bloque pas. |

## 3. Architecture horloge et protocole de bus (depuis l'étape 6)

- Une seule horloge, `clk27` (pin 52), sans clock-enable ni horloge dérivée. Le cœur et tous les esclaves sont sur son front montant. `clkDiv` n'est plus instancié.
- `uc` (front montant) a 4 états :
  - **S_FETCH** : `rd`=1, `adr`=PC. Quand `rdy`=1, IR est chargé sur ce même front (`enIR`, sortie de Mealy) et `rd` retombe.
  - **S_DECODE** : pour un load/store, `rd`/`we` montent, `adrSel`=1 (adresse = résultat ALU), puis S_MEM. Sinon, l'écriture de rd et la mise à jour du PC se font au front qui termine ce cycle (`wEn`/`enPc`, Mealy), et `rd` remonte pour le fetch suivant.
  - **S_MEM** : quand `rdy`=1, rd est écrit pour un load (`din` est capturé sur ce front), puis PC+4, et `rd`/`we` retombent.
  - **S_GAP** : un cycle avec `rd`=`we`=0, puis S_FETCH.
- Coût hors attente mémoire : 2 cycles pour une instruction ALU/branchement (FETCH + DECODE), 4 pour un load/store.
- Bus : `adr`, `dout` (CPU→esclaves), `din` (esclaves→CPU), `rd`, `we`, `wenb`, `rdy`.
  - `din` et `rdy` passent par un **mux explicite dans `top`** selon `adr(31:24)`. Chaque esclave a ses propres sorties et ne met jamais `Z`.
  - Zone non mappée : `rdy`=1, `din`=0.
- Reset : `top` génère `rst`, synchrone sur clk27. Il est actif pendant 255 cycles après la configuration (POR), puis tant que `rst_n` vaut 0 ; `rst_n` est resynchronisé sur 2 bascules.
- **Protocole esclave commun**, suivi par `qspi_sram`, `qspi_flash`, `peripherals`, ROM et RAM :
  - une requête est traitée une seule fois, quand `cs AND (rd XOR we)` et que l'esclave est libre ;
  - `rdy` et `dout` sont tenus jusqu'à ce que `rd`/`we` retombent ;
  - l'esclave baisse `rdy` au premier front où il voit `rd`=`we`=0.
  - La ROM et la RAM, sans effet de bord en lecture, relisent à chaque cycle mais ne lèvent `rdy` que si `cs`.
- **Invariant garanti par `uc`** : entre deux requêtes, `rd`=`we`=0 pendant au moins un cycle (S_DECODE ou S_GAP).
  - L'esclave précédent voit donc la fin de sa requête et baisse `rdy` avant que `uc` ne l'échantillonne de nouveau.
  - Sans ce trou, un esclave encore en S_ACK rendrait sa donnée précédente, par exemple une lecture flash suivie d'un fetch flash.
  - Ne pas supprimer S_GAP sans revoir tous les esclaves.
- `tb_pkg` (`bus_cycle`, `bus_fetch`) reproduit ce handshake.
  - Les TB unitaires ont un generic `FAST` : `true` par défaut, maître à pleine vitesse comme `uc` ; `false` pour un pas tous les 17 cycles, ce qui teste les requêtes tenues longtemps.
- Flash en flux : après une lecture, `qspi_flash` laisse CS# bas. Si la lecture suivante vise le mot suivant, il reprend seulement la phase données (8 SCLK au lieu de 20). Sinon, il remonte CS# et lance une nouvelle lecture continue.
- Latences (ordres de grandeur calculés à partir des phases QSPI, SCLK = 13.5 MHz) :

  | Accès | Cycles clk27 |
  |---|---|
  | Fetch séquentiel | ≈ 20 |
  | Fetch après un saut | ≈ 45 |
  | Accès PSRAM | ≈ 55 |
  | Périphérique | 2 |

## 4. Bugs à corriger

Les références `fichier:ligne` pointent vers l'état du code au 2026-10-23.

### P0 — QSPI (bloquant, cause directe de la panne PSRAM/flash)

> **Statut au 2026-10-23 : tout le P0 est CORRIGÉ.**
> - Étape 2 (PSRAM) : Q1, Q2, Q3, Q4, Q5, Q9, Q10 et T2, par `qspi_master.vhd` + le nouveau `qspi_sram.vhd`. `qspi_sram_tb` donne **SUCCES** ; **validé sur carte** (le `main` de la ROM s'exécute avec la pile en PSRAM).
> - Étape 3 (flash) : Q4 (flash_CLK), Q6, Q7, Q8, par le nouveau `qspi_flash.vhd` sur `qspi_master`. `qspi_flash_tb` donne **SUCCES**. Un test d'intégration (vrai `top` + `flash_model` chargé avec `main.elf` + `psram_model`) montre que `main` s'exécute depuis la flash : « hello » sort sur l'UART, `GPIO0 = 0x1A0F` est écrit, 0 erreur de protocole. **Reste à valider sur carte.**
>
> La description ci-dessous est celle de l'ancien code, conservée pour référence (`src/obsolete/`).

> **Vérifié en simulation (ModelSim ASE, 2026-10-23)** avec `clkDiv` + `qspi_sram` réels, en relevant les nibbles sur chaque front montant de SCLK quand CS est bas (bus tiré à `H`) :
> - QPI-enable : SIO0 donne `1,0,0,0,0,1,1,0,1` au lieu de `0,0,1,1,0,1,0,1` (0x35).
> - Écriture de 0xA1B2C3D4 : `HHHH 0011 1000 HHHH 0000 0000 HHHH ...`, c'est-à-dire un nibble flottant **avant chaque octet**.
> - Lecture : 30 fronts SCLK au lieu des 22 attendus (2 cmd + 6 adr + 6 wait + 8 data), donnée lue `FFFFFFFF`.

- **Q1 — Le handshake du PHY `qspi` insère un trou d'une période SCLK entre chaque octet.** [qspi.vhd:41-75](RISC-V/src/qspi.vhd#L41-L75)
  `ready` est registré dans `S_WRITE1`. La FSM appelante ne le voit qu'à l'impulsion suivante, alors que le PHY est déjà repassé en `S_IDLE` avec `write=0` et a mis `sio <= 'Z'`. SCLK continue de tourner pendant ce temps (`enCs=1`), donc la mémoire échantillonne un nibble flottant.
  En lecture, chaque passage `S_IDLE → S_READ1` coûte une période sans échantillonnage, ce qui fait perdre un nibble entre deux octets.
  → Le PHY ne peut pas être corrigé localement : il faut refondre le moteur QSPI (voir §6).

- **Q2 — La séquence QPI-enable de la PSRAM (0x35 émulé sur SIO0) est fausse.** [qspi_sram.vhd:544-574](RISC-V/src/qspi_sram.vhd#L544-L574)
  (a) `enCs` passe à 1 une impulsion avant que le PHY pilote les lignes, donc le premier bit lu est le pull-up (`1`).
  (b) `S_QPI_EN` maintient `wrQspi=1` alors que `rdyQspi=0`. Le PHY relance donc l'octet suivant avec l'**ancien** `dinQspi` : EN0 est envoyé deux fois et EN3 est perdu.
  (c) Le passage en `S_IDLE` remonte CS au milieu d'un octet.
  Conséquence : la PSRAM reste en mode SPI et toutes les transactions QPI suivantes sont ignorées.

- **Q3 — Les transactions démarrent hors phase avec SCLK.** [qspi_sram.vhd:492-516](RISC-V/src/qspi_sram.vhd#L492-L516)
  `S_IDLE` met CS à 0 et `enCs` à 1 sur un front où `clkEn` (enCore) vaut 1, sans tenir compte de `sram_clk_reg`. Si `sram_clk_reg='1'` à ce moment-là, SCLK monte en même temps que CS descend : tCSP est violé et le premier front échantillonne un bus flottant (`HHHH` dans la trace).
  → Mémoriser la requête sur `clkEn`, puis ne démarrer qu'à une phase où SCLK est bas, au moins une demi-période avant le premier front montant.

- **Q4 — Les horloges de sortie passent par une porte combinatoire.**
  `sram_CLK <= sram_clk_reg WHEN enCs='1'` ([qspi_sram.vhd:441](RISC-V/src/qspi_sram.vhd#L441)) peut glitcher. `flash_CLK <= clkQspi WHEN enCs='1'` ([qspi_flash.vhd:172](RISC-V/src/qspi_flash.vhd#L172)) est un vrai clock gating.
  → SCLK doit sortir directement d'un registre (option : ODDR).

- **Q5 — `dinShift` décale les données à l'envers.** [qspi_sram.vhd:456-464](RISC-V/src/qspi_sram.vhd#L456-L464), [513](RISC-V/src/qspi_sram.vhd#L513)
  Le cœur envoie la donnée **non décalée** (`dout <= s2`, [core.vhd:124](RISC-V/src/core.vhd#L124)), et `qspi_sram` envoie l'adresse octet complète à la PSRAM. Pour SB/SH à un offset non nul, `dinShift` écrit donc le mauvais octet. Exemple : SB à l'offset 1 écrit `din(15:8)` au lieu de `din(7:0)`.
  → Remplacer par `dSave <= din`, ou bien standardiser des byte lanes dans tout le système, mais alors `vgaMemInterface` (qui suppose aussi une donnée non décalée) devra suivre. `qspi_sram_tb` utilise `wenb="0100"` avec une adresse d'offset 1 : c'est incohérent, à corriger aussi.

- **Q6 — `qspi_flash` n'a pas été migré et n'élabore pas.** [qspi_flash.vhd:114-132](RISC-V/src/qspi_flash.vhd#L114-L132)
  Le composant `qspi` y est déclaré avec un port `clkQspi` qui n'existe plus (l'entité a `clk` + `clkQspiEn`). Le process tourne encore sur `clkQspi`, avec un synchroniseur `req_sync` et des ports `clkCpu`/`clkQspi`.
  → Le réécrire sur le même moteur que la PSRAM, avec `clk`, `clkEn` et le tick QSPI.

- **Q7 — Le nombre de cycles dummy du 0xEB flash est faux.** [qspi_flash.vhd:280](RISC-V/src/qspi_flash.vhd#L280), [294](RISC-V/src/qspi_flash.vhd#L294)
  La FSM envoie le mode byte (2 clk) puis 6 cycles d'attente, soit 8 clk, alors que la GD25Q32C attend M7-0 (2 clk) + **4 dummy** (datasheet §7.11). Le flasher MCU envoie bien 3 octets après l'adresse, soit 6 clk ([MX25L.cpp:244-246](soft/Flasher3.1/MCU_QSPIflasher/MX25L.cpp#L244-L246)).
  Le mode `0x20` (M5-4=`10`) active bien le mode continu sur la GD25Q32C : on peut le garder. (Les commentaires du flasher parlent de MX25L3233F, mais la puce réelle est la GD25Q32C.)

- **Q8 — La flash reste en mode continu après un reset bouton.**
  La FSM repart en `S_QPI_CSL` et renvoie 0xEB, que la flash interprète comme une adresse.
  → À l'init, envoyer une séquence de sortie du mode continu : CS bas, 8 clk avec SIO0-3 à `1` (adresse FFFFFF puis M=FF, donc M5-4 ≠ `10`), CS haut. Puis, en option, 66h/99h. Respecter tVSL ≥ 1.8 ms après la mise sous tension.

- **Q9 — L'init PSRAM ne suit pas la datasheet LY68L6400 (§9).**
  La datasheet impose ≥150 µs avec CE# haut et CLK bas, **puis un RESET 66h/99h**, avant toute autre commande. Le contrôleur actuel envoie 35h environ 1.3 µs après le reset et ne fait jamais 66h/99h (confirmé par `qspi_sram_tb`). Par ailleurs, après un reset bouton, le 0x35 « SPI » est renvoyé alors que la PSRAM est déjà en QPI.
  → Séquence d'init : attendre 150 µs, F5h en quad (sans effet si déjà en SPI), 66h/99h en SPI, puis 35h.

- **Q10 — SCLK est trop lent.**
  SCLK = 27/10 = 2.7 MHz. Une lecture de mot prend 22 SCLK, soit ≈8.1 µs, plus les trous du bug Q1. Or **tCEM max de la LY68L6400 = 8 µs**. `qspi_sram_tb` mesure 8.85 µs et 10.85 µs de CS bas par accès.
  → Monter SCLK : 13.5 MHz est possible en basculant SCLK à chaque cycle clk27, et davantage avec le rPLL (la PSRAM tient 144 MHz).

### P1 — Régressions de la migration clkEnable / bus / ISA

> **Statut au 2026-10-23 (étape 4) : tout le P1 est CORRIGÉ** : B1 à B5 à l'étape 4, B6 à l'étape 5, B7 à l'étape 6.
> - B1, B2 : `peripherals.vhd` réécrit (ancien dans `src/obsolete/peripherals_old.vhd`). `peripherals_tb` donne **SUCCES**.
> - B3 : POR et synchronisation de `rst_n` dans `top`.
> - B4 : mux explicite dans `top` ; `peripherals.dout` est passé en `out`.
> - B5 : ROM (modèle de code dans `elf2rom.py`, `ROM.vhd` régénéré) et RAM (qui gère maintenant `wenb`).
>
> Tests d'intégration (vrai `top` + `flash_model` + `psram_model`, sans appui sur le bouton reset) :
> - le `main` actuel tourne, avec « hi world » sur l'UART et `0x1F` sur les broches GPIO, sans le contournement de B2 ;
> - même résultat avec la ROM interne à la place de la flash ;
> - un programme qui écrit puis lit 0xC0000004 (non mappé) relit 0 sans se bloquer.
>
> Les descriptions ci-dessous sont celles de l'ancien code.

- **B1 — Les périphériques ne sont pas protégés contre les requêtes longues : l'UART RX est cassé.** [peripherals.vhd:133-135](RISC-V/src/peripherals.vhd#L133-L135), [174-178](RISC-V/src/peripherals.vhd#L174-L178)
  `peripherals` tourne à chaque cycle clk27 alors que `rd` reste actif ~17 cycles. Au premier cycle, la lecture de 0x07 purge `uart_rx_pending`. Aux cycles suivants, `doutZ(8)` est recapturé à 0. Le CPU lit donc toujours bit8=0, et `serialRead` ([periph.c:10](soft/periph.c#L10)) ne reçoit jamais rien.
  → Répondre une seule fois par requête : condition `cs AND (rd OR we) AND rdyZ='0'`, effets de bord uniquement sur ce cycle, `rdyZ` et `doutZ` tenus jusqu'à ce que `rd`/`we` retombent.

- **B2 — GPIO : boucle combinatoire à travers le pad bidirectionnel.** [peripherals.vhd:69-73](RISC-V/src/peripherals.vhd#L69-L73)
  `regGPIO0 <= GPIO0` hors écriture et `GPIO0 <= regGPIO0` forment un latch implicite.
  **Confirmé en simulation (étape 3)** : dès que `main` écrit DIRGPIO0, `regGPIO0` et `GPIO0` échangent leurs valeurs à chaque delta, et ModelSim s'arrête (`Iteration limit reached`). Tant que B2 n'est pas corrigé, aucune simulation de `top` qui touche au GPIO ne peut tourner. Le test d'intégration de l'étape 3 force `u6.regGPIO0` pour passer. → Utiliser un registre `gpio_out` écrit sur `we`, et lire la broche via deux registres de synchronisation.

- **B3 — Pas de reset à la mise sous tension.**
  Le seul reset est `rst <= NOT rst_n` ([top.vhd:199](RISC-V/src/top.vhd#L199)). `pc_adr` n'a pas de valeur initiale ([pc.vhd:414](RISC-V/src/pc.vhd#L414)), donc PC = 0x00000000 après la configuration, et le CPU exécute l'espace IO tant qu'on n'appuie pas sur reset. `rst_n` est en plus asynchrone et non synchronisé.
  → Ajouter un POR (compteur) et une synchronisation sur 2 bascules dans `top`.

- **B4 — Le bus interne trois états n'est pas fiable.**
  `din` et `rdy` ont plusieurs drivers (ROM, qspi_sram, peripherals, plus flash et VRAM plus tard). Le GW1N n'a pas de trois-états internes : la synthèse les convertit en logique. Pour une adresse non mappée (par exemple 0xC0 tant que le VGA est commenté), `rdy` flotte et le CPU se bloque ou se comporte de façon aléatoire. De plus, `peripherals.dout` est déclaré `inout`.
  → Utiliser un mux explicite dans `top`, avec `rdy='1'` et `din=0` par défaut pour les zones non mappées.

- **B5 — La ROM (et la RAM) ignorent `cs`.** [ROM.vhd](RISC-V/src/ROM.vhd) (process final), [RAM.vhd:321-337](RISC-V/src/RAM.vhd#L321-L337)
  `rdyZ` et `doutZ` se mettent à jour sur `rd` même quand l'accès vise la SRAM. Un `rdy` périmé peut alors être vu au fetch suivant. Le problème est **masqué aujourd'hui uniquement parce que enMem est bien plus rapide qu'enCore**, et il apparaîtra dès qu'on accélérera le cœur.
  → Qualifier par `cs` et générer un ack par requête.

- **B6 — JALR n'écrit pas `rd`.** **CORRIGÉ (étape 5)** : `jalr` est ajouté à `wEn` dans `uc`, et `pc` force le bit 0 de la cible à 0. Avant la correction, `rv32ui-jalr`, `custom-jalr_ra` et `custom-c_system` échouaient ; ils passent après. Description d'origine :
  `wEn` contient `JAL` mais pas `jalr`, donc `jalr ra, ...` (appel via pointeur de fonction) perd l'adresse de retour. `ret` (rd=x0) fonctionne quand même. Par ailleurs, JALR ne force pas le bit 0 du PC à 0 ([pc.vhd:430](RISC-V/src/pc.vhd#L430)).

- **B7 — Fréquences : configuration fragile et code C désynchronisé.** **CORRIGÉ (étape 6)** : il n'y a plus de diviseur, le cœur tourne sur clk27. `CLK_CORE_FREQ` vaut 27 MHz, avec un commentaire : il ne faut pas faire de délai logiciel en comptant des instructions. Le commentaire obsolète de `clkDiv` est retiré. Description d'origine :
  Le C suppose `CLK_CORE_FREQ = 13.5 MHz` ([periph.h:19](soft/periph.h#L19)), alors que le cœur tourne réellement à 27/17 ≈ 1.588 MHz : les délais logiciels sont faux. Le commentaire `00149970` dans `clkDiv` est obsolète. Les deux diviseurs étant premiers entre eux, aucun module ne doit supposer un alignement entre enCore et enMem.

### P2 — Fiabilité / timing / hygiène

- **T1 — CORRIGÉ (étape 6)** : `uc` réécrit sur front montant (voir §3). Description d'origine : `uc` est sur `falling_edge` alors que le datapath est sur `rising_edge`. Cela crée des chemins d'une demi-période (18.5 ns) de uc vers PC, IR, regFile et mémoires. → Passer uc sur `rising_edge` en revoyant le séquencement (un état de plus si nécessaire), ou contraindre ces chemins.
- **T2 —** Les trois-états SIO sont affectés dans un process synchrone (`sio0 <= 'Z'`), et le même port y est relu. → Séparer des registres `oe`/`out`, faire l'affectation concurrente `sio <= out WHEN oe='1' ELSE 'Z'` et ajouter un registre d'entrée.
- **T3 — CORRIGÉ** : `uc` a été réécrit à l'étape 6 (plus d'état mort ni de double affectation), et `qspi_*` à l'étape 2-3. Description d'origine : dans `uc`, `adrSel` n'était pas réinitialisé, `S_WB1` n'était pas utilisé, et `rd` était affecté deux fois dans `others` ; dans `qspi_*`, les signaux `debug` et `r_wn_req` étaient morts.
- **T4 —** Les contrôleurs QSPI n'ont pas de timeout : si la mémoire est absente, le CPU reste bloqué indéfiniment. Utile pour le debug, à ajouter en option.
- **T5 —** Le `.sdc` ne déclare que clk27. Si on ajoute une PLL, déclarer les horloges générées.
- **T6 —** Dans le `.cst`, toutes les IO sont en `LVCMOS18` avec `BANK_VCCIO=1.8`. À vérifier par rapport aux bancs réels de la Tang Nano 9K et à la tension des puces QSPI externes (probablement 3.3 V).

### P3 — VGA (désactivé) à réintégrer après le reste

- **V1 —** `vgaModule` est câblé sur `clk_vram => clkCpu` (signal qui n'existe plus), et `clk25` n'est jamais piloté. Le rPLL existant (27×13/7 ≈ 50.14 MHz) donne via `clkoutd`/2 ≈ 25.07 MHz (-0.4 % par rapport à 25.175 MHz), ce que la plupart des écrans acceptent.
- **V2 —** `vgaMemInterface` : pas de `clkEn`, un `RDY` pipeline non qualifié par `CS`, des écritures répétées tant que `we` reste actif (sans conséquence). À adapter au protocole d'ack commun.
- **V3 —** `link.ld` déclare `VRAM LENGTH = 8K`, alors que la zone utile fait 32 000 octets (`SCREEN_P_END = 0xc0007fff`).

## 5. Testbenches

### État des TB existants

| TB | État |
|---|---|
| `alu_tb`, `regFile_tb`, `clkDiv_tb` | Ne compilaient plus ; déplacés dans `tb/obsolete/`. |
| `qspi_tb.vhd`, ancien `qspi_flash_tb.vhd` | Déplacés dans `tb/obsolete/` (le PHY `qspi.vhd` est supprimé). |
| `qspi_sram_tb.vhd` | **Réécrit (étape 1, fait).** L'ancien est dans `tb/obsolete/`. Voir ci-dessous. |
| `psram_model.vhd` + `psram_model_tb.vhd` | **Fait.** Modèle LY68L6400 ; autotest **SUCCES** (aucune erreur sur une séquence correcte, et 5 fautes injectées toutes détectées). |
| `flash_model.vhd` + `flash_model_tb.vhd` | **Fait (étape 3).** Modèle GD25Q32C ; autotest **SUCCES** (aucune erreur sur une séquence correcte, et 7 fautes injectées toutes détectées). |
| `qspi_flash_tb.vhd` | **Réécrit (étape 3).** Voir plus bas. |
| `peripherals_tb.vhd` | **Fait (étape 4).** Voir plus bas. |
| `top_tb.vhd` | **Réécrit (étape 5)** ; l'ancien est dans `tb/obsolete/`. C'est un TB système qui fait tourner des programmes de test. Voir plus bas. |
| `vga_tb.vhd` | OK (teste `vgaSignalGen` seul, auto-vérifiant). |

### `qspi_sram_tb` : résultats

**Après l'étape 2 (nouveau `qspi_sram` + `qspi_master`) : TB_RESULT: SUCCES**, avec 393 accès et 0 erreur TB ou protocole. Le seul warning attendu est le F5h tronqué de la première init, quand la PSRAM est encore en SPI. Le TB tourne avec `clkQspiEn => '1'` (SCLK = 13.5 MHz), comme dans `top`. J'ai vérifié sa sensibilité par mutations : avec 5 cycles dummy au lieu de 6, il donne ECHEC (182 erreurs) ; avec une adresse d'écriture alignée sur le mot (retour de Q5), ECHEC (135 erreurs).

Sur l'ancien RTL (étape 1), il donnait **TB_RESULT: ECHEC** : 393 accès, 590 erreurs TB, 2454 erreurs de protocole relevées par le modèle. Ce que le modèle signale :
- 1er CE# à 1.3 µs (avant tPU), aucun 66h/99h (Q9) ;
- le 35h arrive comme `86h` à cause du nibble flottant initial (Q2) ;
- la PSRAM ne passe donc jamais en QPI ;
- chaque accès QPI est lu comme une commande SPI inconnue ;
- lignes non pilotées (`H`) pendant que SCLK tourne (Q1) ;
- tCSP = 0 au démarrage de transaction (Q3) ;
- tCEM dépassé à chaque accès (Q10).

Côté TB, toutes les lectures renvoient `FFFFFFFF`.

Ce que vérifie le TB :
- T1 : SW/LW simple ;
- T2 : adresses hautes (A22..A16) ;
- T3 : SB aux offsets 0..3, avec des octets hauts aléatoires dans s2 ;
- T4 : SH aux offsets 0/2 ;
- T5 : lectures non alignées ;
- T6 : 300 accès aléatoires ;
- T7 : reset du contrôleur en cours de route.

Après chaque accès, le TB vérifie aussi : exactement **1** transaction QSPI, l'adresse 24 bits reçue par la PSRAM, et la donnée par rapport à un modèle de référence. Un timeout de 400 pas de uc est appliqué par accès, avec abandon après 3 timeouts consécutifs.

### `qspi_flash_tb` : résultats (étape 3)

**TB_RESULT: SUCCES** : 278 accès, 0 erreur TB, 0 erreur protocole. Le modèle est rempli avec `flash_pattern()` (tb_pkg), donc le TB connaît chaque octet.

Ce que vérifie le TB :
- T1 : reset puis lecture immédiate en 0x40000000, comme le premier fetch du cœur. Elle attend la fin de l'init (≈2.05 ms). On vérifie 3 transactions d'init (sortie du mode continu, 66h, 99h), puis 1 lecture avec une seule commande EBh ;
- T2 : 64 lectures séquentielles, sans aucune commande EBh (mode continu). Depuis l'étape 6, elles doivent toutes passer en **flux**, sans nouvelle transaction ni nouvelle adresse. Une lecture non séquentielle ferme le flux (+1 transaction) ;
- T3 : adresses hautes (A21..A16) ;
- T4 : LB/LH/LBU/LHU non alignés (c'est le mot aligné qui est lu) ;
- T5 : 200 lectures aléatoires sur 4 MiB ;
- T6 : une écriture en flash est acquittée sans transaction QSPI ;
- T7 : reset du contrôleur alors que la flash est en mode continu (Q8), puis relecture.

Mutations, toutes détectées :
- 6 dummy au lieu de 4 (retour de Q7) ;
- pas de sortie du mode continu à l'init (Q8) ;
- commande EBh à chaque lecture ;
- M = 00h ;
- attente tRST nulle ou trop courte ;
- attente tVSL trop courte ;
- adresse non alignée ;
- écriture non acquittée ;
- flux (étape 6) : adresse suivante non incrémentée, flux jamais utilisé, reprise sur 2 octets au lieu de 4.

### `peripherals_tb` : résultats (étape 4)

**TB_RESULT: SUCCES** : 817 accès, 0 erreur. Le TB utilise le vrai `clkDiv`, et `rd`/`we` sont tenus ~17 cycles comme dans uc.

**Bug trouvé sur carte après l'étape 4, corrigé le 2026-10-23.** Après un reset bouton, `serialRead` rendait la main tout de suite. Deux causes :
- RX relisait le dernier octet reçu (le '\r' de la session précédente) avec bit8=0. Or la boucle de `serialRead` compare la valeur **brute** du registre à '\r'.
- Un octet non lu au moment du reset laissait `read_ready` bloqué à 1 dans l'UART, et la réception était morte jusqu'à reconfiguration.

Correction :
- `uart.vhd` n'a plus de poignée de main `read`/`read_ready` : son bit `rx_toggle` bascule à chaque octet reçu ;
- `peripherals` resynchronise ce bit, recopie l'octet dans `rx_byte` (remis à zéro par le reset) et rend 0 quand rien n'est en attente.

Les tests T6 et T7 ci-dessous reproduisent ce bug et échouaient avant la correction. Le scénario a aussi été rejoué sur le vrai `top` avec le `main.elf` de test : taper « abc⏎ », reset, puis taper « xy⏎ ».

Ce que vérifie le TB :
- T1 GPIO : DIR après reset, sorties sur les bits en sortie, entrées pilotées par le TB, aucun conflit, aucune boucle combinatoire (B2) ;
- T2 UART TX : chaque écriture produit exactement une trame, et busy est lu à 1 juste après l'écriture ;
- T3 UART RX : 1 octet, puis 4 octets à la suite, pendant que le TB scrute 0x1C comme `serialRead`. Chaque octet est vu **exactement une fois** avec bit8=1 (B1) ;
- T4 : une adresse non décodée est acquittée et lit 0 ;
- T5 : le reset remet DIR et BAUD à zéro et relâche les broches ;
- T6 : RX relu après consommation d'un '\r', puis après un reset, doit valoir 0 ;
- T7 : un octet reçu mais non lu au moment du reset ; la réception doit repartir ensuite.

Mutations, toutes détectées :
- requête retraitée tant que `rd` reste haut (retour de B1) ;
- entrées GPIO non lues ;
- DIR non remis à zéro ;
- octet reçu jamais consommé ;
- `send` UART jamais relâché ;
- `rdy` relâché trop tôt.

### `top_tb` + `top_tests.do` : tests système (étape 5)

**TB_RESULT: SUCCES (43/43)**, en ~1 min 40 pour toute la série.

Montage :
- `top_tb` instancie le vrai `top`, `flash_model` chargé avec le programme (`HEX_FILE`) et `psram_model` (1 MiB). `rst_n` reste à 1 : seul le POR démarre le cœur.
- Le programme écrit son résultat à TOHOST (0x40) : 1 = succès, `(n << 1) | 1` = échec du test n. `top_tb` relève cette écriture sur le bus.
- Un test échoue aussi si l'un des modèles relève une erreur de protocole, ou en cas de timeout (60 ms par défaut).
- La sortie UART est affichée ligne par ligne.

Les programmes :
- `rv32ui-*` (40) : riscv-tests officiels, sauf `fence_i` (code auto-modifiant) et `ma_data` (accès non alignés), hors périmètre. Ils couvrent toutes les instructions RV32I, les SB/SH/LB/LBU/LH/LHU en PSRAM à tous les offsets (Q5) et les dépendances entre instructions.
- `custom-jalr_ra` : `jalr ra`, rd = rs1, et cible impaire. Le bit 0 se vérifie par AUIPC, car le fetch flash aligne l'adresse et un saut impair « marche » en apparence.
- `custom-unmapped` : SW/LW/SB/LB en zones non mappées (B4), puis RAM toujours accessible.
- `custom-c_system` : programme C compilé comme `comp.bat` (start.S + link.ld). Il couvre `.data`, `.bss`, la pile en PSRAM, la récursion, les pointeurs de fonction, libgcc (mul/div) et libc (memset/memcpy/strlen).

Avant la correction de B6, on avait 40/43 : `rv32ui-jalr`, `custom-jalr_ra` et `custom-c_system` échouaient. J'ai aussi réintroduit séparément les deux moitiés de B6 : l'absence d'écriture de `rd` fait échouer les 3 tests ; l'absence de mise à zéro du bit 0 n'est détectée que par `custom-jalr_ra`.

Vitesse du cœur : environ 4 µs par instruction avant l'étape 6, environ 3 fois moins après. Une instruction ALU en code séquentiel coûte ≈ 22 cycles (0,8 µs), surtout du fetch flash. Les 43 tests tournent en ~55 s. L'init flash prend ≈2,06 ms de temps simulé au début de chaque test.

Temps d'exécution hors init (fin du test − 2,06 ms) :

| Test | Avant l'étape 6 | Sans enCore | + flux flash |
|---|---|---|---|
| `custom-c_system` | 6,70 ms | 3,75 ms | **2,17 ms** (×3,1) |
| `rv32ui-ld_st` | 4,02 ms | 2,43 ms | **1,51 ms** (×2,7) |

**Interface de `qspi_sram` (à conserver) :** la même liste de ports (`clk`, `clkEn`, `rst`, `cs`, `rd`, `wr`, `wenb`, `adr`, `din`, `dout`, `rdy`, `sram_*`, et `clkQspiEn` s'il sert encore) pour que le TB reste valable. Le TB vérifie le nombre de transactions dès que `rdy` est vu : CS doit donc être remonté avant `rdy`. Si on ajoute un jour des écritures postées, il faudra assouplir ce contrôle.

### TB à écrire (tous auto-vérifiants : `assert ... severity error`, compteur d'erreurs, `std.env.finish`)

1. ~~`tb/tb_pkg.vhd`~~ — **fait** : `bus_cycle` / `bus_fetch` / `core_wenb` / `store_bytes`.
2. ~~`tb/psram_model.vhd`~~ — **fait** (LY68L6400, autotest `psram_model_tb.vhd`).
3. ~~`tb/flash_model.vhd`~~ — **fait** (GD25Q32C, autotest `flash_model_tb.vhd`).
   - Préchargement : generic `INIT_FILE` = sortie de `python elf2rom.py main.elf -o flash.hex --format hex` (un mot 32 bits par ligne, mot 0 = 0x40000000).
   - Sans fichier, le contenu est `flash_pattern()`.
4. ~~`tb/qspi_sram_tb.vhd`~~ — **fait**, échoue sur le RTL actuel comme attendu (voir plus haut).
5. ~~`tb/qspi_flash_tb.vhd`~~ — **fait** (voir plus haut).
6. ~~`tb/peripherals_tb.vhd`~~ — **fait** (voir plus haut).
7. ~~`tb/top_tb.vhd`~~ — **fait** (voir plus haut), avec les riscv-tests rv32ui.
8. `alu_tb`, `regFile_tb`, `clkDiv_tb` : **déplacés dans `tb/obsolete/`** le 2026-10-25. Ils ne compilaient plus, et l'ALU, les registres et les branchements sont couverts par les riscv-tests au niveau système.

### Lancer une simulation

ModelSim ASE est installé (`D:\logiciel\Quartus\modelsim_ase\win32aloem`, dans le PATH) et la compilation VHDL-2008 fonctionne. Un script `.do` par TB se trouve dans `RISC-V/sim/`, et la librairie `work` ainsi que les logs y sont générés. Le résultat se lit sur une ligne `TB_RESULT: SUCCES|ECHEC` (ou `MODEL_SELFTEST: ...`).

```sh
cd RISC-V/sim
vsim -c -do "do psram_model.do; quit -f"   # autotest du modèle PSRAM
vsim -c -do "do qspi_sram.do; quit -f"     # contrôleur PSRAM (~1 s pour ~5 ms simulées)
vsim -c -do "do flash_model.do; quit -f"   # autotest du modèle flash
vsim -c -do "do qspi_flash.do; quit -f"    # contrôleur flash (~5 ms simulées)
vsim -c -do "do peripherals.do; quit -f"   # GPIO + UART (~2 ms simulées)

# Tests système (programmes à recompiler après toute modification de soft/tests)
python ../../soft/tests/build_tests.py           # -> sim/tests/*.hex
vsim -c -do "do top_tests.do; quit -f"           # les 43 programmes (~1 min 40)
vsim -c -do "set TEST rv32ui-jalr; do top_tests.do; quit -f"   # un seul
```

Pour simuler un programme quelconque de `soft/` (sans résultat TOHOST, il finira en timeout, mais sa sortie UART s'affiche) :

```sh
python soft/elf2rom.py soft/main.elf -o RISC-V/sim/tests/main.hex --format hex
cd RISC-V/sim && vsim -c -do "set TEST main; do top_tests.do; quit -f"
```

En GUI : `cd RISC-V/sim` puis `do qspi_sram.do` (les signaux utiles sont ajoutés à la fenêtre wave).
Attention : `release` est un mot réservé en VHDL-2008 ; ne pas l'utiliser comme identifiant.

## 6. Architecture cible recommandée (QSPI + bus)

- **Une seule horloge** (clk27, ou mieux une sortie du rPLL entre 54 et 108 MHz), sans aucune horloge dérivée ni gating.
- **Un seul moteur `qspi_master`** à la place du couple PHY/FSM avec handshake :
  - Un tick interne fait basculer un registre SCLK.
  - Sur la phase « front descendant », mise à jour d'un registre à décalage de sortie.
  - Sur la phase « front montant » (ou juste avant le descendant suivant, à basse fréquence), échantillonnage de l'entrée.
  - La séquence est décrite par des compteurs de phases : cmd (8 bits SPI ou 2 nibbles QPI), adresse 6 nibbles, mode 2 nibbles, N dummy, 2×len nibbles de données, direction.
  - CS descend avec SCLK bas, au moins une demi-période avant le premier front montant, et remonte après le dernier front descendant.
- **`qspi_sram` / `qspi_flash`** deviennent de simples wrappers qui configurent le moteur et gèrent l'init :
  - flash : sortie du mode continu ;
  - PSRAM : attente de 150 µs, 0xF5, 0x66/0x99, puis 0x35.
- **Protocole esclave commun** (sram, flash, ROM, périphériques, VRAM) :
  - la requête est capturée une seule fois, quand `cs AND (rd XOR we)` et que l'esclave est libre ;
  - `rdy` et `din` sont tenus jusqu'à ce que `rd`/`we` retombent ;
  - aucun effet de bord répété.
- **Bus** : mux explicite dans `top`, avec `rdy='1'` par défaut pour les zones non mappées.
- Une fois tous les esclaves passés à ce protocole, **supprimer `enCore`** et faire tourner le cœur à chaque cycle : c'est le gain de performance visé par la migration. `rdy` gère alors seul les attentes.

## 7. Ordre de travail conseillé

1. ~~Écrire `tb_pkg` + `psram_model` + `qspi_sram_tb`, et constater l'échec sur le code actuel.~~ **Fait le 2026-10-23.**
2. ~~Écrire `qspi_master` et réécrire `qspi_sram` jusqu'à ce que le TB passe. Puis Q10 (accélérer SCLK).~~ **Fait le 2026-10-23, validé sur carte** (SCLK à 13.5 MHz). L'entrée est échantillonnée sur la phase « front montant », ce qui laisse une demi-période (37 ns) pour Tco + tACLK (≤ 6 ns) + la carte.
3. ~~Écrire `flash_model`, migrer `qspi_flash` (Q6-Q8) jusqu'à ce que le TB passe, puis remplacer `u3 : ROM` par `u7 : qspi_flash` dans `top`.~~ **Fait le 2026-10-23.** À valider sur carte.
   - Programmer d'abord la flash (`comp.bat main.c flash`) : le cœur démarre maintenant depuis la flash, après ≈2.05 ms d'init.
   - Chaque fetch coûte une transaction QSPI : 20 SCLK en mode continu, soit ≈1.6 µs.
   - Piste pour l'étape 6 : un mode « burst » qui garde CS# bas pendant les fetchs séquentiels.
4. ~~Bus et périphériques : B1, B2, B3, B4, B5.~~ **Fait le 2026-10-23.** À valider sur carte, en particulier la réception UART (`serialRead`), qui ne pouvait pas marcher avant B1.
5. ~~ISA : B6. Puis `top_tb` avec des programmes de test et les riscv-tests.~~ **Fait le 2026-10-23** : 43/43 tests système. À valider sur carte : un programme C qui appelle une fonction par pointeur.
6. ~~Performance : T1, suppression de `enCore`, rPLL. Mettre à jour `periph.h` (B7).~~ **Fait le 2026-10-25, sauf le rPLL** : `uc` sur front montant sans enable, flux flash, B7. Résultat : 43/43, programmes ×2,7 à ×3,1 plus rapides. À valider sur carte.
   - **Vérifier le rapport de timing Gowin.** Tout le chemin de données tient maintenant en un cycle de 37 ns : lecture regFile → ALU → PC/regFile, et `adr` → mux → `uc`. Ce n'était pas le cas avant, puisque le cœur n'avançait qu'une fois tous les 17 cycles.
   - rPLL : à envisager seulement si le Fmax Gowin le permet. Le gain serait limité, car SCLK = clk/2 et la latence mémoire domine. Il faudrait aussi revoir les `INIT_WAIT` (exprimés en cycles), la formule du baud UART et le `.sdc` (T5).
   - Piste suivante pour la vitesse : un préchargement du mot suivant en flash, pendant que le cœur exécute.
7. VGA (V1-V3).

## 8. Conventions

- Style VHDL du projet : mots-clés en MAJUSCULES (`ENTITY`, `PROCESS`, `WHEN`), entités en camelCase, architectures nommées `<entité>V1`, composants déclarés dans l'architecture, commentaires en français.
- Bus : pas de trois états internes. Chaque esclave sort `dout`/`rdy` en permanence, et le mux de `top` choisit selon `adr(31:24)`. Un nouvel esclave (VRAM par exemple) doit suivre le protocole commun (§3) et être ajouté au mux.
- `ROM.vhd` est généré par `soft/comp.bat <fichier.c> rom` (via `elf2rom.py --depth 1024`) : ne pas l'éditer à la main.
- Pour programmer la flash : `soft/comp.bat <fichier.c> flash` (passe par l'Arduino `Flasher3.1`).
- Le logiciel est en RV32I pur (`-march=rv32i -mabi=ilp32`), sans interruptions ni CSR.
- Git : `.gitignore` exclut `src/obsolete/` et `tb/obsolete/` (anciennes versions gardées en local), les sorties Gowin (`impl/`, sauf `RISC-V_process_config.json`), `*.gprj.user`, la simulation (`sim/work`, `sim/tests`, logs, wlf, vcd) et les binaires logiciels (elf, hex, `soft/display`). `.gitattributes` normalise les fins de ligne en LF, sauf `*.bat` en CRLF. `README.md` est la page d'accueil du dépôt.
- Avant de remplacer un fichier RTL, copier l'ancienne version dans `src/obsolete/` (ou `tb/obsolete/`).
