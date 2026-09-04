import { networks } from '@btc-vision/bitcoin';
import { getContract, JSONRpcProvider } from 'opnet';
import { MiFrensAbi } from '../abis/MiFrens.abi';
import * as fs from 'fs';
import { join } from 'path';

const dep = JSON.parse(fs.readFileSync(join(__dirname, '../deployments/testnet.json'), 'utf-8'));
const rpc = new JSONRpcProvider({ url: 'https://testnet.opnet.org', network: networks.opnetTestnet });

const classes = ['Wizard', 'King', 'Knight', 'Apprentice', 'Peasant', 'Gnome', 'Elf'];

async function check(tokenId: bigint): Promise<void> {
    const nftAddr = await rpc.getPublicKeyInfo(dep.contracts.MIFRENS, true);
    if (!nftAddr) throw new Error('Could not resolve address');
    const nft = getContract(nftAddr, MiFrensAbi, rpc, networks.opnetTestnet) as any;

    const traits = await nft.getTokenTraits(tokenId);
    const cls = Number(traits.properties?.classIdx ?? 0);
    const body = Number(traits.properties?.bodyIdx ?? 0);
    const face = Number(traits.properties?.faceIdx ?? 0);
    const item = Number(traits.properties?.itemIdx ?? 0);

    const res = await nft.tokenURI(tokenId);
    if (res.revert) {
        console.log(`Token #${tokenId}: REVERT — ${res.revert}`);
        return;
    }
    const uri: string = res.properties?.uri?.toString() ?? '';

    let imgLen = 0;
    let name = '';
    if (uri.startsWith('data:application/json')) {
        const jsonStr = decodeURIComponent(uri.replace('data:application/json,', ''));
        const parsed = JSON.parse(jsonStr);
        imgLen = parsed.image?.length ?? 0;
        name = parsed.name ?? '';
    }

    console.log(
        `Token #${tokenId}: ${classes[cls]} (c=${cls} b=${body} f=${face} i=${item}) | ` +
        `name="${name}" | URI=${uri.length}b | img=${imgLen}b`
    );
}

(async () => {
    for (const id of [1n, 2n, 3n, 5n, 10n, 50n]) {
        try {
            await check(id);
        } catch (e: any) {
            console.log(`Token #${id}: ERROR — ${e.message}`);
        }
    }
    await rpc.close();
})();
