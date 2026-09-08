// Local visual fixtures only. This does not simulate or certify a payment.
import http from 'node:http';
import { readFile,mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';
import assert from 'node:assert/strict';
import * as pages from '../lib/pages.js';
const fixture=JSON.parse(await readFile(new URL('../../Tests/PressTalkCoreTests/Fixtures/commerce-license.json',import.meta.url),'utf8'));
const output=new URL('../../.local/commerce/visual/',import.meta.url);
await mkdir(output,{recursive:true});
const server=http.createServer((req,res)=>{
  res.writeHead(200,pages.headers);
  res.end(req.url==='/recover'?pages.recovery():pages.thanks({license:fixture.license,session_id:'cs_test_0123456789abcdef'}));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try {
  browser=await chromium.launch({headless:true,executablePath:process.env.CHROMIUM_PATH});
  for(const [name,width,height] of [['desktop',1100,1000],['phone',390,844]]){
    const page=await browser.newPage({viewport:{width,height}});
    await page.goto(`http://127.0.0.1:${server.address().port}/thanks`);
    await page.getByText('Enter the key manually',{exact:true}).click();
    assert.equal(await page.locator('textarea').inputValue(),fixture.license);
    assert.match(await page.getByRole('link',{name:'Activate PressTalk',exact:true}).getAttribute('href'),/^presstalk:\/\/activate\?license=PRESSTALK-1\./);
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'receipt overflows horizontally');
    await page.screenshot({path:new URL(`${name}-receipt.png`,output).pathname,fullPage:true});
    await page.goto(`http://127.0.0.1:${server.address().port}/recover`);
    await page.getByLabel('Purchase email').fill('buyer@example.test');
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'recovery overflows horizontally');
    await page.screenshot({path:new URL(`${name}-recovery.png`,output).pathname,fullPage:true});
    await page.close();
  }
  console.log('Desktop and phone receipt/recovery controls and layout passed. Local fixtures only.');
} finally {await browser?.close();server.close();}
