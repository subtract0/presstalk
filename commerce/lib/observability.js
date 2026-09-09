const routes=new Map([['/buy','buy'],['/thanks','receipt'],['/api/license','licence'],
  ['/recover','recovery_form'],['/api/recover','recovery'],['/api/stripe-webhook','stripe_webhook'],
  ['/api/health','health'],['/api/retry','retry']]);
const labels=new Set(routes.values());
const count=value=>Number.isFinite(value)?Math.max(0,Math.min(86400000,Math.floor(value))):0;

export function requestObservation(request,status,milliseconds,environment) {
  return sanitizeObservation({kind:'request',route:routes.get(new URL(request.url).pathname)||'other',
    method:request.method,status,milliseconds,environment});
}
// A strict allowlist at both ends of the binding. Never forward a Request,
// exception, provider response, customer identifier or arbitrary log field.
export function sanitizeObservation(value) {
  const environment=value?.environment==='live'?'live':'test';
  if(value?.kind==='request') return {kind:'request',environment,
    route:labels.has(value.route)?value.route:'other',
    method:['GET','POST','HEAD'].includes(value.method)?value.method:'OTHER',
    status:Number.isInteger(value.status)&&value.status>=100&&value.status<=599?value.status:0,
    milliseconds:count(value.milliseconds)};
  if(value?.kind==='delivery_run') return {kind:'delivery_run',environment,
    attempted:count(value.attempted),sent:count(value.sent),failed:value.failed===true,
    milliseconds:count(value.milliseconds)};
  return null;
}
