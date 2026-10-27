// Public, shared campaign labels only. Never forward an arbitrary query string,
// customer identifier, return URL, email address or test acceptance capability.
const fixed = {utm_source:'4chan',utm_medium:'display',utm_campaign:'presstalk_g_v1'};
const creatives = new Set(['prompt_desktop','privacy_desktop','prompt_mobile','privacy_mobile']);

export function campaignCheckoutURL(paymentLinkURL,requestURL,{liveMode}) {
  if (!liveMode) return paymentLinkURL;
  const parameters = new URL(requestURL).searchParams;
  for (const [name,value] of Object.entries(fixed)) {
    if (parameters.getAll(name).length!==1 || parameters.get(name)!==value) return paymentLinkURL;
  }
  const creative=parameters.get('utm_content');
  if (parameters.getAll('utm_content').length!==1 || !creatives.has(creative)) return paymentLinkURL;
  const target=new URL(paymentLinkURL);
  // The URL comes from Stripe, but do not overwrite an existing reconciliation
  // reference if a future configuration uses one for a different purpose.
  if(target.searchParams.has('client_reference_id')) return paymentLinkURL;
  for(const [name,value] of Object.entries({...fixed,utm_content:creative})) target.searchParams.set(name,value);
  // Shared by everyone arriving through this ad, never a person-specific ID.
  // Stripe includes this in the completed Checkout Session for reconciliation.
  target.searchParams.set('client_reference_id',`presstalk_g_v1_${creative}`);
  return target.href;
}
