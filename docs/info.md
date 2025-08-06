## What it does

This peripheral is a synthesizable hardware implementation of the Nintendo Entertainment System (NES) Ricoh 2A03 `APU`. It is designed to generate sound for the `TinyQV` project. The `APU` has four primary sound channels: two square waves, one triangle wave and one noise channel. The outputs of these channels are mixed to produce a single audio sample.

**Key Design Features:**

* **Audio Channels:** Includes two square wave channels, a triangle channel, and a noise channel.
* **Sample Output:** The final mixed audio sample is available in a 16-bit format through dedicated registers.
* **Feature Removal:** For optimization and reduced resource utilization, the **frequency sweep unit** for the square channels has been intentionally removed. This means the pitch of the square waves cannot be automatically adjusted by the `APU`.
* **Other modifications**:
    - Mixer is now linear
    - Square wave was simplified
    - Triangle wave was simplified

## Register map

This peripheral's memory-mapped registers allow for configuration, status checks, and data exchange with the `APU` core.

### Peripheral Registers

| Address | Name            | Access | Description                                                                   |
|---------|-----------------|--------|-----------------------------------------------------------------------------------|
| 0x00-0x1F | `APU` Registers | R/W    | Direct access to the internal NES `APU` registers (0x4000-0x401F). |
| 0x20    | Configuration0  | R/W    | Configuration bits for the `APU`. `b2`: `isMMC5` (`MMC5` expansion enabled), `b1`: `US` (ultrasound mode), `b0`: `CE` (clock enable). |
| 0x22    | Status0         | R      | Status flags. `b1`: `APU` interrupt request, `b0`: data output ready. |
| 0x23    | Data Input      | R/W    | Data to be written to the `APU`'s DIN port for commands/writes.                |
| 0x24    | Data Output MSB | R      | Most significant byte of the 16-bit `APU` audio sample.                     |
| 0x25    | Data Output LSB | R      | Least significant byte of the 16-bit `APU` audio sample.                      |

### Internal `APU` Registers

The internal `APU` registers (e.g., for channel configuration and status) can be accessed by writing to the peripheral's address space from `0x00` to `0x1F`. For example, `0x00` would map to the `APU`'s `0x4000` register.

## How to test

To test the peripheral, you can write to the `APU`'s registers via the `0x00-0x1F` address space to configure individual channels. The `0x20` register can be used to set global parameters like `MMC5` mode. The output audio samples can be read from registers `0x24` and `0x25`, and the physical audio signals can be monitored on the `PMOD` connector.

`WIP`: `TinyQV` drivers

## External hardware

This peripheral uses the following external hardware connections via the `PMOD` connector:

* **uo_out[0]:** `apu_IRQ` (Interrupt Request signal from the `APU`)

## Thanks

- [kitrinx](https://github.com/kitrinx) for the [`APU`](https://github.com/MiSTer-devel/NES_MiSTer/blob/master/rtl/apu.sv)