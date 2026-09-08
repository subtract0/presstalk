import { activationURL } from './license.js';

export const escapeHTML = value => String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

export function receipt(order,config) {
  const receiptURL=`${config.origin}/thanks?session_id=${encodeURIComponent(order.session_id)}`;
  const activate=activationURL(order.license);
  const text=`Thank you for buying PressTalk.\n\nYour Mac licence is ready.\n\nActivate PressTalk: ${activate}\n\nOr open the attached PressTalk licence file on your Mac. You can also paste the key below into PressTalk Settings → Enter Licence Key.\n\n${order.license}\n\nKeep this email. Your licence has no expiry, works offline, and includes every future Mac update we publish. No account or subscription.\n\nYour receipt and download: ${receiptURL}\nRecover your licence: ${config.origin}/recover\n\nFor help or a refund within 14 days, reply to this email.\nPressTalk\n`;
  const html=`<!doctype html><html><body style="font-family:-apple-system,Arial,sans-serif;color:#242824;line-height:1.6;max-width:600px;margin:32px auto;padding:20px"><h1>Your Mac licence is ready.</h1><p>Thank you for buying PressTalk.</p><p><a href="${escapeHTML(receiptURL)}" style="display:inline-block;padding:12px 20px;background:#254d3b;color:white;border-radius:8px;text-decoration:none">Activate PressTalk</a></p><p>Open the attached licence file on your Mac, or paste this key into <strong>PressTalk Settings → Enter Licence Key</strong>:</p><p style="font-family:monospace;overflow-wrap:anywhere;word-break:break-all;background:#f3f3ef;padding:16px">${escapeHTML(order.license)}</p><p>Keep this email. Your licence has no expiry, works offline, and includes every future Mac update we publish. No account or subscription.</p><p><a href="${escapeHTML(config.origin)}/recover">Recover a lost licence</a> · <a href="https://presstalk.app/download.html">Download PressTalk</a></p><p>For help or a refund within 14 days, reply to this email.</p></body></html>`;
  return {from:config.mailFrom,to:[order.email],reply_to:config.mailReplyTo,
    subject:'Your PressTalk licence — ready for your Mac',text,html,
    attachments:[{filename:'PressTalk.presstalk-license',content:Buffer.from(order.license+'\n').toString('base64')}]};
}

export class ResendMailer {
  // Keep fetch's global receiver in Workers. Storing the native function as an
  // object method works in Node but throws Illegal invocation at the edge.
  constructor(config,fetcher=(...args)=>fetch(...args)) { this.config=config;this.fetcher=fetcher; }
  async send(order,idempotencyKey) {
    const response=await this.fetcher('https://api.resend.com/emails',{
      method:'POST',signal:AbortSignal.timeout(12000),
      headers:{authorization:`Bearer ${this.config.resendKey}`,'content-type':'application/json','Idempotency-Key':idempotencyKey},
      body:JSON.stringify(receipt(order,this.config)),
    });
    if (!response.ok) throw new Error(`mail_http_${response.status}`);
    const data=await response.json();
    if (!data.id) throw new Error('mail_missing_receipt');
    return data.id;
  }
}
