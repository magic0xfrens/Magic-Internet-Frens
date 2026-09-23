# Art adapter, storage and renderer — full source traversals

All source bodies in CauldronArtAdapter, SSTORE2, TraitStorage and FrenRenderer
read. No production change and no final sign-off.

## CauldronArtAdapter

Constructor stores an immutable renderer without zero/code/interface validation.
Deployment must establish that dependency. tokenURI requires contract caller,
then treats caller as collection; no allowlist is intended or needed for a
stateless metadata adapter. traitsOf requires revealed and uses external rarity;
untrusted callers can supply arbitrary sources but cannot alter others' state.
Packed hash inputs are fixed-width address/uint256/uint8, avoiding ambiguous
concatenation. Seven classes, class-specific nonzero body/item counts, twelve
faces; _bodyCount and _itemCount cover every generated class. These are visual
choices, not an unpredictable security RNG: only four rarity possibilities
exist in the normal collection, so the comment claiming pre-reveal art is
unknowable overstates unpredictability. No financial security reliance shown.

API deriveTraits uses the same packing/shifts but obtains counts from generated
TypeScript assets, whereas adapter hardcodes them. Manifest lists two Peasant
bodies; extra unmanifested binaries exist. Full generated-asset/deployed upload
parity remains open; do not infer count mismatch from directory glob alone.

## SSTORE2

write prefixes STOP and uses CREATE with an 11-byte init stub; zero deployment
address reverts. read skips STOP; no-code/STOP-only addresses return empty.
Pointers are not validated generally but TraitStorage only obtains them from
write. Payload size is bounded by CREATE runtime limits, not explicit library
checks. Empty blobs are valid writes. Roundtrip boundaries and deployment-limit
failure need explicit tests. Init code stack inspected: runtime length and offset
are retained for CODECOPY then RETURN. No mutable blob/selfdestruct entrypoint.

## TraitStorage

Constructor ownership; notFrozen plus onlyOwner guard storePalette/storeTrait/
storeTraits. Palette requires positive multiple of three; trait content/key is
not validated. Batch lengths match, repeated keys overwrite pointers, failure
rolls back whole transaction. freeze irreversibly blocks writes but does not
validate completeness or stop ownership transfer/renounce. Owner may freeze an
incomplete or malformed set; deployment validation is mandatory before freeze.
traitKey packs three uint8 without collision. getTrait/getPalette distinguish
missing pointers; getTraitOrEmpty allows missing; hasTrait means pointer exists,
not a valid nonempty blob. These view paths cannot validate rendered art.

## FrenRenderer

Constructor stores TraitStorage. tokenURI wraps numeric/static attributes and
base64 SVG in JSON; no arbitrary text injection. renderSVG obtains palette and
paints face/body/item; _faceClass maps universal/gnome/elf correctly. Header,
gradient/hash/clamp/hex, class labels and attribute helpers inspected. _appendRow
runs same-color pixels and _nibble reads high nibble first. uint arithmetic stays
bounded by byte-sized geometry; appendUint's four-digit scratch is enough for
geometry coordinates <=509 and run width <=255 (comment's 65535 claim is wrong).

Malformed blobs >=8 bytes can panic on palette/pixel reads or local color lookup;
short blobs are skipped and missing global colors become black. TraitStorage
owner controls this input. The buffer called growable is actually fixed at
200,000 bytes; _append/_appendUint use unchecked mcopy, and _finalize rewrites
length. Oversized output can overwrite neighboring memory. Reachable uploaded
payloads and failure behavior need characterization before severity/remediation.

Reproducible shipped-data bound: `python3 audit/SOLIDITY_REAUDIT_2026-09-23/check_art_bound.py`.
ART_BUFFER_BOUND.json hashes every checked binary and computes exact pixel rect
lengths with conservative fixed-header/footer overhead. All combinations from
91 local binaries, including stale extras, fit <=118,476 bytes. This excludes
arbitrary future owner uploads and does not prove memory safety in general.

Executed art-renderer-regressions: five X9a adapter/collection tests pass. Success
uses a five-argument stub renderer, so no actual full renderer image proof.
FrenRendererTest was named in the command but excluded by cauldron profile;
zero tests from it executed. Dedicated renderer profile, real blob roundtrips,
full generated asset parity, worst-case gas and immutable upload verification
remain final gates. No file is signed off from these tests alone.


Renderer continuation: render profile fails compilation on transient storage
syntax in CauldronHook (renderer-profile-tests). run.py metadata says default
cauldron, but explicit env argument selects render; failure is retained.
R23_RendererActual imports the existing real-blob suite under cauldron and all
five tests pass (renderer-real-blobs). Actual SVG test uses ~19.9M gas, URI test
~40.95M including assertion helpers; not an isolated eth_call measurement.
Dense uploaded valid layer reproduction fails; recorded Low FS-artbuffer-01.
