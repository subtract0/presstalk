import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {campaignCheckoutURL} from '../lib/campaign.js';
import {handler} from '../lib/handler.js';

const query='utm_source=4chan&utm_medium=display&utm_campaign=presstalk_g_v1&utm_content=prompt_desktop';
const checkout='https://buy.stripe.com/live_fixture';
const source=readFileSync(new URL('../../site/campaign.js',import.meta.url),'utf8');
function decorate(path,hrefs) {
  const anchors=hrefs.map(href=>({href,getAttribute:()=>href}));
  vm.runInNewContext(source,{URL,window:{location:{href:'https://presstalk.app/'+path}},
    document:{querySelectorAll:()=>anchors}});
  return anchors.map(a=>a.href);
}
test('a campaign click survives landing, download, buy and the verified checkout redirect',async()=>{
  const [download,sourceLink,binary,privateReceipt]=decorate('voice-to-text.html?'+query,
    ['download.html','https://github.com/subtract0/presstalk',
     'https://github.com/subtract0/presstalk/releases/download/v0.1.25/PressTalk-0.1.25-macos-arm64.dmg',
     'https://presstalk-licenses.presstalk.workers.dev/thanks?session_id=private_fixture']);
  assert.equal(download,'https://presstalk.app/download.html?'+query);
  assert.equal(sourceLink,'https://github.com/subtract0/presstalk');
  assert(!binary.includes('utm_'));assert(!privateReceipt.includes('utm_'));
  const [buy]=decorate(new URL(download).pathname.slice(1)+new URL(download).search,['buy.html']);
  const [service]=decorate(new URL(buy).pathname.slice(1)+new URL(buy).search,
    ['https://presstalk-licenses.presstalk.workers.dev/buy']);
  let healthChecks=0;
  const serve=handler({store:{health:async()=>{healthChecks++;}}},
    {salesEnabled:true,liveMode:true,paymentLinkID:'plink_fixture'},
    {paymentLinks:{retrieve:async id=>{assert.equal(id,'plink_fixture');return {active:true,livemode:true,url:checkout};}}});
  const response=await serve(new Request(service));
  assert.equal(response.status,303);assert.equal(healthChecks,1);
  const destination=new URL(response.headers.get('location'));
  assert.equal(destination.origin,'https://buy.stripe.com');
  assert.equal(destination.pathname,'/live_fixture');
  assert.equal(destination.searchParams.get('client_reference_id'),'presstalk_g_v1_prompt_desktop');
  assert.equal(destination.searchParams.get('utm_content'),'prompt_desktop');
});
test('all creative labels are accepted; unexpected values and duplicate fields are ignored',()=>{
  for(const creative of ['prompt_desktop','privacy_desktop','prompt_mobile','privacy_mobile']) {
    const request='https://licenses.example/buy?'+query.replace('prompt_desktop',creative);
    assert.equal(new URL(campaignCheckoutURL(checkout,request,{liveMode:true})).searchParams.get('client_reference_id'),
      `presstalk_g_v1_${creative}`);
  }
  for(const bad of ['',query.replace('4chan','other'),query.replace('display','email'),
    query.replace('presstalk_g_v1','different'),query.replace('prompt_desktop','buyer_email'),
    query+'&utm_source=4chan',query+'&utm_content=privacy_desktop']) {
    assert.equal(campaignCheckoutURL(checkout,'https://licenses.example/buy?'+bad,{liveMode:true}),checkout);
    assert.deepEqual(decorate('voice-to-text.html?'+bad,['buy.html']),['buy.html']);
  }
});
test('tracking cannot change prices, destinations or pass customer data into Stripe',()=>{
  const request='https://licenses.example/buy?'+query+
    '&prefilled_email=private%40example.test&client_reference_id=private&redirect=https://evil.test&session_id=private&price=0';
  const url=new URL(campaignCheckoutURL(checkout,request,{liveMode:true}));
  assert.deepEqual([...url.searchParams.keys()].sort(),
    ['client_reference_id','utm_campaign','utm_content','utm_medium','utm_source']);
  assert(!url.href.includes('private'));assert(!url.href.includes('evil'));
  const [buy]=decorate('voice-to-text.html?'+query+'&session_id=private&email=private',['buy.html']);
  assert(!buy.includes('private'));
});
test('test acceptance references and untagged traffic remain unchanged',()=>{
  const privateLink=checkout+'?client_reference_id=acceptance_fixture';
  assert.equal(campaignCheckoutURL(privateLink,'https://licenses.example/buy?'+query,{liveMode:false}),privateLink);
  assert.equal(campaignCheckoutURL(privateLink,'https://licenses.example/buy?'+query,{liveMode:true}),privateLink);
  assert.equal(campaignCheckoutURL(checkout,'https://licenses.example/buy',{liveMode:true}),checkout);
});
test('the sales switch and inactive payment link still block tagged purchases',async()=>{
  const commerce={store:{health:async()=>{}}};
  const stripe={paymentLinks:{retrieve:async()=>({active:false,livemode:true,url:checkout})}};
  for(const salesEnabled of [false,true]) {
    const serve=handler(commerce,{salesEnabled,liveMode:true,paymentLinkID:'plink_fixture'},stripe);
    const response=await serve(new Request('https://licenses.example/buy?'+query));
    assert.equal(response.status,503);assert.equal(response.headers.get('location'),null);
  }
});
