import { Store } from './store.js';

export function d1Adapter(binding) {
  return { async query(sql,values=[]) {
    // Store's queries use numbered parameters. D1's bind list is positional;
    // repeat the original value when a query references one parameter twice.
    const args=[];
    const statement=sql.replace(/\$(\d+)/g,(_,number)=>{
      const value=values[Number(number)-1];
      args.push(typeof value==='boolean'?Number(value):value);return '?';
    });
    const result=await binding.prepare(statement).bind(...args).all();
    return {rows:result.results};
  }};
}
export class D1Store extends Store {
  constructor(binding) {
    super(d1Adapter(binding),{now:"datetime('now')",lease:"datetime('now','+90 seconds')",
      retry:"datetime('now','+' || $4 || ' seconds')",hourAgo:"datetime('now','-1 hour')",dayAgo:"datetime('now','-1 day')"});
  }
  async health() {
    await super.health();
    const names=['deliveries_ready','deliveries_session','recovery_limits_window'];
    const {rows}=await this.db.query("SELECT name FROM sqlite_master WHERE type='index' AND name IN ($1,$2,$3)",names);
    if(rows.length!==names.length) throw new Error('Missing delivery capacity migration');
  }
}
