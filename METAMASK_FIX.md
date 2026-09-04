# 🔧 MetaMask Conflict Fix + Debug Logging

## Problem
MetaMask error: `Cannot set property ethereum of #<Window> which has only a getter`

This error occurs when multiple wallet extensions try to inject `window.ethereum` and one has already set it as a getter-only property.

## Solution

### 1. Removed window.ethereum from window.d.ts
**Before:**
```typescript
declare global {
  interface Window {
    ethereum?: EthereumProvider;
  }
}
```

**After:**
```typescript
// Do NOT declare window.ethereum to avoid conflicts
export interface EthereumProvider { ... }
```

### 2. Use Type Assertions Instead
Changed all `window.ethereum` references to `(window as any).ethereum`:

**Files Updated:**
- `src/types/window.d.ts` - Removed window.ethereum declaration
- `src/components/wallet/WalletSelector.tsx` - All window.ethereum → (window as any).ethereum
- `src/components/presale/PresaleModal.tsx` - All window.ethereum → (window as any).ethereum

### 3. Added Debug Logging
Added console.log statements to track:
- Button clicks (both header and home page)
- Modal render state (isOpen true/false)
- Portal rendering

**Files Updated:**
- `src/components/layout/AppHeader.tsx` - Button click logging
- `src/components/home/Home.tsx` - Button click logging
- `src/components/presale/PresaleModal.tsx` - Render state logging

---

## 🧪 Testing Instructions

### 1. Hard Refresh Browser
Press `Cmd+Shift+R` (Mac) or `Ctrl+Shift+F5` (Windows)

### 2. Open Browser Console
Press `F12` or `Cmd+Option+I` (Mac)

### 3. Test Header Button
1. Click "JOIN PRESALE" button in header
2. Look for console logs:
   ```
   🚀 JOIN PRESALE button clicked!
   📝 showPresale state set to true
   ✅ PresaleModal: isOpen is true, rendering modal via Portal
   ```
3. Modal should appear on top of everything

### 4. Test Home Page Button
1. Scroll to home page
2. Click "🚀 JOIN PRESALE - BUY WITH ETH/BTC/BNB" button
3. Look for console logs:
   ```
   🚀 [Home] JOIN PRESALE button clicked!
   📝 [Home] showPresale state set to true
   ✅ PresaleModal: isOpen is true, rendering modal via Portal
   ```

### 5. Check for Errors
If you still see the MetaMask error:
- Try disabling other wallet extensions (Rabby, Coinbase, etc.)
- Restart browser
- Clear cache and hard refresh

---

## 🐛 If Modal Still Doesn't Open

### Check Console Logs
Look for these logs to diagnose:

1. **Button click not logging?**
   - Button element might be covered by something else
   - Check z-index of overlapping elements

2. **"showPresale state set to true" but no modal?**
   - React might not be rendering the modal component
   - Check if PresaleModal is imported correctly

3. **"isOpen is false, not rendering"?**
   - State update might not be propagating
   - Check if `showPresale` state is defined in parent component

4. **Portal error?**
   - Check if `createPortal` is imported from 'react-dom'
   - Check if document.body exists when rendering

---

## 📊 Expected Console Output

### On Button Click:
```
🚀 JOIN PRESALE button clicked!
📝 showPresale state set to true
✅ PresaleModal: isOpen is true, rendering modal via Portal
```

### When Modal Opens:
Modal should render at document.body level with:
- Z-index: 999999 (backdrop)
- Z-index: 1000000 (content)
- Dark blurred backdrop
- Centered modal with scrollable content

---

## 🔍 Additional Debugging

If modal still doesn't open, run this in console:

```javascript
// Check if ethereum exists
console.log('window.ethereum:', window.ethereum);

// Check if Portal works
const div = document.createElement('div');
div.textContent = 'TEST PORTAL';
div.style.cssText = 'position:fixed;top:0;left:0;z-index:999999;background:red;color:white;padding:20px;';
document.body.appendChild(div);
```

This will test if:
1. window.ethereum is accessible
2. Portals can render at document.body level

---

## ✅ Success Criteria

After these fixes, you should see:
1. ❌ NO MetaMask error in console
2. ✅ Button clicks logged in console
3. ✅ Modal renders via Portal
4. ✅ Modal appears on top of all content
5. ✅ Modal is centered with dark backdrop

---

**Developer:** Claude Sonnet 4.5  
**Date:** 2026-05-27  
**Status:** Fixed - Ready for testing
