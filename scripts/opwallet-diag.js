/**
 * OPWallet NFT Image Diagnostic Script
 *
 * Paste this into the OPWallet popup's DevTools console
 * (right-click popup → Inspect → Console tab)
 *
 * It tests every step of the image rendering pipeline and reports
 * exactly where the failure occurs.
 */
(async () => {
  const log = (msg) => console.log('%c[DIAG] ' + msg, 'color: #0af');
  const pass = (msg) => console.log('%c[PASS] ' + msg, 'color: #4f4');
  const fail = (msg) => console.log('%c[FAIL] ' + msg, 'color: #f44; font-weight: bold');

  log('=== OPWallet NFT Image Diagnostic ===');

  // Step 0: Check CSP
  log('Step 0: Checking CSP...');
  const cspMeta = document.querySelector('meta[http-equiv="Content-Security-Policy"]');
  log('  CSP meta tag: ' + (cspMeta ? cspMeta.content : 'none'));

  // Step 1: Test basic data URI Image load
  log('Step 1: Loading 1x1 PNG data URI via new Image()...');
  const step1 = await new Promise((resolve) => {
    const img = new Image();
    const t = setTimeout(() => resolve('TIMEOUT (3s)'), 3000);
    img.onload = () => { clearTimeout(t); resolve('OK (' + img.naturalWidth + 'x' + img.naturalHeight + ')'); };
    img.onerror = (e) => { clearTimeout(t); resolve('BLOCKED/ERROR: ' + e.type); };
    img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==';
  });
  (step1.startsWith('OK') ? pass : fail)('  Image load: ' + step1);

  // Step 2: Test canvas re-encode
  log('Step 2: Canvas re-encode of data URI...');
  const step2 = await new Promise((resolve) => {
    const img = new Image();
    img.onload = () => {
      try {
        const c = document.createElement('canvas');
        c.width = 1; c.height = 1;
        c.getContext('2d').drawImage(img, 0, 0);
        const re = c.toDataURL('image/png');
        resolve('OK (reencoded ' + re.length + ' chars)');
      } catch (e) {
        resolve('CANVAS ERROR: ' + e.message);
      }
    };
    img.onerror = () => resolve('IMAGE LOAD FAILED');
    img.src = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==';
  });
  (step2.startsWith('OK') ? pass : fail)('  Canvas: ' + step2);

  // Step 3: Test CSS backgroundImage with data URI
  log('Step 3: CSS backgroundImage with data URI...');
  const testDiv = document.createElement('div');
  testDiv.style.cssText = 'width:50px;height:50px;position:fixed;top:-999px;';
  testDiv.style.backgroundImage = 'url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwADhQGAWjR9awAAAABJRU5ErkJggg==)';
  document.body.appendChild(testDiv);
  const bgSet = window.getComputedStyle(testDiv).backgroundImage !== 'none';
  document.body.removeChild(testDiv);
  (bgSet ? pass : fail)('  backgroundImage set: ' + bgSet);

  // Step 4: Check for CSP violations
  log('Step 4: Listening for CSP violations...');
  let cspViolations = [];
  const cspHandler = (e) => cspViolations.push(e.violatedDirective + ' → ' + e.blockedURI);
  document.addEventListener('securitypolicyviolation', cspHandler);

  // Step 5: Find existing asyncImage elements on the page
  log('Step 5: Checking current page state...');
  const asyncImages = document.querySelectorAll('.asyncImage');
  const loadedImages = document.querySelectorAll('.loaded');
  const errorImages = document.querySelectorAll('.load-error');
  log('  .asyncImage elements (pending): ' + asyncImages.length);
  log('  .loaded elements (success): ' + loadedImages.length);
  log('  .load-error elements (failed): ' + errorImages.length);

  asyncImages.forEach((el, i) => {
    const src = el.dataset.src || '(none)';
    const isData = src.startsWith('data:');
    log('  asyncImage[' + i + ']: ' + (isData ? 'data URI (' + src.length + ' chars)' : src.substring(0, 80)));
  });

  loadedImages.forEach((el, i) => {
    const bg = el.style.backgroundImage || '(none)';
    log('  loaded[' + i + ']: bg=' + bg.substring(0, 80));
  });

  errorImages.forEach((el, i) => {
    log('  load-error[' + i + ']: innerHTML=' + el.innerHTML.substring(0, 100));
  });

  // Step 6: Find NFT cards and check metadata
  log('Step 6: Checking NFT metadata...');
  const allDivs = document.querySelectorAll('[data-src]');
  log('  Elements with data-src: ' + allDivs.length);
  allDivs.forEach((el, i) => {
    const src = el.dataset.src || '';
    const classes = el.className;
    log('  [' + i + '] class="' + classes + '" src=' + (src.startsWith('data:') ? 'data:...' + src.length + 'chars' : src.substring(0, 60)));
  });

  // Step 7: Try the full OPWallet pipeline with actual NFT data URI
  log('Step 7: Testing full pipeline with actual NFT image data URI...');
  const testImageUri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABABAMAAABYR2ztAAAAMFBMVEUAAAAxHBUmFQ8jGhUOBwVBJxxJLCHVqYzt1bDClnz/6czgvp1xTDphQjJXOSy5iGi87pSuAAAAAXRSTlMAQObYZgAAAe1JREFUSMftlM1ugzAQhN3QNHZSA6ekTnOmSnLGUsp5kZI8AI3z/q9SG9trbZNDD5V6qMTl0+zsj4fxn38djV4AaJkQ7K0DPw/g+3cA4k0yHKadAqhbA67DAHBiEhzACbFSaIqAZ0KMBYB7SuDYPHzgFKNxaEDhZBJwEd0zq5F6NjA0gDjtkbk0wDgNgEzaGTr6j8NuE4DZNJhbQNsKzPugBv1D8cXMzd7O1AB5FsD8uNfugOsE1IQAM6O2qn6FMBQK0LMBIA+A==';

  // Test the OPWallet regex
  const DATA_URI_PATTERN = /^data:(image\/[a-zA-Z0-9.+-]+);base64,([A-Za-z0-9+\/=]+)$/;
  const match = testImageUri.match(DATA_URI_PATTERN);
  (match ? pass : fail)('  Regex match: ' + !!match);

  if (match) {
    const ALLOWED = new Set(['image/png','image/jpeg','image/gif','image/webp','image/bmp','image/avif','image/svg+xml']);
    (ALLOWED.has(match[1]) ? pass : fail)('  MIME allowed: ' + match[1]);

    // Test canvas reencode with this real image
    const step7 = await new Promise((resolve) => {
      const img = new Image();
      const t = setTimeout(() => resolve('TIMEOUT (5s)'), 5000);
      img.onload = () => {
        clearTimeout(t);
        try {
          const c = document.createElement('canvas');
          c.width = img.naturalWidth; c.height = img.naturalHeight;
          c.getContext('2d').drawImage(img, 0, 0);
          const re = c.toDataURL('image/png');
          // Try loading the reencoded image
          const img2 = new Image();
          img2.onload = () => resolve('FULL PIPELINE OK (' + img.naturalWidth + 'x' + img.naturalHeight + ', reencoded=' + re.length + ')');
          img2.onerror = () => resolve('REENCODED IMAGE LOAD FAILED');
          img2.src = re;
        } catch (e) {
          resolve('CANVAS ERROR: ' + e.message);
        }
      };
      img.onerror = () => { clearTimeout(t); resolve('IMAGE LOAD FAILED'); };
      img.src = testImageUri;
    });
    (step7.includes('OK') ? pass : fail)('  Full pipeline: ' + step7);
  }

  // Wait for any CSP violations
  await new Promise((r) => setTimeout(r, 1000));
  document.removeEventListener('securitypolicyviolation', cspHandler);
  if (cspViolations.length > 0) {
    fail('CSP VIOLATIONS DETECTED:');
    cspViolations.forEach((v) => fail('  ' + v));
  } else {
    pass('No CSP violations detected');
  }

  log('=== Diagnostic Complete ===');
  log('If all tests PASS but images still don\'t show, paste this to check ImageService:');
  log('  document.querySelectorAll(".asyncImage, .loaded, .load-error").forEach(e => console.log(e.className, e.style.backgroundImage?.substring(0,60), e.offsetWidth+"x"+e.offsetHeight))');
})();
