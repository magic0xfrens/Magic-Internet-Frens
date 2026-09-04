import { getContract, JSONRpcProvider, ABIDataTypes, BitcoinAbiTypes } from 'opnet';
import { networks } from '@btc-vision/bitcoin';

const abi = [
    { name: 'getGlobalPalette', inputs: [], outputs: [{ name: 'data', type: ABIDataTypes.BYTES }], type: BitcoinAbiTypes.Function },
    { name: 'getTraitImage', inputs: [{ name: 'traitKey', type: ABIDataTypes.UINT256 }], outputs: [{ name: 'data', type: ABIDataTypes.BYTES }], type: BitcoinAbiTypes.Function },
];

async function main() {
    const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

    const forgeAddr = await rpc.getPublicKeyInfo('opt1sqr0y94t0r839609tan5tgtfh58mtd9apr5sqrpyc', true);
    console.log('Forge resolved:', forgeAddr ? 'yes' : 'no');

    const contract = getContract(forgeAddr, abi, rpc, networks.opnetTestnet);

    console.log('Calling getGlobalPalette...');
    const palResult = await contract.getGlobalPalette();
    if (palResult.revert) {
        console.log('REVERT:', palResult.revert);
    } else if (palResult.properties) {
        const data = palResult.properties.data;
        if (data) {
            const arr = data instanceof Uint8Array ? data : new Uint8Array(data);
            console.log('Palette size:', arr.length, 'bytes');
        } else {
            console.log('properties:', JSON.stringify(Object.keys(palResult.properties)));
        }
    }

    console.log('Calling getTraitImage(0) [wizard body 0]...');
    const r1 = await contract.getTraitImage(0n);
    if (r1.revert) console.log('REVERT:', r1.revert);
    else {
        const d = r1.properties?.data;
        if (d) console.log('Body trait size:', (d instanceof Uint8Array ? d : new Uint8Array(d)).length, 'bytes');
        else console.log('No data property. Keys:', Object.keys(r1.properties || {}));
    }

    console.log('Calling getTraitImage(65536) [face 0-0]...');
    const r2 = await contract.getTraitImage(65536n);
    if (r2.revert) console.log('REVERT:', r2.revert);
    else {
        const d = r2.properties?.data;
        if (d) console.log('Face trait size:', (d instanceof Uint8Array ? d : new Uint8Array(d)).length, 'bytes');
        else console.log('No data property');
    }

    await rpc.close();
}

main().catch(e => { console.error(e.message); process.exit(1); });
