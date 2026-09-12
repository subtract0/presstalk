import {GrantError} from './access-grants.js';
import * as pages from './grant-pages.js';
import {escapeHTML as e} from './mail.js';

const redirect=location=>new Response(null,{status:303,headers:{location,'cache-control':'no-store','referrer-policy':'same-origin'}});
const cookie=value=>`presstalk_operator=${value}; HttpOnly; Secure; SameSite=Strict; Path=/admin; Max-Age=${value?2592000:0}`;
async function form(request,origin) {
  if(request.method!=='POST')throw new GrantError('Use the button on this page.',405);
  if(request.headers.get('origin')!==origin)throw new GrantError('Open this page directly and try again.',403);
  if(!request.headers.get('content-type')?.startsWith('application/x-www-form-urlencoded'))throw new GrantError('Invalid form.',415);
  const reader=request.body?.getReader();const chunks=[];let size=0;
  if(reader)for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>4096){await reader.cancel();throw new GrantError('Form too large.',413);}chunks.push(Buffer.from(value));}
  return Object.fromEntries(new URLSearchParams(Buffer.concat(chunks).toString('utf8')));
}
export async function grantHandler(request,grants,config) {
  const url=new URL(request.url),path=url.pathname;
  if(path!=='/admin'&&!path.startsWith('/admin/')&&!path.startsWith('/gift/'))return null;
  try {
    if(path==='/admin/link'&&request.method==='POST') {
      if(!grants.masterAuthorized(request.headers.get('authorization')))throw new GrantError('Unauthorized.',401);
      return new Response(JSON.stringify({url:await grants.loginLink()}),{headers:{'content-type':'application/json','cache-control':'no-store'}});
    }
    if(path==='/admin/enter'&&request.method==='GET')return pages.loginPage();
    if(path==='/admin/login') {
      const fields=await form(request,config.origin),session=await grants.login(fields.code);
      const response=redirect('/admin');response.headers.set('set-cookie',cookie(session));return response;
    }
    if(path==='/admin'||path.startsWith('/admin/')) {
      if(!await grants.authorized(request))return pages.signedOut();
      if(path==='/admin'&&request.method==='GET') {
        const page=Math.max(0,Number.parseInt(url.searchParams.get('page')||'0',10)||0),search=(url.searchParams.get('q')||'').slice(0,254);
        return pages.manager({...await grants.list(page,search),page,search,selected:await grants.get(url.searchParams.get('created')||''),origin:config.origin,now:grants.now()});
      }
      const fields=await form(request,config.origin);
      if(path==='/admin/logout') {await grants.logout(request);const response=redirect('/admin');response.headers.set('set-cookie',cookie(''));return response;}
      let grant;
      if(path==='/admin/create')grant=await grants.create(fields);
      else if(path==='/admin/change')grant=await grants.change({...fields,revision:Number(fields.revision)});
      else throw new GrantError('Page not found.',404);
      return redirect('/admin?created='+encodeURIComponent(grant.id));
    }
    const match=path.match(/^\/gift\/([A-Za-z0-9_-]{43})(?:\/(claim|license))?$/);
    if(!match)throw new GrantError('This invitation is unavailable.',404);
    const [,token,action]=match;
    if(action==='claim') {await form(request,config.origin);await grants.claim(token);return redirect(`/gift/${token}`);}
    if(request.method!=='GET')throw new GrantError('Use the button on this page.',405);
    const grant=await grants.fromToken(token);
    if(!grant)throw new GrantError('This invitation is unavailable. Ask the person who shared it with you.',404);
    if(action==='license') {
      if(!grant.license)throw new GrantError('Claim your invitation first.',409);
      if(grant.expires_at!==null&&grant.expires_at<=grants.now())throw new GrantError('This extension has expired. Ask the person who shared it for more time.',410);
      return new Response(grant.license+'\n',{headers:{'content-type':'application/octet-stream','content-disposition':'attachment; filename="PressTalk.presstalk-license"','cache-control':'no-store, private','referrer-policy':'no-referrer','x-content-type-options':'nosniff'}});
    }
    return pages.gift(grant,grants.now());
  } catch(error) {
    const known=error instanceof GrantError;
    if(!known)console.error('access_grant_request_failed',error?.constructor?.name||'UnknownError');
    return pages.documentResponse('Please try again',`<h1>${known?'We could not complete that.':'Please try again shortly.'}</h1><p>${e(known?error.message:'The access service is temporarily unavailable. Your existing offline licence still works.')}</p>${path.startsWith('/admin')?'<p><a href="/admin">Return to your manager</a></p>':''}`,{status:known?error.status:503});
  }
}
