export function configuration(env=process.env,{database='postgres'}={}) {
  const required=name=>{const value=env[name];if(!value)throw new Error(`Missing ${name}`);return value;};
  const origin=new URL(required('PUBLIC_ORIGIN')).origin;
  if(!origin.startsWith('https://') && !origin.startsWith('http://localhost:')) throw new Error('HTTPS origin required');
  if(!['true','false'].includes(env.STRIPE_LIVE_MODE)) throw new Error('Explicit Stripe mode required');
  const liveMode=env.STRIPE_LIVE_MODE==='true';
  const stripeKey=required('STRIPE_SECRET_KEY');
  if(!stripeKey.match(new RegExp(`^(sk|rk)_${liveMode?'live':'test'}_`))) throw new Error('Stripe key mode mismatch');
  const keyID=required('LICENSE_KEY_ID');
  if(!/^[A-Za-z0-9_-]{1,50}$/.test(keyID)) throw new Error('Invalid signing key ID');
  const recoveryPepper=required('RECOVERY_PEPPER'),cronSecret=required('CRON_SECRET');
  if(recoveryPepper.length<32||cronSecret.length<32) throw new Error('Recovery and retry secrets must be at least 32 characters');
  return {origin,liveMode,stripeKey,keyID,recoveryPepper,cronSecret,
    databaseURL:database==='postgres' ? required('DATABASE_URL') : undefined,webhookSecret:required('STRIPE_WEBHOOK_SECRET'),
    paymentLinkID:required('STRIPE_PAYMENT_LINK_ID'),priceID:required('STRIPE_PRICE_ID'),
    currencies:required('STRIPE_CURRENCIES').split(',').map(x=>x.trim()),privateKey:required('LICENSE_PRIVATE_KEY'),
    publicKey:required('LICENSE_PUBLIC_KEY'),resendKey:required('RESEND_API_KEY'),
    mailFrom:required('MAIL_FROM'),mailReplyTo:required('MAIL_REPLY_TO'),
    salesEnabled:env.SALES_ENABLED==='true'};
}
