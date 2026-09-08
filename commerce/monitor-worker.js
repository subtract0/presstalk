import { WorkerEntrypoint } from 'cloudflare:workers';
import { sanitizeObservation } from './lib/observability.js';

// This private service receives already-sanitized metrics, not incoming payment
// requests. Its logs and traces cannot inherit receipt URLs from an HTTP handler.
export default class extends WorkerEntrypoint {
  async fetch() { return new Response('Not found',{status:404}); }
  async record(value) {
    const observation=sanitizeObservation(value);
    if(observation) console.log(JSON.stringify(observation));
  }
}
