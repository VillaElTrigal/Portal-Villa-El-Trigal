(()=>{
'use strict';

const cfg=window.PORTAL_CONFIG||{};
if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey)return;
const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);

const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const dcl=v=>{if(!v)return '—';const [y,m,d]=String(v).slice(0,10).split('-');return `${d}-${m}-${y}`};
const tm=v=>v?String(v).slice(0,5):'—';
const dt=v=>v?new Date(v).toLocaleString('es-CL'):'—';

async function rpc(name,args){
  const {data,error}=await sb.rpc(name,args);
  if(error)throw new Error(error.message);
  return data;
}

async function loadAvisos(){
  const box=$('#avisos-socios-list');
  if(!box)return;

  box.innerHTML='<div class="notice">Cargando historial de avisos…</div>';

  const {data,error}=await sb
    .from('avisos_socios')
    .select('id,titulo,mensaje,tipo,fecha_evento,hora_evento,lugar,fecha_publicacion,fecha_expiracion,activo,destinatarios_total,creado_en')
    .order('creado_en',{ascending:false})
    .limit(100);

  if(error){
    box.innerHTML=`<div class="notice">${esc(error.message)}</div>`;
    return;
  }

  box.innerHTML=(data||[]).map(a=>`
    <article class="list-card">
      <div>
        <strong>${a.tipo==='reunion'?'📅':a.tipo==='importante'?'⚠️':'ℹ️'} ${esc(a.titulo)}</strong>
        <p>${esc(a.mensaje)}</p>
        <small>
          Publicado: ${dt(a.fecha_publicacion)}
          ${a.fecha_evento?` · Evento: ${dcl(a.fecha_evento)} ${tm(a.hora_evento)}`:''}
          ${a.lugar?` · ${esc(a.lugar)}`:''}
        </small>
        <div class="item-meta">
          👥 ${Number(a.destinatarios_total||0)} socio(s) activo(s) considerados ·
          ${a.activo?'🟢 Activo':'⚪ Desactivado'}
          ${a.fecha_expiracion?` · Visible hasta ${dcl(a.fecha_expiracion)}`:''}
        </div>
      </div>
      <div class="actions">
        <button class="button secondary" data-toggle-aviso="${a.id}" data-active="${a.activo}">
          ${a.activo?'Desactivar':'Activar'}
        </button>
      </div>
    </article>
  `).join('')||'<div class="notice">Aún no hay avisos publicados.</div>';

  box.querySelectorAll('[data-toggle-aviso]').forEach(b=>{
    b.onclick=async()=>{
      try{
        await rpc('admin_cambiar_estado_aviso_socios',{
          p_aviso_id:b.dataset.toggleAviso,
          p_activo:b.dataset.active!=='true'
        });
        await loadAvisos();
      }catch(e){
        alert(e.message);
      }
    };
  });
}

function bind(){
  const form=$('#avisos-socios-form');
  if(!form)return;

  form.onsubmit=async e=>{
    e.preventDefault();

    const btn=form.querySelector('[type="submit"]');
    const msg=$('#avisos-socios-msg');
    const original=btn.textContent;

    btn.disabled=true;
    btn.textContent='Publicando…';
    msg.textContent='';

    try{
      const id=await rpc('admin_publicar_aviso_socios',{
        p_tipo:form.tipo.value,
        p_titulo:form.titulo.value.trim(),
        p_mensaje:form.mensaje.value.trim(),
        p_fecha_evento:form.fecha_evento.value||null,
        p_hora_evento:form.hora_evento.value||null,
        p_lugar:form.lugar.value.trim()||null,
        p_fecha_expiracion:form.fecha_expiracion.value||null,
        p_activo:form.activo.checked
      });

      msg.textContent=`Aviso publicado y guardado correctamente. Registro: ${String(id).slice(0,8)}…`;
      msg.className='form-message success';

      form.reset();
      form.activo.checked=true;
      form.lugar.value='Sede Social Villa El Trigal';

      await loadAvisos();

    }catch(e){
      msg.textContent='No se pudo publicar: '+e.message;
      msg.className='form-message error';
    }finally{
      btn.disabled=false;
      btn.textContent=original;
    }
  };

  $('#avisos-socios-clear')?.addEventListener('click',()=>{
    form.reset();
    form.activo.checked=true;
    form.lugar.value='Sede Social Villa El Trigal';
  });

  $('#avisos-socios-refresh')?.addEventListener('click',loadAvisos);

  document.addEventListener('click',e=>{
    if(e.target.closest('[data-section="avisos-socios"]')){
      setTimeout(loadAvisos,80);
    }
  });
}

window.addEventListener('load',()=>{
  setTimeout(()=>{
    bind();
    loadAvisos();
  },650);
});

})();