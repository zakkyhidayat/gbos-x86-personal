# Lenovo identity

Google's `lapis` build names the device **ASUS / "ASUS Googlebook 14"** in `ro.product.<partition>.brand`,
`.manufacturer`, `.model` and `.marketname`, in seven partitions: vendor, product, odm, odm_dlkm, system_ext, system_dlkm
and vendor_dlkm. gbOS86's own `DEVICE_MODEL` only covered the vendor model lines, so Settings still said ASUS.

## How
- `usb/hook.sh` (patch): `DEVICE_BRAND` and `DEVICE_MODEL` from `gbos.cfg` replace those four properties in all seven
  `build.prop` files, whatever value Google's build has, so a newer Google build is covered too. Each file is copied to
  `/tmp/ident.*`, rewritten with `sed` and bind-mounted over the original: the erofs images stay untouched.
- Values containing `/`, `\` or `&` are refused (they would break the `sed` expression); the original names stay then.
- `usb/gbos.cfg` (patch): `DEVICE_BRAND="LENOVO"`, `DEVICE_MODEL="ThinkPad X13 Gen 2i"`.

## Kept on purpose
`ro.product.*.device=lapis` and every build fingerprint (`ASUS/lapis/lapis:17/...`). Play Integrity and Google services
check those against the build Google signed; changing them would break sign-in and Play. Only the names people read change.

## Result
Settings > About phone and the device name show **ThinkPad X13 Gen 2i**, brand **LENOVO**. The boot log has one line per
partition: `hook: identity /new/vendor/build.prop: brand=LENOVO model=ThinkPad X13 Gen 2i`.

## Test
`tools/test_device_model.sh` (in the patch) runs the rewrite on sample `build.prop` files with a non-ASUS name ("Acme"), and
checks the refused characters.

## Known issue: build fingerprint
The internal install's first boot log has `init: Setting property 'ro.build.fingerprint' to
'LENOVO/lapis/lapis:17/CL3B.260622.271.R1/16452207:user/release-keys'`. Google's build does not set `ro.build.fingerprint`
itself, so init composes it from `ro.product.brand` and friends, which the rewrite changed to LENOVO: against the intent
above. (The per-partition `ro.<partition>.build.fingerprint` values are not checked yet.) Google services may then see the
device as uncertified. Fix (not done yet): set `ro.build.fingerprint` explicitly to the ASUS value
in the rewritten vendor build.prop.
