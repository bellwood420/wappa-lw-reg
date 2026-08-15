# Wappa LW Register

Minimal DE10-Nano experiment for direct communication from the Cyclone V HPS
to FPGA fabric through the **Lightweight HPS-to-FPGA bridge**.

The point of this project is to keep the path visible and small.

There is **no Qsys / Platform Designer interconnect in the active design**.
The Cyclone V hard Lightweight HPS-to-FPGA AXI interface is instantiated
directly from SystemVerilog, in the same spirit as MiSTer-style direct HPS
primitive use.

The current design implements one 32-bit FPGA register:

```text
ARM Cortex-A9
    |
    | physical 0xFF200000
    v
Cyclone V Lightweight HPS-to-FPGA bridge
    |
    v
cyclonev_hps_interface_hps2fpga_light_weight
    |
    v
wappa_axi_reg.sv
    |
    v
reg0[31:0]
```

A real DE10-Nano test has successfully written and read back:

```text
0xDEADBEEF
```

---

## Target

- Board: Terasic DE10-Nano
- FPGA: Intel/Altera Cyclone V SoC
- Device: `5CSEBA6U23I7`
- Quartus: 17.0.2
- FPGA fabric clock: `FPGA_CLK1_50`
- Clock pin: `PIN_V11`
- Clock frequency: 50 MHz

The HPS is already running Linux before the FPGA fabric is configured.

---

## Design files

The active design is intentionally small:

```text
wappa_lw_reg.qpf
wappa_lw_reg.qsf
wappa_lw_reg.sdc
wappa_top.sv
wappa_axi_reg.sv
```

### `wappa_top.sv`

Top-level wrapper.

It only receives the DE10-Nano 50 MHz FPGA clock and instantiates
`wappa_axi_reg`.

### `wappa_axi_reg.sv`

Contains:

- direct instantiation of
  `cyclonev_hps_interface_hps2fpga_light_weight`
- a minimal AXI3 slave
- one 32-bit register, `reg0`
- byte-write support through AXI `WSTRB`
- single-beat, 32-bit transfers only

For this experiment:

```text
HPS physical address 0xFF200000 <-> reg0
```

No Qsys-generated PIO, Merlin interconnect, router, mux, demux, burst adapter,
or generated HPS wrapper is used.

---

## Quartus build

Open the project in Quartus 17.0.2 and run **Full Compilation**.

Command-line equivalent:

```sh
quartus_sh --flow compile wappa_lw_reg
```

The generated SOF is normally placed under:

```text
output_files/
```

---

## Unused-pin safety

MiSTer expansion boards may remain physically attached to the DE10-Nano.

The project therefore explicitly keeps unused FPGA pins as tri-stated inputs:

```tcl
set_global_assignment -name RESERVE_ALL_UNUSED_PINS \
    "AS INPUT TRI-STATED"

set_global_assignment -name RESERVE_ALL_UNUSED_PINS_WEAK_PULLUP \
    "AS INPUT TRI-STATED"
```

This was verified from the Quartus `.pin` report.

Observed result:

```text
FPGA_CLK1_50 -> PIN_V11 -> input
all ordinary unused FPGA I/O -> RESERVED_INPUT
```

No user FPGA output pins are driven by this design.

The JTAG `TDO` pin may appear as an output in the pin report; that is a
dedicated JTAG pin, not a user circuit output.

---

## Programming the FPGA

For the current experiment, FPGA Manager is deliberately bypassed.

The SOF is loaded directly over JTAG:

1. Open **Tools -> Programmer**
2. Select the USB-Blaster
3. Add the generated `.sof`
4. Check **Program/Configure**
5. Press **Start**

The Linux FPGA Manager may still report:

```text
power off
```

after JTAG programming. That status does not mean the JTAG-loaded fabric is
absent; FPGA Manager did not perform the configuration.

---

## Opening the Lightweight bridge

After a valid SOF has been loaded, the current test system uses these raw HPS
register writes.

### 1. Release only the Lightweight HPS-to-FPGA bridge reset

Observed boot value:

```text
BRGMODRST = 0x00000007
```

For this experiment:

```sh
devmem 0xFFD0501C 32 0x00000005
```

This clears the Lightweight HPS-to-FPGA reset bit while leaving the other two
bridge reset bits asserted.

After this write:

```sh
cat /sys/class/fpga_bridge/br0/state
```

reports:

```text
enabled
```

Note that this sysfs state reflects the reset state. It does not by itself
prove that the L3 remap has been opened.

### 2. Make the Lightweight bridge visible from the HPS L3 interconnect

```sh
devmem 0xFF800000 32 0x00000011
```

`0x11` enables:

```text
bit 0: MPUZERO
bit 4: Lightweight HPS-to-FPGA visibility
```

**Do not read back `0xFF800000`.**
The Cyclone V L3 remap register used here is write-only.

---

## Register test

Read the FPGA register:

```sh
devmem 0xFF200000 32
```

Immediately after FPGA configuration, the expected value is:

```text
0x00000000
```

Write and read back:

```sh
devmem 0xFF200000 32 0xDEADBEEF
devmem 0xFF200000 32
```

Expected result:

```text
0xDEADBEEF
```

This path has been verified on real hardware.

---

## Important ordering rule

Configure the FPGA **before** allowing the HPS to access the FPGA address
space.

Correct order:

```text
1. Load a valid SOF
2. Release the Lightweight bridge reset
3. Enable the L3 remap
4. Access 0xFF200000
```

A real negative test was also performed:

```text
power cycle
-> Linux boot
-> release bridge reset
-> enable L3 remap
-> access 0xFF200000 before loading SOF
```

The `devmem` access blocked because there was no FPGA AXI slave to answer it.

While that read was still pending, the SOF was loaded through JTAG.
The pending access then completed and returned:

```text
0x00000000
```

Afterward, normal `0xDEADBEEF` write/readback worked.

This is useful experimental evidence, but it should **not** be treated as a
general guarantee that arbitrary AXI transactions may safely survive FPGA
reconfiguration.

---

## Why no Qsys?

The first working version used a small Platform Designer system:

```text
HPS Lightweight AXI
    ->
Qsys / Merlin interconnect
    ->
Qsys PIO
```

It worked, but pulled in a large generated RTL tree.

The current version removes that layer and directly instantiates the Cyclone V
hard interface:

```systemverilog
cyclonev_hps_interface_hps2fpga_light_weight
```

The minimal 32-bit register therefore does not depend on a generated Qsys
system.

Quartus still provides knowledge of the Cyclone V hard primitive itself; that
is part of targeting this FPGA device, not a generated interconnect subsystem.

---

## Current scope

This is deliberately a small experiment, not a general-purpose AXI
interconnect.

The slave currently assumes:

- 32-bit transfers
- one beat per transaction
- one register at local address zero
- no multiple outstanding transactions
- no burst support beyond rejecting unsupported requests
- `OKAY` for valid accesses
- `SLVERR` for unsupported access shapes

That is sufficient for the current `devmem` experiment and keeps the complete
HPS-to-FPGA path understandable.

---

## Status

Verified on DE10-Nano:

```text
Linux userspace
-> /dev/mem
-> 0xFF200000
-> Lightweight HPS-to-FPGA bridge
-> direct Cyclone V hard AXI interface
-> wappa_axi_reg
-> reg0
-> write/readback 0xDEADBEEF
```

**Qsys / Platform Designer generated RTL is not required for this minimal
communication path.**
