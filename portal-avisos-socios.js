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

function hideBell(){
  const bell=$('#socio-notification-bell');
  const count=$('#socio-notification-count');
  if(bell)bell.hidden=true;
  if(count){count.hidden=true;count.textContent=''}
}

function renderBadge(){
  const bell=$('#socio-notification-bell');
  const count=$('#socio-notification-count');
  if(!bell)return;

  // Solo visible después de iniciar sesión.
  if(!token()){
    hideBell();
    return;
  }

  bell.hidden=false;

  if(count){
    if(currentUnread.length>0){
      count.textContent=String(currentUnread.length);
      count.hidden=false;
    }else{
      count.textContent='';
      count.hidden=true;
    }
  }
}

async function loadAvisos(){
  if(!token()){
    currentUnread=[];
    hideBell();
    return;
  }

  try{
    const items=await rpc('portal_socio_mis_avisos',{p_token:token()})||[];
    currentUnread=items.filter(x=>!x.leido);
    renderBadge();

    const summary=$('#socio-notification-summary');
    if(summary){
      summary.textContent=currentUnread.length
        ?`${currentUnread.length} aviso${currentUnread.length===1?'':'s'} nuevo${currentUnread.length===1?'':'s'}`
        :'Todo al día';
    }
  }catch(e){
    console.warn('Avisos socios:',e.message);
    currentUnread=[];
    renderBadge();
  }
}

function renderPanel(){
  const list=$('#socio-notification-list');
  if(!list)return;

  if(!currentUnread.length){
    list.innerHTML='<div class="notice">✅ No tienes avisos nuevos.</div>';
    return;
  }

  list.innerHTML=currentUnread.map(x=>`
    <article class="socio-notification-card" data-aviso="${x.id}">
      <strong>${x.tipo==='reunion'?'📅':x.tipo==='importante'?'⚠️':'ℹ️'} ${esc(x.titulo)}</strong>
      <p>${esc(x.mensaje)}</p>
      ${x.fecha_evento?`<small>📅 ${dcl(x.fecha_evento)}${x.hora_evento?' · 🕒 '+String(x.hora_evento).slice(0,5):''}${x.lugar?' · 📍 '+esc(x.lugar):''}</small>`:''}
    </article>
  `).join('');
}

async function openPanel(){
  if(!token())return;

  const panel=$('#socio-notification-panel');
  if(!panel)return;

  renderPanel();
  panel.hidden=false;

  // Marcar como leídos DESPUÉS de haberlos mostrado.
  if(currentUnread.length){
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
    currentUnread=[];
    renderBadge();
    const summary=$('#socio-notification-summary');
    if(summary)summary.textContent='Todo al día';
  }
}

function bind(){
  $('#socio-notification-bell')?.addEventListener('click',openPanel);
  $('#socio-notification-close')?.addEventListener('click',()=>{
    $('#socio-notification-panel').hidden=true;
  });

  // Cuando portal-socio inicia/cierra sesión, el storage cambia en esta misma pestaña
  // solo por código, por eso observamos el DOM y reintentamos periódicamente de forma liviana.
  let lastToken='';
  setInterval(()=>{
    const t=token();
    if(t!==lastToken){
      lastToken=t;
      if(t)loadAvisos();
      else hideBell();
    }
  },800);
}

window.addEventListener('load',()=>{
  hideBell();
  bind();
  setTimeout(loadAvisos,1000);
});

})();