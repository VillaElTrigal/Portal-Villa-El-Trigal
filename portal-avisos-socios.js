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

function ensureModal(){
  if(document.getElementById('sigve-aviso-modal'))return;

  const style=document.createElement('style');
  style.textContent=`
    #sigve-aviso-modal[hidden]{display:none!important}
    #sigve-aviso-modal{
      position:fixed;inset:0;z-index:99999;
      background:rgba(10,35,43,.48);
      display:grid;place-items:center;
      padding:18px;
    }
    .sigve-aviso-dialog{
      width:min(520px,100%);
      max-height:82vh;
      overflow:auto;
      background:#fff;
      border-radius:18px;
      box-shadow:0 20px 60px rgba(0,0,0,.28);
    }
    .sigve-aviso-head{
      display:flex;justify-content:space-between;align-items:flex-start;gap:12px;
      padding:18px 20px 14px;
      border-bottom:1px solid #e4ebea;
    }
    .sigve-aviso-head div{display:flex;flex-direction:column;gap:3px}
    .sigve-aviso-head strong{font-size:1.1rem;color:#173b46}
    .sigve-aviso-head small{color:#6b7f83}
    .sigve-aviso-close{
      border:0;background:#eef4f4;color:#173b46;
      width:36px;height:36px;border-radius:50%;
      font-size:1.35rem;cursor:pointer;
    }
    .sigve-aviso-body{padding:16px 20px 20px}
    .sigve-aviso-card{
      border:1px solid #dfe8e7;
      border-left:4px solid #18758a;
      border-radius:12px;
      padding:14px 15px;
      margin-bottom:12px;
      background:#fbfdfd;
    }
    .sigve-aviso-card strong{display:block;color:#173b46;font-size:1rem;margin-bottom:7px}
    .sigve-aviso-card p{margin:0 0 10px;white-space:pre-wrap;line-height:1.5;color:#344e55}
    .sigve-aviso-card small{color:#5e7479;line-height:1.45}
    .sigve-aviso-empty{
      min-height:170px;display:flex;flex-direction:column;
      align-items:center;justify-content:center;text-align:center;gap:7px;color:#61767a
    }
    .sigve-aviso-empty span{font-size:2rem}
    .sigve-aviso-empty strong{color:#173b46;font-size:1.05rem}
  `;
  document.head.appendChild(style);

  const modal=document.createElement('div');
  modal.id='sigve-aviso-modal';
  modal.hidden=true;
  modal.innerHTML=`
    <div class="sigve-aviso-dialog" role="dialog" aria-modal="true" aria-labelledby="sigve-aviso-title">
      <div class="sigve-aviso-head">
        <div>
          <strong id="sigve-aviso-title">🔔 Avisos de la Junta</strong>
          <small id="sigve-aviso-summary">Todo al día</small>
        </div>
        <button class="sigve-aviso-close" type="button" aria-label="Cerrar">×</button>
      </div>
      <div id="sigve-aviso-body" class="sigve-aviso-body"></div>
    </div>`;

  document.body.appendChild(modal);

  modal.querySelector('.sigve-aviso-close').onclick=()=>modal.hidden=true;
  modal.addEventListener('click',e=>{if(e.target===modal)modal.hidden=true});
}

function renderBadge(){
  const bell=$('#socio-notification-bell');
  const count=$('#socio-notification-count');
  if(!bell)return;

  if(!token()){
    bell.hidden=true;
    if(count){count.hidden=true;count.textContent=''}
    return;
  }

  bell.hidden=false;

  if(count){
    if(currentUnread.length){
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
    renderBadge();
    return;
  }

  try{
    const items=await rpc('portal_socio_mis_avisos',{p_token:token()})||[];
    currentUnread=items.filter(x=>!x.leido);
    renderBadge();
  }catch(e){
    console.warn('Avisos socios:',e.message);
    currentUnread=[];
    renderBadge();
  }
}

function renderModal(){
  ensureModal();
  const modal=$('#sigve-aviso-modal');
  const body=$('#sigve-aviso-body');
  const summary=$('#sigve-aviso-summary');

  modal.hidden=false;

  if(!currentUnread.length){
    summary.textContent='Todo al día';
    body.innerHTML=`
      <div class="sigve-aviso-empty">
        <span>✅</span>
        <strong>Todo al día</strong>
        <small>No tienes avisos nuevos.</small>
      </div>`;
    return;
  }

  summary.textContent=`${currentUnread.length} aviso${currentUnread.length===1?'':'s'} nuevo${currentUnread.length===1?'':'s'}`;

  body.innerHTML=currentUnread.map(x=>`
    <article class="sigve-aviso-card">
      <strong>${x.tipo==='reunion'?'📅':x.tipo==='importante'?'⚠️':'ℹ️'} ${esc(x.titulo)}</strong>
      <p>${esc(x.mensaje)}</p>
      ${x.fecha_evento?`
        <small>
          📅 ${dcl(x.fecha_evento)}
          ${x.hora_evento?' · 🕒 '+String(x.hora_evento).slice(0,5):''}
          ${x.lugar?' · 📍 '+esc(x.lugar):''}
        </small>`:''}
    </article>`).join('');
}

async function openAvisos(){
  if(!token())return;

  // Primero mostrar el mensaje.
  renderModal();

  // Luego marcar como leído.
  if(currentUnread.length){
    const vistos=[...currentUnread];
    for(const x of vistos){
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
  }
}

function bind(){
  ensureModal();

  const bell=$('#socio-notification-bell');
  if(bell){
    bell.onclick=e=>{
      e.preventDefault();
      e.stopPropagation();
      openAvisos();
    };
  }

  let lastToken='';
  setInterval(()=>{
    const t=token();
    if(t!==lastToken){
      lastToken=t;
      if(t)loadAvisos();
      else renderBadge();
    }
  },800);
}

window.addEventListener('load',()=>{
  bind();
  setTimeout(loadAvisos,900);
});

})();