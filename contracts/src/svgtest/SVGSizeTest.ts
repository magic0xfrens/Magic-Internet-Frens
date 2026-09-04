import { u256 } from '@btc-vision/as-bignum/assembly';
import {
    Blockchain,
    BytesWriter,
    Calldata,
    OP_NET,
} from '@btc-vision/btc-runtime/runtime';

// Base64 encoding table
// @ts-ignore: decorator
@inline
const B64_TABLE: StaticArray<u8> = [
    65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90, // A-Z
    97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122, // a-z
    48,49,50,51,52,53,54,55,56,57, // 0-9
    43,47, // +/
];

/**
 * SVGSizeTest -- Lightweight contract to test OPNet RPC response size limits.
 *
 * Three methods to probe different return types:
 *   - testReturn(size)      → raw string of `size` bytes
 *   - testDataURI(svgSize)  → full data:application/json;base64,... tokenURI with SVG
 *   - testBase64URI(rawSize) → data:image/svg+xml;base64,<base64 of rawSize bytes>
 *
 * No storage needed — all data generated in-memory from repeated patterns.
 */
@final
export class SVGSizeTest extends OP_NET {
    public constructor() {
        super();
    }

    public override onDeployment(_calldata: Calldata): void {
        // No-op — no storage to initialize
    }

    // -----------------------------------------------------------------------
    // testReturn(size: uint256) → string
    // Returns a repeated-character string of exactly `size` bytes.
    // -----------------------------------------------------------------------
    @method({ name: 'size', type: ABIDataTypes.UINT256 })
    @returns({ name: 'result', type: ABIDataTypes.STRING })
    public testReturn(calldata: Calldata): BytesWriter {
        const size: u64 = calldata.readU256().toU64();

        // Build a string of 'A' repeated `size` times
        let result: string = '';
        // Build in chunks of 64 to reduce string concatenation overhead
        const chunk64: string = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        const fullChunks: u64 = size / 64;
        const remainder: u64 = size % 64;

        for (let i: u64 = 0; i < fullChunks; i++) {
            result += chunk64;
        }
        for (let i: u64 = 0; i < remainder; i++) {
            result += 'A';
        }

        const writer: BytesWriter = new BytesWriter(4 + result.length);
        writer.writeStringWithLength(result);
        return writer;
    }

    // -----------------------------------------------------------------------
    // testDataURI(svgSize: uint256) → string
    // Builds a full data:application/json;base64,... tokenURI containing
    // an SVG image of approximately `svgSize` bytes.
    // -----------------------------------------------------------------------
    @method({ name: 'svgSize', type: ABIDataTypes.UINT256 })
    @returns({ name: 'result', type: ABIDataTypes.STRING })
    public testDataURI(calldata: Calldata): BytesWriter {
        const svgSize: u64 = calldata.readU256().toU64();

        // Build an SVG with repeated rect elements to reach target size
        const svgHeader: string = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">';
        const svgFooter: string = '</svg>';
        // Each rect: <rect x="0" y="0" width="1" height="1" fill="#f00"/> = ~52 chars
        const rectTemplate: string = '<rect x="0" y="0" width="1" height="1" fill="#f00"/>';
        const headerFooterLen: u64 = (svgHeader.length + svgFooter.length) as u64;

        let svg: string = svgHeader;

        if (svgSize > headerFooterLen) {
            const bodyTarget: u64 = svgSize - headerFooterLen;
            const rectsNeeded: u64 = bodyTarget / (rectTemplate.length as u64);
            const extraChars: u64 = bodyTarget % (rectTemplate.length as u64);

            for (let i: u64 = 0; i < rectsNeeded; i++) {
                svg += rectTemplate;
            }
            // Pad remaining bytes with spaces
            for (let i: u64 = 0; i < extraChars; i++) {
                svg += ' ';
            }
        }

        svg += svgFooter;

        // Base64-encode the SVG
        const svgBytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(svg));
        const b64Svg: string = this._base64Encode(svgBytes);

