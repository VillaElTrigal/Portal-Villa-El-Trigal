(()=>{
'use strict';

const cfg=window.PORTAL_CONFIG||{};
if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey)return;

const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const getToken=()=>sessionStorage.getItem('sigve_portal_token')||'';
const date=v=>{if(!v)return '';const [y,m,d]=String(v).slice(0,10).split('-');return `${d}-${m}-${y}`};

async function rpc(name,args){
  const {data,error}=await sb.rpc(name,args);
  if(error)throw new Error(error.message);
  return data;
}

async function loadAvisos(){
  const token=getToken();
  const bell=$('#socio-notification-bell');
  if(!token||!bell)return;

  try{
    const items=await rpc('portal_socio_mis_avisos',{p_token:token})||[];
    const unread=items.filter(x=>!x.leido);
    const count=$('#socio-notification-count');
    const list=$('#socio-notification-list');
    const summary=$('#socio-notification-summary');

    bell.hidden=false;
    count.textContent=unread.length;
    count.hidden=!unread.length;
    summary.textContent=unread.length
      ?`${unread.length} aviso${unread.length===1?'':'s'} nuevo${unread.length===1?'':'s'}`
      :'Todo al día';

    list.innerHTML=unread.length
      ? unread.map(x=>`<article class="socio-notification-card" data-aviso="${x.id}">
          <strong>${x.tipo==='reunion'?'📅':x.tipo==='importante'?'⚠️':'ℹ️'} ${esc(x.titulo)}</strong>
          <p>${esc(x.mensaje)}</p>
          ${x.fecha_evento?`<small>📅 ${date(x.fecha_evento)}${x.hora_evento?' · 🕒 '+String(x.hora_evento).slice(0,5):''}${x.lugar?' · 📍 '+esc(x.lugar):''}</small>`:''}
        </article>`).join('')
      :'<div class="notice">✅ No tienes avisos nuevos.</div>';

  }catch(e){
    console.warn('Avisos socios:',e.message);
    bell.hidden=false;
  }
}

async function markVisibleAsRead(){
  const token=getToken();
  if(!token)return;
  const nodes=[...document.querySelectorAll('#socio-notification-list [data-aviso]')];

  for(const n of nodes){
    try{
      await rpc('portal_socio_marcar_aviso_leido',{
        p_token:token,
        p_aviso_id:n.dataset.aviso
      });
    }catch(e){
      console.warn('No fue posible marcar aviso como leído:',e.message);
    }
  }
}

async function openPanel(){
  const panel=$('#socio-notification-panel');
  if(!panel)return;
  panel.hidden=false;

  // Primero mostramos los avisos al socio.
  // Solo se marcan como leídos después de abrir la campanilla.
  await markVisibleAsRead();

  const count=$('#socio-notification-count');
  if(count){
    count.textContent='0';
    count.hidden=true;
  }
  const summary=$('#socio-notification-summary');
  if(summary)summary.textContent='Todo al día';
}

function bind(){
  $('#socio-notification-bell')?.addEventListener('click',openPanel);
  $('#socio-notification-close')?.addEventListener('click',()=>{
    $('#socio-notification-panel').hidden=true;
    loadAvisos();
  });
}

window.addEventListener('load',()=>{
  bind();
  setTimeout(loadAvisos,900);
});

})();
