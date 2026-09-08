import { escapeHTML as e } from './mail.js';
import { activationURL } from './license.js';

export const headers={
  'content-type':'text/html; charset=utf-8','cache-control':'no-store, private',
  'referrer-policy':'no-referrer','x-content-type-options':'nosniff',
  'content-security-policy':"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
};
function page(title,body) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${e(title)} · PressTalk</title><style>*{box-sizing:border-box}body{margin:0;background:#f8f7f4;color:#252b26;font:18px/1.65 -apple-system,BlinkMacSystemFont,Arial,sans-serif}main{max-width:700px;margin:8vh auto;padding:28px}h1{font-size:clamp(36px,7vw,54px);line-height:1.12;letter-spacing:-.04em}a{color:#254d3b}header{font-weight:700;margin-bottom:48px}button,.button{display:inline-block;border:0;background:#254d3b;color:white;padding:14px 22px;border-radius:9px;font:inherit;text-decoration:none;cursor:pointer}input,textarea{display:block;width:100%;padding:14px;border:1px solid #a7b1a8;border-radius:7px;background:white;color:#252b26;font:inherit;margin:12px 0 20px}textarea{font:13px/1.5 monospace;overflow-wrap:anywhere;resize:vertical;min-height:160px}.detail{font-size:15px;color:#59645b}.card{background:#eeeee7;padding:20px;border-radius:12px;margin:24px 0}footer{margin-top:48px;font-size:15px}a:focus-visible,button:focus-visible,input:focus-visible,textarea:focus-visible{outline:3px solid #7ea883;outline-offset:3px}</style></head><body><main><header><a href="https://presstalk.app">fn &nbsp; PressTalk</a></header>${body}<footer><a href="https://presstalk.app/download.html">Download for Mac</a> · <a href="/recover">Recover a licence</a> · <a href="mailto:help@presstalk.app">Get help</a></footer></main></body></html>`;
}
export function thanks(order) {
  const download=`/api/license?session_id=${encodeURIComponent(order.session_id)}`;
  return page('Your licence is ready',`<h1>PressTalk is yours.</h1><p>Your payment is complete. Activate the app on your Mac to keep dictating after the trial.</p><p><a class="button" href="${e(activationURL(order.license))}">Activate PressTalk</a></p><p class="detail">Your browser may ask to open PressTalk. Requires the current version.</p><div class="card"><strong>Keep a copy.</strong><p><a href="${e(download)}" download="PressTalk.presstalk-license">Download your licence file</a>. Double-click it on your Mac to activate. We also email your licence to the address used at checkout; if it has not arrived yet, delivery will retry automatically.</p></div><p>Your licence has no expiry and includes every future Mac update we publish. Once activated, it works offline.</p><details><summary>Enter the key manually</summary><p>Open PressTalk Settings → Enter Licence Key, then paste this entire key.</p><label for="license">Your licence key</label><textarea id="license" readonly spellcheck="false">${e(order.license)}</textarea></details>`);
}
export function pending() {
  return page('Checking your purchase','<h1>Checking your purchase.</h1><p>If your payment is still processing, your licence will arrive by email when it clears. You can reload this page to check again.</p><p>No need to pay a second time.</p>');
}
export function unavailable() {
  return page('Purchase unavailable','<h1>We could not open this receipt.</h1><p>Use the link from your PressTalk email, or recover your licence using the email address you paid with.</p><p><a class="button" href="/recover">Recover my licence</a></p>');
}
export function recovery(sent=false) {
  return page('Recover your licence',sent
    ? '<h1>Check your inbox.</h1><p>If this email matches a completed PressTalk purchase, we will send your licence there. Check your spam folder too.</p><p>The same licence works on your Mac without an account.</p>'
    : '<h1>Your licence, again.</h1><p>Enter the email address you used at checkout. We will send your existing licence to that address.</p><form action="/api/recover" method="post"><label for="email">Purchase email</label><input id="email" type="email" name="email" autocomplete="email" maxlength="254" required><button type="submit">Send my licence</button></form><p class="detail">This sends a purchase receipt only. No mailing list.</p>');
}
export function paused() {
  return page('Purchases paused','<h1>Purchases are paused.</h1><p>Please try again shortly. You can still download PressTalk or recover an existing licence.</p>');
}
