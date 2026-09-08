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
      retry:"datetime('now','+60 seconds')",hourAgo:"datetime('now','-1 hour')"});
  }
}
