import pg from 'pg';
import { readFile } from 'node:fs/promises';
if(!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
const client=new pg.Client({connectionString:process.env.DATABASE_URL});
try {
  await client.connect();
  await client.query(await readFile(new URL('../schema.sql',import.meta.url),'utf8'));
  console.log('PressTalk order and delivery tables are ready.');
} finally {await client.end();}
