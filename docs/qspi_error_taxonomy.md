# QSPI Error Taxonomy (RTL Frontend)

The frontend contract uses one 16-bit class and one 16-bit code. The packed
value is exposed consistently by Boot ROM, `apb_qspi_status`, `apb_boot_status`,
and the firmware mailbox. `0` means no error.

| Class | Code | Meaning | Retry |
|---:|---:|---|---|
| `0x0001` | `0x0001` | XIP read timeout / downstream no response | one bounded retry, then reset/DBE |
| `0x0002` | `0x0001` | command aborted by software or reset-in-flight | no automatic retry |
| `0x0002` | `0x0002` | unsupported command or bus width | no retry |
| `0x0003` | `0x0001` | malformed manifest/header or bounds violation | no retry |
| `0x0003` | `0x0002` | payload CRC failure | no retry |
| `0x0004` | `0x0001` | controller initialization failure | one bounded retry |
| `0x0005` | `0x0001` | erase/program/device status failure | no retry; production policy required |
| `0x0006` | `0x0001` | signature/authentication failure | no retry; secure boot stop |

The packed error is `{class[15:0], code[15:0]}`. Status is sticky until a W1C
write. A new error replaces the previous value only after the prior value has
been cleared, preventing a late transport response from hiding a boot error.

Malformed header and CRC are distinct even though both reject a development
image. Existing legacy values `0xB0070003` and `0xB0070004` remain firmware
failure mailbox values during migration; the APB status block carries the
canonical class/code pair.

The current RTL can implement all taxonomy, sticky/W1C, retry, and no-preload
behavioral gates. Real flash status bits, dummy-cycle/device mode behavior,
PHY/electrical timing, production erase/program, and signature verification
require external device/security inputs and remain out of this frontend gate.

`rtl/perips/qspi_retry_policy.v` is the reference bounded policy: timeout and
controller-init errors receive one retry; all other classes terminate without
automatic retry.
