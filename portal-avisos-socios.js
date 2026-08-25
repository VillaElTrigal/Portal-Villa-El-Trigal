(()=>{'use strict';
const $=s=>document.querySelector(s),esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const getToken=()=>{try{return sessionStorage.getItem('portal_socio_token')||localStorage.getItem('portal_socio_token')||window.portalSocioToken||window.token||''}catch{return window.token||''}};
const client=()=>window.supabaseClient||window.sb;
const date=v=>{if(!v)return '';const [y,m,d]=String(v).slice(0,10).split('-');return `${d}-${m}-${y}`};
async function rpc(name,args){const c=client();if(!c)return null;const {data,error}=await c.rpc(name,args);if(error)throw error;return data}
async function load(){
 const token=getToken();if(!token)return;
 try{
  const items=await rpc('portal_socio_mis_avisos',{p_token:token})||[],unread=items.filter(x=>!x.leido);
  const bell=$('#socio-notification-bell'),count=$('#socio-notification-count'),list=$('#socio-notification-list'),summary=$('#socio-notification-summary');
  if(!bell||!list)return;bell.hidden=false;count.textContent=unread.length;count.hidden=!unread.length;summary.textContent=unread.length?`${unread.length} aviso${unread.length===1?'':'s'} nuevo${unread.length===1?'':'s'}`:'Todo al día';
  list.innerHTML=unread.map(x=>`<article class="socio-notification-card" data-aviso="${x.id}"><strong>${x.tipo==='reunion'?'📅':x.tipo==='importante'?'⚠️':'ℹ️'} ${esc(x.titulo)}</strong><p>${esc(x.mensaje)}</p>${x.fecha_evento?`<small>📅 ${date(x.fecha_evento)}${x.hora_evento?' · 🕒 '+String(x.hora_evento).slice(0,5):''}${x.lugar?' · 📍 '+esc(x.lugar):''}</small>`:''}</article>`).join('')||'<div class="notice">✅ No tienes avisos nuevos.</div>';
 }catch(e){console.warn('Avisos socios:',e.message)}
}
async function markAll(){
 const token=getToken();if(!token)return;
 const nodes=[...document.querySelectorAll('[data-aviso]')];
 await Promise.all(nodes.map(n=>rpc('portal_socio_marcar_aviso_leido',{p_token:token,p_aviso_id:n.dataset.aviso}).catch(()=>null)));
 await load();
}
window.addEventListener('load',()=>setTimeout(load,1200));
document.addEventListener('click',async e=>{
 if(e.target.closest('#socio-notification-bell')){const p=$('#socio-notification-panel');p.hidden=false;await markAll();return}
 if(e.target.closest('#socio-notification-close')){$('#socio-notification-panel').hidden=true}
});
})();