        // Build JSON: {"name":"Test #1","description":"SVG size test","image":"data:image/svg+xml;base64,..."}
        const json: string = '{"name":"Test #1","description":"SVG size test","image":"data:image/svg+xml;base64,' + b64Svg + '"}';

        // Base64-encode the JSON for the data URI
        const jsonBytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(json));
        const b64Json: string = this._base64Encode(jsonBytes);

        const dataUri: string = 'data:application/json;base64,' + b64Json;

        const writer: BytesWriter = new BytesWriter(4 + dataUri.length);
        writer.writeStringWithLength(dataUri);
        return writer;
    }

    // -----------------------------------------------------------------------
    // testBase64URI(rawSize: uint256) → string
    // Returns data:image/svg+xml;base64,<base64 of rawSize bytes>.
    // -----------------------------------------------------------------------
    @method({ name: 'rawSize', type: ABIDataTypes.UINT256 })
    @returns({ name: 'result', type: ABIDataTypes.STRING })
    public testBase64URI(calldata: Calldata): BytesWriter {
        const rawSize: u64 = calldata.readU256().toU64();

        // Generate raw SVG bytes of target size
        const svgHeader: string = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">';
        const svgFooter: string = '</svg>';
        const filler: string = '<!-- ';
        const fillerEnd: string = ' -->';

        let svg: string = svgHeader;
        const headerFooterLen: u64 = (svgHeader.length + svgFooter.length) as u64;
        const fillerWrapLen: u64 = (filler.length + fillerEnd.length) as u64;

        if (rawSize > headerFooterLen + fillerWrapLen) {
            svg += filler;
            const padLen: u64 = rawSize - headerFooterLen - fillerWrapLen;
            // Pad with 'x' in chunks
            const xChunk: string = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
            const xChunks: u64 = padLen / 64;
            const xRemainder: u64 = padLen % 64;
            for (let i: u64 = 0; i < xChunks; i++) {
                svg += xChunk;
            }
            for (let i: u64 = 0; i < xRemainder; i++) {
                svg += 'x';
            }
            svg += fillerEnd;
        }

        svg += svgFooter;

        // Base64 encode
        const svgBytes: Uint8Array = Uint8Array.wrap(String.UTF8.encode(svg));
        const b64: string = this._base64Encode(svgBytes);

        const dataUri: string = 'data:image/svg+xml;base64,' + b64;

        const writer: BytesWriter = new BytesWriter(4 + dataUri.length);
        writer.writeStringWithLength(dataUri);
        return writer;
    }

    // -----------------------------------------------------------------------
    // Internal: Base64 encoder (zero-alloc byte-level)
    // -----------------------------------------------------------------------

    private _base64Encode(data: Uint8Array): string {
        const len: i32 = data.length;
        const outLen: i32 = ((len + 2) / 3) * 4;
        const out: Uint8Array = new Uint8Array(outLen);
        let j: i32 = 0;

        for (let i: i32 = 0; i < len; i += 3) {
            const b0: u32 = data[i] as u32;
            const b1: u32 = (i + 1 < len) ? (data[i + 1] as u32) : 0;
            const b2: u32 = (i + 2 < len) ? (data[i + 2] as u32) : 0;

            const triple: u32 = (b0 << 16) | (b1 << 8) | b2;

            out[j++] = unchecked(B64_TABLE[((triple >> 18) & 0x3F) as i32]);
            out[j++] = unchecked(B64_TABLE[((triple >> 12) & 0x3F) as i32]);
            out[j++] = (i + 1 < len)
                ? unchecked(B64_TABLE[((triple >> 6) & 0x3F) as i32])
                : 61; // '='
            out[j++] = (i + 2 < len)
                ? unchecked(B64_TABLE[(triple & 0x3F) as i32])
                : 61; // '='
        }

        return String.UTF8.decode(out.buffer);
    }
}
