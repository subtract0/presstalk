import {randomBytes} from 'node:crypto';
import {escapeHTML as e} from './mail.js';
import {activationURL} from './license.js';
import {page,headers} from './pages.js';

export const requestID=()=>randomBytes(24).toString('base64url');
const date=value=>new Date(value).toLocaleString('en-GB',{timeZone:'UTC',dateStyle:'medium',timeStyle:'short'})+' UTC';
const hidden=(name,value)=>`<input type="hidden" name="${name}" value="${e(String(value))}">`;
const urlFor=(g,origin)=>`${origin}/gift/${g.token}`;
function status(g,now) {
  if(g.revoked)return 'Link disabled';
  if(g.claimed_at===null)return g.kind==='gift'?'Free forever · waiting to be claimed':`${g.days} days · starts when claimed`;
  if(g.kind==='gift')return 'Free forever · claimed';
  return `${g.expires_at<=now?'Expired':'Access until'} ${date(g.expires_at)}`;
}
const copyScript=`document.querySelectorAll('[data-copy]').forEach(button=>button.addEventListener('click',async()=>{const input=document.getElementById(button.dataset.copy);try{await navigator.clipboard.writeText(input.value);button.textContent='Copied';}catch{input.focus();input.select();button.textContent='Selected — press ⌘C';}}));`;
export function documentResponse(title,body,{status=200,script='',extra={}}={}) {
  const nonce=requestID();
  let html=page(title,body);
  if(script)html=html.replace('</body>',`<script nonce="${nonce}">${script}</script></body>`);
  // no-referrer makes browser navigation POSTs send Origin: null. Same-origin
  // retains CSRF validation while still withholding private URLs off-site.
  return new Response(html,{status,headers:{...headers,'referrer-policy':'same-origin',
    'content-security-policy':headers['content-security-policy']+`; script-src 'nonce-${nonce}'`,...extra}});
}
export function loginPage() {
  return documentResponse('Opening your manager',`<h1>Opening your manager.</h1><p id="message">Signing you in securely…</p><form action="/admin/login" method="post" id="login">${hidden('code','')}</form><noscript>Enable JavaScript, then open Manage PressTalk from Downloads again.</noscript>`,{
    script:`const code=location.hash.slice(1);history.replaceState(null,'','/admin/enter');if(/^[A-Za-z0-9_-]{43}$/.test(code)){document.querySelector('[name=code]').value=code;document.getElementById('login').submit();}else{document.getElementById('message').textContent='Open Manage PressTalk from Downloads to sign in.';}`,
  });
}
export function signedOut() {
  return documentResponse('Your PressTalk manager','<h1>Your PressTalk manager.</h1><p>Open <strong>Manage PressTalk.command</strong> in Downloads on your Mac to sign in.</p><p>This page is private. People receiving a gift only see their own invitation.</p>',{status:401});
}
export function manager({grants,more,page:pageNumber,search,selected,origin,now}) {
  const row=g=>`<article class="card" id="grant-${e(g.id)}"><h2>${e(g.label)}</h2><p>${e(status(g,now))}</p>${g.revoked?'':`<label for="link-${e(g.id)}">Link to share</label><input id="link-${e(g.id)}" readonly value="${e(urlFor(g,origin))}"><p><button type="button" data-copy="link-${e(g.id)}">Copy link</button></p>${g.claimed_at!==null&&g.kind==='extension'?'<p class="detail">After adding time, send this same link again. They must activate the updated licence on their Mac.</p>':''}<form action="/admin/change" method="post">${hidden('id',g.id)}${hidden('revision',g.revision)}${hidden('operation',requestID())}<div class="actions">${g.kind==='extension'?'<button name="action" value="7">+7 days</button><button name="action" value="30">+30 days</button><button name="action" value="gift">Make free forever</button>':''}</div><details><summary>Link controls</summary><p class="detail">Disabling stops future access to this link. An already imported offline licence keeps working until its expiry; a permanent licence cannot be revoked.</p><button class="secondary" name="action" value="disable">Disable this link</button></details></form>`}</article>`;
  const query=p=>`/admin?page=${p}&q=${encodeURIComponent(search)}`;
  return documentResponse('Manage access',`<style>main{max-width:850px}h2{font-size:23px;overflow-wrap:anywhere}.actions{display:flex;flex-wrap:wrap;gap:10px;margin:16px 0}input[type=hidden]{display:none}input[readonly]{font:14px/1.5 monospace}.secondary{background:#e0e4dd;color:#254d3b}details{margin-top:18px}summary{cursor:pointer}form{margin:0}.notice{border:2px solid #254d3b;padding:18px;border-radius:12px}</style><h1>Give someone more PressTalk.</h1><p>Choose extra time or a permanent free licence, then share their link. No payment or account needed.</p>${selected?`<section class="notice"><strong>${selected.revoked?'Link disabled.':'Ready to share.'}</strong>${row(selected)}${selected.revoked?'':'<p class="detail">Keep this link between you and its recipient. Anyone with it can claim the licence.</p>'}</section>`:''}<section class="card"><h2>New invitation</h2><form action="/admin/create" method="post">${hidden('id',requestID())}<label for="label">Name or email — only visible to you</label><input id="label" name="label" maxlength="254" placeholder="e.g. Moritz" required><div class="actions"><button name="choice" value="7">Give 7 days</button><button name="choice" value="30">Give 30 days</button><button name="choice" value="gift">Free forever</button></div></form><p class="detail">Extra time starts when they claim it. Extensions require PressTalk 0.1.25 or later; their link explains how to update. Free licences also work in 0.1.24.</p></section><h2>Your invitations</h2><form action="/admin" method="get"><label for="q">Find a person</label><input id="q" name="q" value="${e(search)}" maxlength="254"><button class="secondary">Search</button> <a href="/admin">Show all</a></form>${grants.length?grants.filter(g=>g.id!==selected?.id).map(row).join(''):'<p>No invitations yet.</p>'}<p>${pageNumber>0?`<a href="${e(query(pageNumber-1))}">← Newer</a> &nbsp; `:''}${more?`<a href="${e(query(pageNumber+1))}">Older →</a>`:''}</p><form action="/admin/logout" method="post"><button class="secondary">Sign out</button></form>`,{script:copyScript});
}
export function gift(grant,now) {
  const temporary=grant.kind==='extension',path=`/gift/${grant.token}`;
  const expired=temporary&&grant.expires_at!==null&&grant.expires_at<=now;
  const title=temporary?'More time with PressTalk.':'PressTalk is yours.';
  let body=`<h1>${title}</h1>`;
  if(grant.claimed_at===null) {
    body+=`<p>${temporary?`You have ${grant.days} days of free dictation, starting when you claim this invitation.`:'You have a permanent free Mac licence, including every future Mac update we publish.'}</p><p>No card. No account. No automatic charge.</p>${temporary?'<p><strong>Before claiming:</strong> <a href="https://presstalk.app/download.html">update to PressTalk 0.1.25 or later</a>. Keep the same app and settings; older versions cannot read an extension.</p>':''}<form method="post" action="${path}/claim"><button>${temporary?'Start my extra time':'Claim my free licence'}</button></form>`;
  } else if(expired) {
    body+=`<p>Your extra time ended on ${e(date(grant.expires_at))}.</p><p>Ask the person who shared this link for more time, or <a href="https://presstalk.app/download.html#buy">buy PressTalk once</a> to keep it.</p>`;
  } else {
    body+=`<p>${temporary?`Your free access lasts until <strong>${e(date(grant.expires_at))}</strong>.`:'Your Mac licence has no expiry and includes every future Mac update we publish.'}</p><p><a class="button" href="${e(activationURL(grant.license))}">Activate PressTalk</a></p><p class="detail">${temporary?'Requires PressTalk 0.1.25 or later. ':''}Your browser may ask to open the app. After activation, it works offline.</p><div class="card"><p><a href="${path}/license" download="PressTalk.presstalk-license">Download your licence file</a> and double-click it on your Mac. Keep this page to collect any extra time your host adds.</p></div><details><summary>Enter the key manually</summary><p>Open PressTalk Settings → Enter Licence Key and paste the entire key.</p><label for="license">Licence key</label><textarea id="license" readonly spellcheck="false">${e(grant.license)}</textarea><button type="button" data-copy="license">Copy key</button></details>`;
  }
  return documentResponse(title,body,{script:copyScript});
}
