(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{},loading=document.getElementById('child-loading'),invalid=document.getElementById('child-invalid'),content=document.getElementById('child-content');
  const fail=d=>{loading.hidden=true;content.hidden=true;invalid.hidden=false;if(d)console.error(d)};
  if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey){fail('Falta configuración de Supabase');return}
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey),params=new URLSearchParams(location.search),token=params.get('token')||params.get('registro_ninos');
  const esc=v=>String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const dateCL=v=>v?new Date(v+'T12:00:00').toLocaleDateString('es-CL'):'—';
  if(!token){fail('El enlace no contiene token');return}
  const form=document.getElementById('child-form'),message=document.getElementById('child-message'),list=document.getElementById('child-list'),count=document.getElementById('saved-count'),save=document.getElementById('save-child'),cancel=document.getElementById('cancel-edit'),birth=form.elements.fecha_nacimiento;
  let editingId=null,rows=[];birth.max=new Date().toISOString().slice(0,10);
  function resetForm(){editingId=null;form.reset();birth.max=new Date().toISOString().slice(0,10);save.textContent='Guardar niño o niña';cancel.hidden=true}
  async function loadChildren(){
    const{data,error}=await sb.rpc('listar_ninos_por_token',{p_token:token});
    if(error){list.innerHTML='<p class="empty-list">No fue posible cargar los registros.</p>';console.error(error);return}
    rows=data||[];count.textContent=rows.length;
    list.innerHTML=rows.length?rows.map(r=>`<article class="child-record"><div><strong>${esc(r.nombre_completo)}</strong><small>Fecha de nacimiento: ${esc(dateCL(r.fecha_nacimiento))}</small></div><span class="child-sex">${r.sexo==='F'?'F - Niña':'M - Niño'}</span><div class="child-record-actions"><button type="button" class="button secondary" data-edit="${r.id}">Editar</button><button type="button" class="button danger" data-delete="${r.id}">Eliminar</button></div></article>`).join(''):'<p class="empty-list">Todavía no has agregado niños o niñas.</p>';
    list.querySelectorAll('[data-edit]').forEach(b=>b.addEventListener('click',()=>{const r=rows.find(x=>x.id===b.dataset.edit);if(!r)return;editingId=r.id;form.elements.nombre.value=r.nombre_completo;form.elements.fecha_nacimiento.value=r.fecha_nacimiento;form.elements.sexo.value=r.sexo;save.textContent='Guardar cambios';cancel.hidden=false;form.scrollIntoView({behavior:'smooth'});form.elements.nombre.focus()}));
    list.querySelectorAll('[data-delete]').forEach(b=>b.addEventListener('click',async()=>{const r=rows.find(x=>x.id===b.dataset.delete);if(!confirm(`¿Eliminar a ${r?.nombre_completo||'este registro'}?`))return;const{error}=await sb.rpc('eliminar_nino_por_token',{p_token:token,p_nino_id:b.dataset.delete});if(error)return alert(error.message);if(editingId===b.dataset.delete)resetForm();message.textContent='Registro eliminado correctamente.';await loadChildren()}));
  }
  async function init(){const{data,error}=await sb.rpc('obtener_socio_por_token_ninos',{p_token:token});const socio=Array.isArray(data)?data[0]:data;if(error||!socio){fail(error||'Socio no encontrado');return}document.getElementById('member-name').textContent=socio.nombre_completo||'—';document.getElementById('member-number').textContent=socio.numero_socio?String(socio.numero_socio).padStart(3,'0'):'—';document.getElementById('member-address').textContent=socio.direccion||'—';loading.hidden=true;invalid.hidden=true;content.hidden=false;await loadChildren()}
  cancel.addEventListener('click',()=>{resetForm();message.textContent='Edición cancelada.'});
  form.addEventListener('submit',async e=>{e.preventDefault();message.classList.remove('error');if(!form.reportValidity())return;const nombre=form.elements.nombre.value.trim();if(nombre.length<3){message.textContent='Ingresa el nombre completo.';message.classList.add('error');return}save.disabled=true;message.textContent='Guardando…';const args={p_token:token,p_nombre:nombre,p_fecha_nacimiento:form.elements.fecha_nacimiento.value,p_sexo:form.elements.sexo.value};const result=editingId?await sb.rpc('actualizar_nino_por_token',{...args,p_nino_id:editingId}):await sb.rpc('registrar_nino_por_token',args);save.disabled=false;if(result.error){message.textContent='No se pudo guardar: '+result.error.message;message.classList.add('error');return}message.textContent=editingId?'Cambios guardados correctamente.':'Registro guardado correctamente. Puedes agregar otro niño o niña.';resetForm();await loadChildren();form.elements.nombre.focus()});
  init();
})();
