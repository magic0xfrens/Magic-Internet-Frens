import { Blockchain } from '@btc-vision/btc-runtime/runtime';
import { MiFrens } from './MiFrens';
import { revertOnError } from '@btc-vision/btc-runtime/runtime/abort/abort';

// 1. Factory function - REQUIRED
Blockchain.contract = (): MiFrens => {
    return new MiFrens();
};

// 2. Runtime exports - REQUIRED
export * from '@btc-vision/btc-runtime/runtime/exports';

// 3. Abort handler - REQUIRED
export function abort(message: string, fileName: string, line: u32, column: u32): void {
    revertOnError(message, fileName, line, column);
}
