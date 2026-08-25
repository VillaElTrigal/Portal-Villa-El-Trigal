(()=>{
'use strict';

const cfg=window.PORTAL_CONFIG||{};
if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey)return;
const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);

const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const token=()=>sessionStorage.getItem('sigve_portal_token')||'';
const dcl=v=>{if(!v)return '';const [y,m,d]=String(v).slice(0,10).split('-');return `${d}-${m}-${y}`};

async function rpc(name,args){
  const {data,error}=await sb.rpc(name,args);
  if(error)throw new Error(error.message);
  return data;
}

let currentUnread=[];

async function loadAvisos(){
  const bell=$('#socio-notification-bell');
  if(!bell||!token())return;

  try{
    const items=await rpc('portal_socio_mis_avisos',{p_token:token()})||[];
    currentUnread=items.filter(x=>!x.leido);

    bell.hidden=false;

    const count=$('#socio-notification-count');
    if(count){
      count.textContent=currentUnread.length;
      count.hidden=!currentUnread.length;
    }

    const summary=$('#socio-notification-summary');
    if(summary){
      summary.textContent=currentUnread.length
        ?`${currentUnread.length} aviso${currentUnread.length===1?'':'s'} nuevo${currentUnread.length===1?'':'s'}`
        :'Todo al día';
    }
  }catch(e){
    console.warn('Avisos socios:',e.message);
    bell.hidden=false;
  }
}

function renderPanel(){
  const list=$('#socio-notification-list');
  if(!list)return;

  list.innerHTML=currentUnread.length
    ?currentUnread.map(x=>`
      <article class="socio-notification-card" data-aviso="${x.id}">
        <strong>${x.tipo==='reunion'?'📅':x.tipo==='importante'?'⚠️':'ℹ️'} ${esc(x.titulo)}</strong>
        <p>${esc(x.mensaje)}</p>
        ${x.fecha_evento?`<small>📅 ${dcl(x.fecha_evento)}${x.hora_evento?' · 🕒 '+String(x.hora_evento).slice(0,5):''}${x.lugar?' · 📍 '+esc(x.lugar):''}</small>`:''}
      </article>
    `).join('')
    :'<div class="notice">✅ No tienes avisos nuevos.</div>';
}

async function openPanel(){
  const panel=$('#socio-notification-panel');
  if(!panel)return;

  renderPanel();
  panel.hidden=false;

  // Se muestran primero; luego quedan marcados como leídos.
  const toMark=[...currentUnread];
  for(const x of toMark){
    try{
      await rpc('portal_socio_marcar_aviso_leido',{
        p_token:token(),
        p_aviso_id:x.id
      });
    }catch(e){
      console.warn('Lectura aviso:',e.message);
    }
  }

  const count=$('#socio-notification-count');
  if(count){count.textContent='0';count.hidden=true}
  const summary=$('#socio-notification-summary');
  if(summary)summary.textContent='Todo al día';
}

function bind(){
  $('#socio-notification-bell')?.addEventListener('click',openPanel);
  $('#socio-notification-close')?.addEventListener('click',async()=>{
    $('#socio-notification-panel').hidden=true;
    await loadAvisos();
  });
}

window.addEventListener('load',()=>{
  bind();
  setTimeout(loadAvisos,1000);
});

})();