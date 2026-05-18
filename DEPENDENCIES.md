# Third-Party Dependencies

The 2008–2009 working Quartus II project integrated several reference
cores and simulation models that are **not redistributed in this
publication**. They remain the property of their respective vendors
under their original license terms. To rebuild the project locally
you would need to obtain each one from its vendor.

## Altera (now Intel) reference cores

The following modules carry the standard **Altera Program License
Subscription Agreement** notice
(`(C) 2006 Altera Corporation`), which restricts use to programming
Altera/Intel logic devices. They were obtained as part of the
Cyclone II Starter Board / DE1 reference design materials shipped
with the original Altera development kit.

| Module | Role |
|--------|------|
| `Multi_Sdram` (8 files — `Sdram_Controller.v`, `Multi_Sdram.v`, `command.v`, `control_interface.v`, `sdr_data_path.v`, `Sdram_Multiplexer.v`, `Params.v`, `Sdram_Params.h`) | Multi-port SDRAM controller targeting the on-board ISSI/Hynix 8 MB SDRAM chip on the DE1. |
| `I2C_Controller.v` | Bit-banged I2C master used to configure the WM8731 audio codec at boot. |
| `I2C_AV_Config.v` | I2C transaction sequencer that pushes the WM8731 register table. |
| `ps2_keyboard.v` | PS/2 keyboard receiver. Drives the `cmd_interface` module in `rtl/`. |

## Altera megafunction (auto-generated)

| Module | Role |
|--------|------|
| `FIFO0` (DC FIFO, generated via the Quartus II megafunction wizard) | Dual-clock FIFO bridging the codec clock domain and the SDRAM clock domain inside the Memory Flow Controller. Regenerable in seconds inside Quartus II / Quartus Prime by re-running the wizard. |
| PLL primitive(s) wrapping the on-board 50 MHz and 27 MHz crystals into the three working clock domains (50 MHz, 100 MHz, 18.4 MHz) | Same regenerability — instantiate via the PLL megafunction wizard. |

## Micron (simulation only)

Used only during behavioural simulation of the SDRAM controller, never
synthesised into the bitstream.

| File | Role | License notice |
|------|------|----------------|
| `mt48lc4m16a2.v` | Behavioural model of the Micron MT48LC4M16A2 SDRAM chip. | "Provided 'AS IS'", standard Micron sim-model disclaimer. |
| `test.v` | Companion testbench for the Micron model. | Same. |

## How the originals were laid out

In the original Quartus II project:

```
<project root>/
├── rtl/                            <-- the VHDL in this repository
│   ├── Looper.vhd, MFC.vhd, CODECC.vhd, DACC.vhd,
│   │   cmd_interface.vhd, LooperTop.vhd     (authored by me)
│   ├── FIFO0.vhd                            (Altera megafunction)
│   ├── I2C_AV_Config.v, I2C_Controller.v    (Altera reference)
│   └── ps2_keyboard.v                       (Altera reference)
└── SDRAMAlteraTest/              <-- separate SDRAM-bring-up sandbox
    ├── Multi_Sdram/                         (Altera reference)
    └── mt48lc4m16a2.v, test.v               (Micron sim)
```

The dependencies above were dropped into those locations from the
DE1 reference design / Altera AN-202 SDRAM controller materials.
