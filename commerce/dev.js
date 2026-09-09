import http from 'node:http';
import app from './api/index.js';
http.createServer(async(req,res)=>{
  const request=new Request(`http://localhost:4242${req.url}`,{method:req.method,headers:req.headers,
    ...(req.method!=='GET'&&req.method!=='HEAD'?{body:req,duplex:'half'}:{})});
  const response=await app.fetch(request);
  res.writeHead(response.status,Object.fromEntries(response.headers));
  res.end(Buffer.from(await response.arrayBuffer()));
}).listen(4242,'127.0.0.1',()=>console.log('PressTalk commerce at http://localhost:4242'));
