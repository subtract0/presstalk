import {randomBytes,createHash,timingSafeEqual} from 'node:crypto';
import {issueAccessLicense} from './license.js';

const day=86400000;
const token=()=>randomBytes(32).toString('base64url');
const hash=value=>createHash('sha256').update(value).digest('hex');
const validToken=value=>typeof value==='string' && /^[A-Za-z0-9_-]{43}$/.test(value);
export class GrantError extends Error {
  constructor(message,status=400){super(message);this.status=status;}
}
export class AccessGrants {
  constructor({db,key,config,now=()=>Date.now()}) {Object.assign(this,{db,key,config,now});}
  masterAuthorized(header) {
    const secret=this.config.adminToken;
    if(typeof secret!=='string'||secret.length<43)return false;
    const a=Buffer.from(header||''),b=Buffer.from(`Bearer ${secret}`);
    return a.length===b.length && timingSafeEqual(a,b);
  }
  async loginLink() {
    const code=token(),now=this.now();
    await this.db.batch([
      this.db.prepare('DELETE FROM operator_logins WHERE expires_at<=?').bind(now),
      this.db.prepare('DELETE FROM operator_sessions WHERE expires_at<=?').bind(now),
      this.db.prepare('INSERT INTO operator_logins(token_hash,expires_at) VALUES (?,?)').bind(hash(code),now+60000),
    ]);
    return `${this.config.origin}/admin/enter#${code}`;
  }
  async login(code) {
    if(!validToken(code))throw new GrantError('This sign-in link is invalid or expired.',401);
    const now=this.now(),used=await this.db.prepare('DELETE FROM operator_logins WHERE token_hash=? AND expires_at>? RETURNING token_hash').bind(hash(code),now).first();
    if(!used)throw new GrantError('This sign-in link is invalid or expired. Open Manage PressTalk again.',401);
    const session=token();
    await this.db.prepare('INSERT INTO operator_sessions(token_hash,expires_at) VALUES (?,?)').bind(hash(session),now+30*day).run();
    return session;
  }
  sessionCookie(request) {
    const found=(request.headers.get('cookie')||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('presstalk_operator='));
    return found?.slice('presstalk_operator='.length)||'';
  }
  async authorized(request) {
    const value=this.sessionCookie(request);
    if(!validToken(value))return false;
    return Boolean(await this.db.prepare('SELECT token_hash FROM operator_sessions WHERE token_hash=? AND expires_at>?').bind(hash(value),this.now()).first());
  }
  async logout(request) {
    const value=this.sessionCookie(request);
    if(validToken(value))await this.db.prepare('DELETE FROM operator_sessions WHERE token_hash=?').bind(hash(value)).run();
  }
  async list(page=0,search='') {
    const offset=Math.max(0,Math.min(100000,Number.isSafeInteger(page)?page:0))*50;
    const {results}=await this.db.prepare('SELECT * FROM access_grants WHERE label LIKE ? ORDER BY created_at DESC,id LIMIT 51 OFFSET ?').bind('%'+search.slice(0,254)+'%',offset).all();
    return {grants:results.slice(0,50),more:results.length>50};
  }
  async get(id) {return this.db.prepare('SELECT * FROM access_grants WHERE id=?').bind(id).first();}
  async fromToken(value) {
    if(!validToken(value))return null;
    return this.db.prepare('SELECT * FROM access_grants WHERE token=? AND revoked=0').bind(value).first();
  }
  validateID(value) {
    if(typeof value!=='string'||!/^[-a-zA-Z0-9_]{20,64}$/.test(value))throw new GrantError('Please reload and try again.');
  }
  async create({id,label,choice}) {
    this.validateID(id);
    label=String(label||'').trim();
    if(!label||label.length>254)throw new GrantError('Enter a name or email, up to 254 characters.');
    if(!['7','30','gift'].includes(choice))throw new GrantError('Choose 7 days, 30 days or a free licence.');
    const kind=choice==='gift'?'gift':'extension',days=kind==='gift'?0:Number(choice);
    await this.db.prepare('INSERT INTO access_grants(id,token,label,kind,days,created_at,last_action) VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING').bind(id,token(),label,kind,days,this.now(),id).run();
    const grant=await this.get(id);
    if(grant.label!==label||grant.kind!==kind||grant.days!==days)throw new GrantError('This request was already used. Reload before making another grant.',409);
    return grant;
  }
  async change({id,revision,action,operation}) {
    this.validateID(id);this.validateID(operation);
    if(!['7','30','gift','disable'].includes(action))throw new GrantError('Unknown action.');
    const grant=await this.get(id);
    if(!grant)throw new GrantError('Grant not found.',404);
    if(grant.last_action===operation)return grant;
    if(grant.revision!==revision)throw new GrantError('This grant changed. Reload to see its current status.',409);
    if(grant.revoked)throw new GrantError('This link is disabled. Create a new grant if needed.',409);
    const changed={...grant},now=this.now();
    if(action==='disable')changed.revoked=1;
    else if(action==='gift') {changed.kind='gift';changed.days=0;changed.expires_at=null;}
    else {
      if(grant.kind==='gift')throw new GrantError('This person already has a permanent free licence.',409);
      changed.days+=Number(action);
      if(changed.days>3650)throw new GrantError('Use a permanent licence instead of extending beyond ten years.');
      if(grant.claimed_at!==null)changed.expires_at=Math.max(now,grant.expires_at)+Number(action)*day;
    }
    if(grant.claimed_at!==null && !changed.revoked)changed.license=issueAccessLicense({grant:changed,key:this.key,keyID:this.config.keyID,now});
    const saved=await this.db.prepare('UPDATE access_grants SET kind=?,days=?,expires_at=?,license=?,revoked=?,revision=revision+1,last_action=? WHERE id=? AND revision=? RETURNING *').bind(changed.kind,changed.days,changed.expires_at,changed.license,changed.revoked,operation,id,revision).first();
    if(!saved)throw new GrantError('This grant changed. Reload to see its current status.',409);
    return saved;
  }
  async claim(value) {
    for(let attempt=0;attempt<3;attempt++) {
      const grant=await this.fromToken(value);
      if(!grant)throw new GrantError('This link is unavailable. Ask the person who shared it with you.',404);
      if(grant.claimed_at!==null)return grant;
      const now=this.now();
      grant.claimed_at=now;grant.expires_at=grant.kind==='extension'?now+grant.days*day:null;
      grant.license=issueAccessLicense({grant,key:this.key,keyID:this.config.keyID,now});
      const saved=await this.db.prepare('UPDATE access_grants SET claimed_at=?,expires_at=?,license=?,revision=revision+1 WHERE id=? AND revision=? AND revoked=0 AND claimed_at IS NULL RETURNING *').bind(now,grant.expires_at,grant.license,grant.id,grant.revision).first();
      if(saved)return saved;
    }
    throw new GrantError('This grant changed while opening it. Please try again.',409);
  }
}
