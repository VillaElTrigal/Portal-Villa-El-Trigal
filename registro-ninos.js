(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{},loading=document.getElementById('child-loading'),invalid=document.getElementById('child-invalid'),expired=document.getElementById('child-expired'),finished=document.getElementById('child-finished'),content=document.getElementById('child-content');
  const hideAll=()=>{loading.hidden=true;invalid.hidden=true;expired.hidden=true;finished.hidden=true;content.hidden=true};
  const fail=d=>{hideAll();invalid.hidden=false;if(d){document.getElementById('invalid-message').textContent=typeof d==='string'?d:'No fue posible validar el enlace.';console.error(d)}};
  if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey){fail('Falta configuración de Supabase');return}
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey),params=new URLSearchParams(location.search),token=params.get('token')||params.get('registro_ninos');
  const esc=v=>String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const dateCL=v=>v?new Date(v+'T12:00:00').toLocaleDateString('es-CL'):'—';
  const rutClean=r=>String(r||'').replace(/[^0-9kK]/g,'').toUpperCase();
  const formatRut=r=>{const c=rutClean(r);if(c.length<2)return c;let b=c.slice(0,-1),dv=c.slice(-1),out='';while(b.length>3){out='.'+b.slice(-3)+out;b=b.slice(0,-3)}return b+out+'-'+dv};
  const validRut=r=>{r=rutClean(r);if(r.length<7)return false;const body=r.slice(0,-1),dv=r.slice(-1);let sum=0,m=2;for(let i=body.length-1;i>=0;i--){sum+=Number(body[i])*m;m=m===7?2:m+1}const x=11-(sum%11),expected=x===11?'0':x===10?'K':String(x);return dv===expected};
  const childUrl=t=>{const u=new URL('./registro-ninos.html',location.href);u.search='';u.searchParams.set('token',t);return u.href};
  if(!token){fail('El enlace no contiene un código válido.');return}

  const form=document.getElementById('child-form'),message=document.getElementById('child-message'),list=document.getElementById('child-list'),count=document.getElementById('saved-count'),save=document.getElementById('save-child'),cancel=document.getElementById('cancel-edit'),birth=form.elements.fecha_nacimiento,rutInput=form.elements.rut,hasSpecial=form.elements.tiene_condicion_especial,specialFields=document.getElementById('special-fields'),noChildren=document.getElementById('save-no-children'),noChildrenMessage=document.getElementById('no-children-message');
  let editingId=null,rows=[];birth.max=new Date().toISOString().slice(0,10);
  rutInput.addEventListener('input',()=>rutInput.value=formatRut(rutInput.value));
  function toggleSpecial(){specialFields.hidden=!hasSpecial.checked;if(!hasSpecial.checked){form.querySelectorAll('[name="condicion"]').forEach(i=>i.checked=false);form.elements.condicion_otro.value='';form.elements.observaciones_especiales.value='';form.elements.autoriza_datos_sensibles.checked=false}}
  hasSpecial.addEventListener('change',toggleSpecial);
  function resetForm(){editingId=null;form.reset();form.elements.participa_actividades.checked=true;birth.max=new Date().toISOString().slice(0,10);save.textContent='Guardar niño o niña';cancel.hidden=true;rutInput.readOnly=false;toggleSpecial()}
  function selectedConditions(){return [...form.querySelectorAll('[name="condicion"]:checked')].map(x=>x.value)}

  async function loadChildren(){
    const{data,error}=await sb.rpc('listar_ninos_por_token',{p_token:token});
    if(error){list.innerHTML='<p class="empty-list">No fue posible cargar los registros.</p>';console.error(error);return}
    rows=data||[];count.textContent=rows.length;
    list.innerHTML=rows.length?rows.map(r=>{const conditions=(r.condiciones_especiales||[]).join(', ');return `<article class="child-record"><div><strong>${esc(r.nombre_completo)}</strong><small>${esc(formatRut(r.rut)||'RUT pendiente')} · ${esc(r.parentesco||'Parentesco pendiente')} · Nacimiento: ${esc(dateCL(r.fecha_nacimiento))}</small>${r.tiene_condicion_especial?`<small class="special-summary">Consideraciones: ${esc(conditions||r.condicion_otro||'Registradas')}</small>`:''}</div><span class="child-sex">${r.sexo==='F'?'F - Niña':'M - Niño'}</span><div class="record-badges"><span>${r.participa_actividades?'Participa en actividades':'No participa'}</span></div><div class="child-record-actions"><button type="button" class="button secondary" data-edit="${r.id}">Editar</button><button type="button" class="button danger" data-delete="${r.id}">Eliminar</button></div></article>`}).join(''):'<p class="empty-list">Todavía no has agregado niños o niñas.</p>';
    list.querySelectorAll('[data-edit]').forEach(b=>b.addEventListener('click',()=>{const r=rows.find(x=>x.id===b.dataset.edit);if(!r)return;editingId=r.id;form.elements.rut.value=formatRut(r.rut||'');rutInput.readOnly=!!r.rut;form.elements.parentesco.value=r.parentesco||'';form.elements.nombre.value=r.nombre_completo;form.elements.fecha_nacimiento.value=r.fecha_nacimiento;form.elements.sexo.value=r.sexo;form.elements.participa_actividades.checked=r.participa_actividades!==false;hasSpecial.checked=!!r.tiene_condicion_especial;toggleSpecial();(r.condiciones_especiales||[]).forEach(v=>{const el=[...form.querySelectorAll('[name="condicion"]')].find(i=>i.value===v);if(el)el.checked=true});form.elements.condicion_otro.value=r.condicion_otro||'';form.elements.observaciones_especiales.value=r.observaciones_especiales||'';form.elements.autoriza_datos_sensibles.checked=!!r.autoriza_datos_sensibles;save.textContent='Guardar cambios';cancel.hidden=false;form.scrollIntoView({behavior:'smooth'});form.elements.nombre.focus()}));
    list.querySelectorAll('[data-delete]').forEach(b=>b.addEventListener('click',async()=>{const r=rows.find(x=>x.id===b.dataset.delete);if(!confirm(`¿Eliminar a ${r?.nombre_completo||'este registro'}?`))return;const{error}=await sb.rpc('eliminar_nino_por_token',{p_token:token,p_nino_id:b.dataset.delete});if(error)return alert(error.message);if(editingId===b.dataset.delete)resetForm();message.textContent='Registro eliminado correctamente.';await loadChildren()}));
  }

  function showExpired(canRenew=true){hideAll();expired.hidden=false;document.querySelectorAll('[data-renew-method]').forEach(b=>b.disabled=!canRenew);if(!canRenew)document.getElementById('renew-message').textContent='Ya se solicitó un enlace durante las últimas 24 horas. Revisa el correo o WhatsApp registrado.'}
  async function init(){
    const stateResult=await sb.rpc('estado_registro_ninos_por_token',{p_token:token});
    const state=Array.isArray(stateResult.data)?stateResult.data[0]:stateResult.data;
    if(stateResult.error){fail(stateResult.error.message);return}
    if(!state||state.estado==='invalido'){fail('Este enlace no es válido o el socio ya no se encuentra activo.');return}
    if(state.estado==='vencido'){showExpired(state.puede_renovar!==false);return}
    if(state.estado==='sin_ninos'){hideAll();finished.hidden=false;return}
    const{data,error}=await sb.rpc('obtener_socio_por_token_ninos',{p_token:token});const socio=Array.isArray(data)?data[0]:data;
    if(error||!socio){fail(error?.message||'Socio no encontrado');return}
    document.getElementById('member-name').textContent=socio.nombre_completo||'—';document.getElementById('member-number').textContent=socio.numero_socio?String(socio.numero_socio).padStart(3,'0'):'—';document.getElementById('member-address').textContent=socio.direccion||'—';hideAll();content.hidden=false;resetForm();await loadChildren();
  }

  document.querySelectorAll('[data-renew-method]').forEach(button=>button.addEventListener('click',async()=>{
    const renewMessage=document.getElementById('renew-message'),share=document.getElementById('renew-share');
    document.querySelectorAll('[data-renew-method]').forEach(b=>b.disabled=true);renewMessage.textContent='Generando un nuevo enlace…';share.hidden=true;
    const{data,error}=await sb.rpc('solicitar_nuevo_enlace_ninos',{p_token:token,p_medio:button.dataset.renewMethod});const result=Array.isArray(data)?data[0]:data;
    if(error||!result?.ok){renewMessage.textContent=error?.message||result?.mensaje||'No fue posible generar el enlace.';return}
    const link=childUrl(result.nuevo_token),text=`Hola. Se generó un nuevo enlace para registrar a los niños y niñas del hogar. Tiene una vigencia de 30 días: ${link}`;
    const phone=String(result.telefono||'').replace(/\D/g,'');const wa=phone?`https://wa.me/${phone.startsWith('56')?phone:'56'+phone}?text=${encodeURIComponent(text)}`:'';const mail=result.correo?`mailto:${encodeURIComponent(result.correo)}?subject=${encodeURIComponent('Nuevo enlace para registro de niños y niñas')}&body=${encodeURIComponent(text)}`:'';
    renewMessage.textContent='Nuevo enlace generado correctamente. Tiene una vigencia de 30 días.';
    share.innerHTML=`<p>El sistema dejó registrada la solicitud. Mientras se conecta un proveedor automático, puedes abrir el canal disponible:</p>${wa?`<a class="button primary" target="_blank" rel="noopener" href="${wa}">Abrir WhatsApp</a>`:''}${mail?`<a class="button secondary" href="${mail}">Abrir correo</a>`:''}<button class="button secondary" id="copy-renew-link" type="button">Copiar enlace</button><p><code>${esc(link)}</code></p>`;share.hidden=false;document.getElementById('copy-renew-link').onclick=async()=>{try{await navigator.clipboard.writeText(link);renewMessage.textContent='Enlace copiado.'}catch{prompt('Copia este enlace:',link)}};
  }));

  noChildren.addEventListener('click',async()=>{
    if(rows.length){noChildrenMessage.textContent='Ya existen niños o niñas registrados. Elimina esos registros antes de declarar que no hay niños o niñas en el hogar.';return}
    if(!confirm('¿Confirmas que actualmente no hay niños ni niñas que residan en este hogar?'))return;
    noChildren.disabled=true;noChildrenMessage.textContent='Guardando…';const{error}=await sb.rpc('declarar_hogar_sin_ninos',{p_token:token});noChildren.disabled=false;
    if(error){noChildrenMessage.textContent='No se pudo guardar: '+error.message;return}hideAll();finished.hidden=false;
  });

  cancel.addEventListener('click',()=>{resetForm();message.textContent='Edición cancelada.'});
  form.addEventListener('submit',async e=>{e.preventDefault();message.classList.remove('error');if(!form.reportValidity())return;const rut=formatRut(rutInput.value),nombre=form.elements.nombre.value.trim(),conditions=selectedConditions();if(!validRut(rut)){message.textContent='El RUT ingresado no es válido.';message.classList.add('error');rutInput.focus();return}if(nombre.length<3){message.textContent='Ingresa el nombre completo.';message.classList.add('error');return}if(!form.elements.parentesco.value){message.textContent='Selecciona el parentesco.';message.classList.add('error');return}if(hasSpecial.checked&&!conditions.length&&!form.elements.condicion_otro.value.trim()&&!form.elements.observaciones_especiales.value.trim()){message.textContent='Describe o selecciona al menos una consideración especial.';message.classList.add('error');return}if(hasSpecial.checked&&!form.elements.autoriza_datos_sensibles.checked){message.textContent='Debes autorizar el registro de esta información sensible para guardarla.';message.classList.add('error');return}save.disabled=true;message.textContent='Guardando…';const args={p_token:token,p_rut:rut,p_nombre:nombre,p_fecha_nacimiento:form.elements.fecha_nacimiento.value,p_sexo:form.elements.sexo.value,p_parentesco:form.elements.parentesco.value,p_participa_actividades:form.elements.participa_actividades.checked,p_tiene_condicion_especial:hasSpecial.checked,p_condiciones_especiales:conditions,p_condicion_otro:form.elements.condicion_otro.value.trim()||null,p_observaciones_especiales:form.elements.observaciones_especiales.value.trim()||null,p_autoriza_datos_sensibles:form.elements.autoriza_datos_sensibles.checked};const result=editingId?await sb.rpc('actualizar_nino_por_token',{...args,p_nino_id:editingId}):await sb.rpc('registrar_nino_por_token',args);save.disabled=false;if(result.error){console.error('Error al guardar niño o niña:',result.error);const detail=result.error.details||result.error.hint||'';message.textContent='No se pudo guardar: '+result.error.message+(detail?' — '+detail:'');message.classList.add('error');return}message.textContent=editingId?'Cambios guardados correctamente.':'Registro guardado correctamente. Puedes agregar otro niño o niña.';resetForm();await loadChildren();form.elements.rut.focus()});
  init();
})();
