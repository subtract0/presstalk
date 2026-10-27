/* A public campaign label follows navigation; nothing is stored or sent in the background. */
(() => {
  'use strict';
  const current = new URL(window.location.href);
  const fixed = {utm_source: '4chan', utm_medium: 'display', utm_campaign: 'presstalk_g_v1'};
  const creatives = new Set(['prompt_desktop', 'privacy_desktop', 'prompt_mobile', 'privacy_mobile']);
  const parameters = current.searchParams;
  for (const [name, value] of Object.entries(fixed)) {
    if (parameters.getAll(name).length !== 1 || parameters.get(name) !== value) return;
  }
  if (parameters.getAll('utm_content').length !== 1 || !creatives.has(parameters.get('utm_content'))) return;
  const campaign = {...fixed, utm_content: parameters.get('utm_content')};
  const pages = new Set(['/', '/index.html', '/voice-to-text.html', '/download.html', '/buy.html',
    '/evidence.html', '/de/', '/de/index.html', '/de/download.html', '/de/buy.html']);
  for (const anchor of document.querySelectorAll('a[href]')) {
    const raw = anchor.getAttribute('href');
    if (!raw || raw.startsWith('#')) continue;
    let target;
    try { target = new URL(raw, current); } catch { continue; }
    const localPage = target.origin === current.origin && pages.has(target.pathname);
    const checkout = target.origin === 'https://presstalk-licenses.presstalk.workers.dev' && target.pathname === '/buy';
    if (!localPage && !checkout) continue;
    for (const [name, value] of Object.entries(campaign)) target.searchParams.set(name, value);
    anchor.href = target.href;
  }
})();
