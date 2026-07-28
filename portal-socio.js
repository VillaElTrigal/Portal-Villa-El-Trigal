(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{};
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
  let token=sessionStorage.getItem('sigve_portal_token'), children=[], currentMemberNumber='', childFormDirty=false, vias=[];
  const $=(id)=>document.getElementById(id);
  const msg=(id,text,type='')=>{const e=$(id);e.textContent=text;e.className=`message ${type}`};
  const rpc=async(fn,args={})=>{const {data,error}=await sb.rpc(fn,args);if(error)throw new Error(error.message);return data};
  const fmtDate=(v)=>v?new Intl.DateTimeFormat('es-CL',{timeZone:'UTC'}).format(new Date(v+'T00:00:00Z')):'—';
  const escape=(s='')=>String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const normalizeMemberNumber=(value)=>{const digits=String(value??'').replace(/\D/g,'');if(!digits)return null;const number=Number.parseInt(digits,10);return Number.isSafeInteger(number)?number:null};
  const rutClean=(value)=>String(value||'').replace(/[^0-9kK]/g,'').toUpperCase();
  const formatRut=(value)=>{const clean=rutClean(value);if(clean.length<2)return clean;let body=clean.slice(0,-1),dv=clean.slice(-1),formatted='';while(body.length>3){formatted='.'+body.slice(-3)+formatted;body=body.slice(0,-3)}return body+formatted+'-'+dv};
  const validRut=(value)=>{const clean=rutClean(value);if(clean.length<7)return false;const body=clean.slice(0,-1),dv=clean.slice(-1);let sum=0,multiplier=2;for(let i=body.length-1;i>=0;i--){sum+=Number(body[i])*multiplier;multiplier=multiplier===7?2:multiplier+1}const result=11-(sum%11),expected=result===11?'0':result===10?'K':String(result);return dv===expected};

  const normalizeSearch=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const viaLabel=via=>`${via.tipo} ${via.nombre}`.trim();
  const money=value=>new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(value||0));
  async function loadVias(){const {data,error}=await sb.from('vias').select('id,tipo,nombre,aliases').eq('activa',true).order('nombre');if(error)throw new Error('No fue posible cargar las calles y pasajes.');vias=(data||[]).sort((a,b)=>viaLabel(a).localeCompare(viaLabel(b),'es',{sensitivity:'base'}));}
  function bindViaPicker(){const root=document.querySelector('[data-via-picker]'),input=$('viaSearch'),hidden=$('viaId'),list=root.querySelector('.via-suggestions'),number=$('numeroDomicilio'),preview=$('addressPreview');let matches=[];const update=()=>{const via=vias.find(v=>v.id===hidden.value);preview.textContent=via&&number.value.trim()?`📍 ${viaLabel(via)} ${number.value.trim()}`:'📍 Selecciona una vía e ingresa el número.'};const close=()=>{list.hidden=true;input.setAttribute('aria-expanded','false')};const choose=via=>{hidden.value=via.id;input.value=viaLabel(via);root.classList.remove('invalid');close();update()};const render=()=>{const q=normalizeSearch(input.value);hidden.value='';matches=vias.filter(v=>!q||normalizeSearch([viaLabel(v),...(v.aliases||[])].join(' ')).includes(q)).slice(0,30);list.innerHTML=matches.length?matches.map((v,i)=>`<button type="button" class="via-suggestion" data-i="${i}">${escape(viaLabel(v))}</button>`).join(''):'<div class="via-empty">No hay coincidencias.</div>';list.hidden=false;input.setAttribute('aria-expanded','true');list.querySelectorAll('[data-i]').forEach(b=>b.onclick=()=>choose(matches[+b.dataset.i]));update()};input.addEventListener('focus',render);input.addEventListener('input',render);number.addEventListener('input',()=>{number.value=number.value.replace(/[^0-9]/g,'');update()});document.addEventListener('click',e=>{if(!root.contains(e.target))close()});return {set(viaId,numero,direccion){hidden.value=viaId||'';number.value=numero||'';const via=vias.find(v=>v.id===viaId);input.value=via?viaLabel(via):(direccion||'').replace(/\s+\d+[A-Za-z-]*$/,'');update()},get(){const via=vias.find(v=>v.id===hidden.value),numero=number.value.trim();if(!via||!numero){root.classList.add('invalid');return null}return {via_id:via.id,numero_domicilio:numero,direccion:`${viaLabel(via)} ${numero}`}}};}
  let viaPicker;

  const selectedConditions=()=>[...document.querySelectorAll('input[name="childCondition"]:checked')].map(input=>input.value);
  const setSelectedConditions=(values=[])=>{const selected=new Set(values||[]);document.querySelectorAll('input[name="childCondition"]').forEach(input=>input.checked=selected.has(input.value))};

  document.querySelectorAll('[data-rut]').forEach(input=>input.addEventListener('input',()=>{input.value=formatRut(input.value)}));

  $('rutForm').addEventListener('submit',async(e)=>{
    e.preventDefault();
    msg('authMsg','');
    const rut=formatRut($('rut').value);
    $('rut').value=rut;
    if(!validRut(rut)){msg('authMsg','El RUT ingresado no es válido.','error');$('rut').focus();return}
    msg('authMsg','Validando datos…');
    try{const memberNumber=normalizeMemberNumber($('memberNumber').value);if(memberNumber===null)throw new Error('Los datos ingresados son incorrectos');const t=await rpc('portal_socio_ingresar',{p_rut:rut,p_numero_socio:memberNumber});if(!t)throw new Error('Los datos ingresados son incorrectos');token=t;sessionStorage.setItem('sigve_portal_token',token);await enter()}catch(err){msg('authMsg',err.message.includes('tempor')?err.message:'Los datos ingresados son incorrectos','error')}
  });
  document.querySelectorAll('.tabs button').forEach(b=>b.onclick=()=>{document.querySelectorAll('.tabs button').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('.tab-panel').forEach(p=>p.hidden=p.id!==b.dataset.tab)});

  async function enter(){try{if(!vias.length)await loadVias();if(!viaPicker)viaPicker=bindViaPicker();const rows=await rpc('portal_socio_mis_datos',{p_token:token});const s=rows?.[0];if(!s)throw new Error();currentMemberNumber=normalizeMemberNumber(s.numero_socio);$('loginView').hidden=true;$('portalView').hidden=false;$('logout').hidden=false;$('welcomeName').textContent=s.nombre_completo;$('numero').textContent=s.numero_socio||'—';$('rutRead').textContent=formatRut(s.rut);$('fechaIngreso').textContent=fmtDate(s.fecha_ingreso);$('estado').textContent=s.estado;viaPicker.set(s.via_id,s.numero_domicilio,s.direccion);$('telefono').value=s.telefono||'';$('correo').value=s.correo||'';const pending=Number(s.cuotas_pendientes||0);$('duesStatus').textContent=pending?'Pendiente':'Al día';$('duesStatus').classList.toggle('pending',pending>0);$('lastPaid').textContent=s.ultima_cuota_pagada?fmtDate(s.ultima_cuota_pagada):'Sin pagos registrados';$('pendingCount').textContent=pending;$('pendingAmount').textContent=money(s.monto_adeudado);await loadChildren()}catch(e){console.error(e);sessionStorage.removeItem('sigve_portal_token');token=null;$('loginView').hidden=false;$('portalView').hidden=true;$('logout').hidden=true;msg('authMsg','Tu sesión venció o no fue posible cargar tus datos. Ingresa nuevamente.','error')}}
  $('dataForm').addEventListener('submit',async(e)=>{e.preventDefault();const address=viaPicker.get();if(!address){msg('dataMsg','Selecciona una calle, pasaje o avenida válida e ingresa el número.','error');return}msg('dataMsg','Guardando…');try{await rpc('portal_socio_actualizar_datos',{p_token:token,p_via_id:address.via_id,p_numero_domicilio:address.numero_domicilio,p_telefono:$('telefono').value,p_correo:$('correo').value});msg('dataMsg','Datos actualizados correctamente.','success')}catch(err){msg('dataMsg',err.message,'error')}});
  async function loadChildren(){children=await rpc('portal_socio_listar_ninos',{p_token:token})||[];const box=$('childrenList');if(!children.length){box.innerHTML='<div class="notice">No hay niños o niñas registrados actualmente.</div>';return}box.innerHTML=children.map(n=>`<article class="child-card"><div><h3>${escape(n.nombre_completo)}</h3><p>RUT: ${escape(formatRut(n.rut))} · Nacimiento: ${fmtDate(n.fecha_nacimiento)}</p><p>${escape(n.parentesco||'Hijo(a)')}${n.tiene_condicion_especial?' · Con consideración especial':''}</p></div><div class="child-actions"><button data-edit="${n.id}">Editar</button><button data-delete="${n.id}">Retirar</button></div></article>`).join('');box.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>openChild(children.find(n=>n.id===b.dataset.edit)));box.querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>removeChild(b.dataset.delete))}

  function toggleSpecial(clear=false){$('specialFields').hidden=!$('childSpecial').checked;if(clear&&!$('childSpecial').checked){setSelectedConditions([]);$('childOther').value='';$('childNotes').value='';$('childConsent').checked=false}}
  $('childSpecial').addEventListener('change',()=>{toggleSpecial(true);childFormDirty=true});
  $('childForm').addEventListener('input',()=>{childFormDirty=true});
  $('childForm').addEventListener('change',()=>{childFormDirty=true});
  $('newChild').onclick=()=>openChild();

  function openChild(n=null){
    $('childForm').reset();
    $('childParticipates').checked=true;
    $('childRelation').value='Hijo(a)';
    $('childId').value=n?.id||'';
    $('childTitle').textContent=n?'Editar registro':'Agregar niño o niña';
    setSelectedConditions([]);
    if(n){$('childName').value=n.nombre_completo||'';$('childRut').value=formatRut(n.rut);$('childBirth').value=n.fecha_nacimiento||'';$('childSex').value=n.sexo||'';$('childRelation').value=n.parentesco||'Hijo(a)';$('childParticipates').checked=n.participa_actividades!==false;$('childSpecial').checked=!!n.tiene_condicion_especial;setSelectedConditions(n.condiciones_especiales||[]);$('childOther').value=n.condicion_otro||'';$('childNotes').value=n.observaciones_especiales||'';$('childConsent').checked=!!n.autoriza_datos_sensibles}
    toggleSpecial(false);msg('childMsg','');childFormDirty=false;$('childDialog').showModal();
  }
  function closeChild(){if(childFormDirty&&!confirm('¿Deseas salir sin guardar los cambios?'))return;$('childDialog').close();childFormDirty=false}
  $('closeChild').onclick=closeChild;
  $('cancelChild').onclick=closeChild;
  $('childDialog').addEventListener('cancel',(e)=>{e.preventDefault();closeChild()});

  $('saveChild').addEventListener('click',async()=>{
    if(!$('childForm').reportValidity())return;
    const rut=formatRut($('childRut').value);$('childRut').value=rut;
    if(!validRut(rut)){msg('childMsg','El RUT ingresado no es válido.','error');$('childRut').focus();return}
    const conditions=selectedConditions();
    if($('childSpecial').checked&&!conditions.length&&!$('childOther').value.trim()&&!$('childNotes').value.trim()){msg('childMsg','Describe o selecciona al menos una consideración especial.','error');return}
    if($('childSpecial').checked&&!$('childConsent').checked){msg('childMsg','Debes autorizar el registro de esta información sensible para guardarla.','error');return}
    msg('childMsg','Guardando…');
    try{await rpc('portal_socio_guardar_nino',{p_token:token,p_id:$('childId').value||null,p_nombre:$('childName').value.trim(),p_rut:rut,p_fecha:$('childBirth').value,p_sexo:$('childSex').value,p_parentesco:$('childRelation').value,p_participa:$('childParticipates').checked,p_tiene_condicion:$('childSpecial').checked,p_condiciones:$('childSpecial').checked?conditions:[],p_otro:$('childSpecial').checked?$('childOther').value.trim():null,p_observaciones:$('childSpecial').checked?$('childNotes').value.trim():null,p_autoriza:$('childSpecial').checked&&$('childConsent').checked});childFormDirty=false;$('childDialog').close();await loadChildren();msg('familyMsg','Registro guardado.','success')}catch(err){msg('childMsg',err.message,'error')}
  });
  async function removeChild(id){if(!confirm('¿Retirar este registro del grupo familiar? Se conservará como antecedente histórico.'))return;try{await rpc('portal_socio_eliminar_nino',{p_token:token,p_id:id});await loadChildren();msg('familyMsg','Registro retirado.','success')}catch(err){msg('familyMsg',err.message,'error')}}
  $('noChildren').onclick=async()=>{if(!confirm('¿Confirmas que actualmente no tienes niños o niñas que registrar?'))return;try{await rpc('portal_socio_declarar_sin_ninos',{p_token:token});msg('familyMsg','Declaración registrada correctamente.','success')}catch(err){msg('familyMsg',err.message,'error')}};
  $('resignForm').addEventListener('submit',async(e)=>{e.preventDefault();if(normalizeMemberNumber($('resignConfirm').value)!==currentMemberNumber){msg('resignMsg','El número de socio no coincide.','error');return}if(!confirm('Esta es la confirmación final. ¿Registrar tu renuncia voluntaria?'))return;msg('resignMsg','Registrando renuncia…');try{await rpc('portal_socio_renunciar_numero',{p_token:token,p_numero_socio:normalizeMemberNumber($('resignConfirm').value),p_motivo:$('resignReason').value});sessionStorage.removeItem('sigve_portal_token');alert('Tu renuncia voluntaria quedó registrada.');location.href='index.html'}catch(err){msg('resignMsg',err.message,'error')}});
  $('logout').onclick=async()=>{try{if(token)await rpc('portal_socio_cerrar_sesion',{p_token:token})}catch{}sessionStorage.removeItem('sigve_portal_token');location.reload()};
  if(token)enter();
})();
