(()=>{'use strict';
const $=s=>document.querySelector(s), esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const sb=window.supabaseClient||window.sb;
function client(){return window.supabaseClient||window.sb||window.supabase?.createClient?.(window.SUPABASE_URL,window.SUPABASE_ANON_KEY)}
function dcl(v){if(!v)return '—';const [y,m,d]=String(v).slice(0,10).split('-');return `${d}-${m}-${y}`}
function tm(v){return v?String(v).slice(0,5):'—'}
async function load(){
 const c=client(); if(!c)return;
 const {data,error}=await c.from('avisos_socios').select('*').order('creado_en',{ascending:false}).limit(50);
 const box=$('#avisos-socios-list'); if(!box)return;
 if(error){box.innerHTML=`<div class="notice">${esc(error.message)}</div>`;return}
 box.innerHTML=(data||[]).map(a=>`<article class="list-card"><div><strong>${a.tipo==='reunion'?'📅':a.tipo==='importante'?'⚠️':'ℹ️'} ${esc(a.titulo)}</strong><p>${esc(a.mensaje)}</p><small>${a.fecha_evento?`${dcl(a.fecha_evento)} · ${tm(a.hora_evento)} · `:''}${esc(a.lugar||'')} · ${a.activo?'Activo':'Desactivado'}</small></div><div class="actions"><button class="button secondary" data-toggle-aviso="${a.id}" data-active="${a.activo}">${a.activo?'Desactivar':'Activar'}</button></div></article>`).join('')||'<div class="notice">Aún no hay avisos masivos.</div>';
 box.querySelectorAll('[data-toggle-aviso]').forEach(b=>b.onclick=async()=>{const {error}=await c.from('avisos_socios').update({activo:b.dataset.active!=='true'}).eq('id',b.dataset.toggleAviso);if(error)return alert(error.message);load()});
}
function bind(){
 const form=$('#avisos-socios-form'); if(!form)return;
 form.onsubmit=async e=>{
  e.preventDefault(); const c=client(),f=e.currentTarget,btn=f.querySelector('[type=submit]');
  btn.disabled=true;btn.textContent='Publicando…';
  const payload={tipo:f.tipo.value,titulo:f.titulo.value.trim(),mensaje:f.mensaje.value.trim(),fecha_evento:f.fecha_evento.value||null,hora_evento:f.hora_evento.value||null,lugar:f.lugar.value.trim()||null,fecha_expiracion:f.fecha_expiracion.value||null,activo:f.activo.checked,solo_socios_activos:true};
  const {error}=await c.from('avisos_socios').insert(payload);
  btn.disabled=false;btn.textContent='📣 Publicar para socios activos';
  const m=$('#avisos-socios-msg');
  if(error){m.textContent=error.message;m.className='form-message error';return}
  m.textContent='Aviso publicado para los socios activos.';m.className='form-message success';f.reset();f.activo.checked=true;f.lugar.value='Sede Social Villa El Trigal';load();
 };
 $('#avisos-socios-clear').onclick=()=>{form.reset();form.activo.checked=true;form.lugar.value='Sede Social Villa El Trigal'};
 $('#avisos-socios-refresh').onclick=load;
 document.addEventListener('click',e=>{if(e.target.closest('[data-section="avisos-socios"]'))setTimeout(load,50)});
}
window.addEventListener('load',()=>setTimeout(bind,600));
})();