// Isolated browser acceptance: no production credentials, payments or email.
import assert from 'node:assert/strict';
import {readFile,readdir,mkdir,writeFile} from 'node:fs/promises';
import {Miniflare,convertV4MiniflareOptions} from 'miniflare';
import {chromium} from 'playwright';
const output=new URL('../../.local/access-grants-25/browser/',import.meta.url);await mkdir(output,{recursive:true});
const origin='http://localhost:18879';
const fixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/access-license.json',import.meta.url),'utf8'));
const runtime=new Miniflare(convertV4MiniflareOptions({modules:true,port:18879,host:'127.0.0.1',
  script:await readFile(new URL('../../.local/commerce/worker-bundle/worker.js',import.meta.url),'utf8'),
  compatibilityDate:'2026-09-08',compatibilityFlags:['nodejs_compat'],d1Databases:['ORDERS'],
  bindings:{STRIPE_SECRET_KEY:'sk_test_fixture',STRIPE_WEBHOOK_SECRET:'whsec_fixture',STRIPE_LIVE_MODE:'false',
    STRIPE_TEST_REFERENCE:'fixture-reference-'.repeat(3),STRIPE_PAYMENT_LINK_ID:'plink_test',STRIPE_PRICE_ID:'price_test',STRIPE_CURRENCIES:'eur',
    LICENSE_KEY_ID:'test-only',LICENSE_PRIVATE_KEY:Buffer.alloc(32,7).toString('base64'),LICENSE_PUBLIC_KEY:fixture.publicKey,
    RESEND_API_KEY:'test-only',MAIL_FROM:'PressTalk <licenses@presstalk.app>',MAIL_REPLY_TO:'help@presstalk.app',PUBLIC_ORIGIN:origin,
    RECOVERY_PEPPER:'test'.repeat(16),CRON_SECRET:'cron'.repeat(16),SALES_ENABLED:'false',ADMIN_TOKEN:'operator-test-'.repeat(5)},
  outboundService:async()=>{throw new Error('Unexpected external request');},
}));
let browser;const errors=[];
try {
  await runtime.ready;const db=await runtime.getD1Database('ORDERS');
  for(const name of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')).sort())
    for(const sql of (await readFile(new URL('../migrations/'+name,import.meta.url),'utf8')).split(';').filter(x=>x.trim()))await db.prepare(sql).run();
  const login=await runtime.dispatchFetch(origin+'/admin/link',{method:'POST',headers:{authorization:'Bearer '+'operator-test-'.repeat(5)}});
  const loginURL=(await login.json()).url;
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
  const owner=await browser.newContext({viewport:{width:1280,height:900},permissions:['clipboard-read','clipboard-write']});
  const page=await owner.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('console',m=>{if(m.type()==='error')console.log('Browser:',m.text());});
  await page.goto(loginURL);try{await page.waitForURL(origin+'/admin',{timeout:10000});}catch(error){console.log({url:page.url().split('#')[0],body:await page.locator('body').innerText(),errors});throw error;}
  await page.getByLabel('Name or email — only visible to you').fill('Moritz — review example');
  await page.getByRole('button',{name:'Give 7 days',exact:true}).click();await page.waitForURL('**/admin?created=*');
  await page.getByRole('button',{name:'Copy link',exact:true}).click();
  const giftURL=await page.evaluate(()=>navigator.clipboard.readText());assert(giftURL.startsWith(origin+'/gift/'));
  for(const width of [1280,390]){await page.setViewportSize({width,height:900});assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);await page.screenshot({path:new URL('manager-'+width+'.png',output).pathname,fullPage:true});}
  const recipient=await browser.newContext({viewport:{width:390,height:900}}),giftPage=await recipient.newPage();
  giftPage.on('pageerror',e=>errors.push(e.message));await giftPage.goto(giftURL);
  assert((await giftPage.locator('body').innerText()).includes('7 days'));assert(!(await giftPage.locator('body').innerText()).includes('Moritz'));
  await giftPage.screenshot({path:new URL('invitation-mobile.png',output).pathname,fullPage:true});
  await giftPage.getByRole('button',{name:'Start my extra time',exact:true}).click();
  await giftPage.getByRole('link',{name:'Activate PressTalk',exact:true}).waitFor();
  const activation=await giftPage.getByRole('link',{name:'Activate PressTalk',exact:true}).getAttribute('href');assert(activation.startsWith('presstalk://activate?license=PRESSTALK-1.'));
  const downloadPromise=giftPage.waitForEvent('download');await giftPage.getByRole('link',{name:'Download your licence file'}).click();
  const download=await downloadPromise;assert.equal(download.suggestedFilename(),'PressTalk.presstalk-license');await download.saveAs(new URL('test-extension.presstalk-license',output).pathname);
  const payload=href=>JSON.parse(Buffer.from(new URL(href).searchParams.get('license').split('.')[2],'base64url'));
  const before=payload(activation);
  await page.reload();await page.getByRole('button',{name:'+30 days',exact:true}).click();await page.waitForURL('**/admin?created=*');await giftPage.reload();
  const after=payload(await giftPage.getByRole('link',{name:'Activate PressTalk',exact:true}).getAttribute('href'));
  assert.equal(Date.parse(after.expiresAt)-Date.parse(before.expiresAt),30*86400000);
  await giftPage.screenshot({path:new URL('claimed-mobile.png',output).pathname,fullPage:true});
  await page.getByRole('button',{name:'Make free forever',exact:true}).click();await page.waitForURL('**/admin?created=*');await giftPage.reload();
  assert((await giftPage.locator('body').innerText()).includes('no expiry'));
  await giftPage.setViewportSize({width:1280,height:900});await giftPage.screenshot({path:new URL('permanent-desktop.png',output).pathname,fullPage:true});
  const recovery=await recipient.newPage();let recoveryOrigin;
  recovery.on('request',request=>{if(request.url().endsWith('/api/recover'))recoveryOrigin=request.headers().origin;});
  await recovery.goto(origin+'/recover');await recovery.getByLabel('Purchase email').fill('nobody@example.test');
  await recovery.getByRole('button',{name:'Send my licence',exact:true}).click();await recovery.waitForURL('**/api/recover');
  assert.equal(recoveryOrigin,origin,'Browser recovery form lost its Origin');
  assert((await recovery.locator('body').innerText()).includes('Check your inbox.'));
  let externalReferrer;
  await giftPage.route('https://presstalk.app/**',async route=>{externalReferrer=route.request().headers().referer;await route.fulfill({status:200,body:'Download destination'});});
  await giftPage.getByRole('link',{name:'Download for Mac',exact:true}).click();
  assert.equal(externalReferrer,undefined,'Gift URL leaked in an external referrer');
  assert.deepEqual(errors,[]);
  await writeFile(new URL('receipt.json',output),JSON.stringify({passed:true,flows:['owner login','create','copy','anonymous claim','download','extend claimed','upgrade permanent','browser recovery','private referrer'],viewports:[390,1280],pageErrors:errors},null,2));
  console.log('PASS: operator and recipient browser journeys, copy, download, extension and permanent upgrade; no page errors or horizontal overflow.');
} finally {await browser?.close();await runtime.dispose();}
