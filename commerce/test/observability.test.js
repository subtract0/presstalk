import {test} from 'node:test';
import assert from 'node:assert/strict';
import {requestObservation,sanitizeObservation} from '../lib/observability.js';

test('receipt credentials, headers, body, unknown paths and error text cannot enter metrics',()=>{
  const secret='PRESSTALK_PRIVATE_SENTINEL';
  const request=new Request('https://example.test/thanks?session_id='+secret,{method:'POST',
    headers:{authorization:secret},body:secret});
  const observation=requestObservation(request,503,19.5,'live');
  assert.deepEqual(observation,{kind:'request',environment:'live',route:'receipt',method:'POST',status:503,milliseconds:19});
  assert(!JSON.stringify(observation).includes(secret));
  assert.equal(requestObservation(new Request('https://example.test/'+secret),404,0,'test').route,'other');
  const cleaned=sanitizeObservation({...observation,route:secret,method:secret,error:secret,url:secret,license:secret});
  assert.equal(cleaned.route,'other');assert.equal(cleaned.method,'OTHER');
  assert(!JSON.stringify(cleaned).includes(secret));
  assert.equal(sanitizeObservation({kind:secret}),null);
  assert.deepEqual(sanitizeObservation({kind:'delivery_run',attempted:50,sent:4,failed:true,
    milliseconds:Infinity,email:secret,session_id:secret}),
    {kind:'delivery_run',environment:'test',attempted:50,sent:4,failed:true,milliseconds:0});
});
