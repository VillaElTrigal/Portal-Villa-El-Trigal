const CACHE='sigve-pwa-v1';
const CORE=[
  './',
  './index.html',
  './portal-socio.html',
  './styles.css',
  './portal-socio.css',
  './portal-v7.css',
  './portal-config.js',
  './portal-v7.js',
  './portal-socio.js',
  './portal-popup.js',
  './popup.css',
  './assets/logo.svg',
  './assets/pwa-icon-192.png',
  './assets/pwa-icon-512.png'
];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE).catch(()=>{})));
  self.skipWaiting();
});

self.addEventListener('activate',event=>{
  event.waitUntil(
    caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET')return;
  const url=new URL(req.url);

  // Supabase/API: siempre red, nunca cachear datos dinámicos.
  if(url.hostname.includes('supabase') || url.pathname.includes('/rest/v1/') || url.pathname.includes('/auth/v1/')){
    event.respondWith(fetch(req));
    return;
  }

  // HTML/JS/CSS: network-first para evitar versiones antiguas.
  if(req.mode==='navigate' || /\.(?:js|css|html)$/.test(url.pathname)){
    event.respondWith(
      fetch(req).then(res=>{
        const copy=res.clone();
        caches.open(CACHE).then(cache=>cache.put(req,copy));
        return res;
      }).catch(()=>caches.match(req).then(r=>r||caches.match('./index.html')))
    );
    return;
  }

  // Imágenes/recursos: cache-first.
  event.respondWith(
    caches.match(req).then(cached=>cached||fetch(req).then(res=>{
      const copy=res.clone();
      caches.open(CACHE).then(cache=>cache.put(req,copy));
      return res;
    }))
  );
});
