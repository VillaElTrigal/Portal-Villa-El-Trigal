(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{};
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
  let token=sessionStorage.getItem('sigve_portal_token'), children=[], currentMemberNumber='', childFormDirty=false, vias=[], currentSocio=null;
  const $=(id)=>document.getElementById(id);
  const msg=(id,text,type='')=>{const e=$(id);e.textContent=text;e.className=`message ${type}`};
  const rpc=async(fn,args={})=>{const {data,error}=await sb.rpc(fn,args);if(error)throw new Error(error.message);return data};
  const fmtDate=(v)=>v?new Intl.DateTimeFormat('es-CL',{timeZone:'UTC'}).format(new Date(v+'T00:00:00Z')):'—';
  const escape=(s='')=>String(s).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const normalizeMemberNumber=(value)=>{const digits=String(value??'').replace(/\D/g,'');if(!digits)return null;const number=Number.parseInt(digits,10);return Number.isSafeInteger(number)?number:null};
  const rutClean=(value)=>String(value||'').replace(/[^0-9kK]/g,'').toUpperCase();
  const formatRut=(value)=>{const clean=rutClean(value);if(clean.length<2)return clean;let body=clean.slice(0,-1),dv=clean.slice(-1),formatted='';while(body.length>3){formatted='.'+body.slice(-3)+formatted;body=body.slice(0,-3)}return body+formatted+'-'+dv};
    const phoneDigitsPortal=value=>{let d=String(value||'').replace(/\D/g,'');if(d.startsWith('56'))d=d.slice(2);if(d.length>=9&&d.startsWith('9'))d=d.slice(1);return d.slice(0,8)};
  const formatPhonePortal=value=>{const d=phoneDigitsPortal(value);return d?`+56 9 ${d.slice(0,4)}${d.length>4?' '+d.slice(4):''}`:''};
  const phoneDbPortal=value=>{const d=phoneDigitsPortal(value);return d.length===8?`+569${d}`:null};
const validRut=(value)=>{const clean=rutClean(value);if(clean.length<7)return false;const body=clean.slice(0,-1),dv=clean.slice(-1);let sum=0,multiplier=2;for(let i=body.length-1;i>=0;i--){sum+=Number(body[i])*multiplier;multiplier=multiplier===7?2:multiplier+1}const result=11-(sum%11),expected=result===11?'0':result===10?'K':String(result);return dv===expected};

  const normalizeSearch=value=>String(value||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const chileTodayParts=()=>{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',month:'2-digit',day:'2-digit'}).formatToParts(new Date());return {month:Number(parts.find(p=>p.type==='month')?.value),day:Number(parts.find(p=>p.type==='day')?.value)}};
  function renderBirthdayBanner(socio){const box=$('birthdayPortalBanner');if(!box||!socio?.fecha_nacimiento){if(box)box.hidden=true;return}const birth=new Date(socio.fecha_nacimiento+'T12:00:00Z'),now=chileTodayParts();let month=birth.getUTCMonth()+1,day=birth.getUTCDate();if(month===2&&day===29){const y=Number(new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric'}).format(new Date()));const leap=(y%4===0&&y%100!==0)||y%400===0;if(!leap)day=28}if(month===now.month&&day===now.day){box.innerHTML=`<strong>🎉 ¡Feliz cumpleaños, ${escape((socio.nombres||socio.nombre_completo||'').split(' ')[0])}!</strong><span>La Junta de Vecinos Villa El Trigal te desea un excelente día, lleno de alegría y buenos momentos. 🎂🎈</span>`;box.hidden=false}else box.hidden=true}
  const viaLabel=via=>`${via.tipo} ${via.nombre}`.trim();
  const money=value=>new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(value||0));
  const calcAge=d=>{if(!d)return'';const b=new Date(d+'T12:00:00'),t=new Date();let a=t.getFullYear()-b.getFullYear();if(t<new Date(t.getFullYear(),b.getMonth(),b.getDate()))a--;return a};
  async function loadVias(){const {data,error}=await sb.from('vias').select('id,tipo,nombre,aliases').eq('activa',true).order('nombre');if(error)throw new Error('No fue posible cargar las calles y pasajes.');vias=(data||[]).sort((a,b)=>viaLabel(a).localeCompare(viaLabel(b),'es',{sensitivity:'base'}));}
  function bindViaPicker(){const root=document.querySelector('[data-via-picker]'),input=$('viaSearch'),hidden=$('viaId'),list=root.querySelector('.via-suggestions'),number=$('numeroDomicilio'),preview=$('addressPreview');let matches=[];const update=()=>{const via=vias.find(v=>v.id===hidden.value);preview.textContent=via&&number.value.trim()?`📍 ${viaLabel(via)} ${number.value.trim()}`:'📍 Selecciona una vía e ingresa el número.'};const close=()=>{list.hidden=true;input.setAttribute('aria-expanded','false')};const choose=via=>{hidden.value=via.id;input.value=viaLabel(via);root.classList.remove('invalid');close();update()};const render=()=>{const q=normalizeSearch(input.value);hidden.value='';matches=vias.filter(v=>!q||normalizeSearch([viaLabel(v),...(v.aliases||[])].join(' ')).includes(q)).slice(0,30);list.innerHTML=matches.length?matches.map((v,i)=>`<button type="button" class="via-suggestion" data-i="${i}">${escape(viaLabel(v))}</button>`).join(''):'<div class="via-empty">No hay coincidencias.</div>';list.hidden=false;input.setAttribute('aria-expanded','true');list.querySelectorAll('[data-i]').forEach(b=>b.onclick=()=>choose(matches[+b.dataset.i]));update()};input.addEventListener('focus',render);input.addEventListener('input',render);number.addEventListener('input',()=>{number.value=number.value.replace(/[^0-9]/g,'');update()});document.addEventListener('click',e=>{if(!root.contains(e.target))close()});return {set(viaId,numero,direccion){hidden.value=viaId||'';number.value=numero||'';const via=vias.find(v=>v.id===viaId);input.value=via?viaLabel(via):(direccion||'').replace(/\s+\d+[A-Za-z-]*$/,'');update()},get(){const via=vias.find(v=>v.id===hidden.value),numero=number.value.trim();if(!via||!numero){root.classList.add('invalid');return null}return {via_id:via.id,numero_domicilio:numero,direccion:`${viaLabel(via)} ${numero}`}}};}
  let viaPicker;

  const selectedConditions=()=>[...document.querySelectorAll('input[name="childCondition"]:checked')].map(input=>input.value);
  const setSelectedConditions=(values=[])=>{const selected=new Set(values||[]);document.querySelectorAll('input[name="childCondition"]').forEach(input=>input.checked=selected.has(input.value))};

  document.querySelectorAll('[data-rut]').forEach(input=>input.addEventListener('input',()=>{input.value=formatRut(input.value)}));
  $('telefono')?.addEventListener('blur',()=>{$('telefono').value=formatPhonePortal($('telefono').value)});

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

  const syncOccupation=()=>{$('ocupacionOtroWrap').hidden=$('ocupacion').value!=='Otro';if($('ocupacionOtroWrap').hidden)$('ocupacionOtro').value=''};
  $('ocupacion').addEventListener('change',syncOccupation);
  $('fechaNacimiento').max=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
  $('fechaNacimiento').addEventListener('change',()=>{$('edad').value=calcAge($('fechaNacimiento').value)});

  async function enter(){try{if(!vias.length)await loadVias();if(!viaPicker)viaPicker=bindViaPicker();const rows=await rpc('portal_socio_mis_datos',{p_token:token});const s=rows?.[0];if(!s)throw new Error();currentSocio=s;currentMemberNumber=normalizeMemberNumber(s.numero_socio);renderBirthdayBanner(s);$('loginView').hidden=true;$('portalView').hidden=false;$('logout').hidden=false;$('welcomeName').textContent=s.nombre_completo;$('numero').textContent=s.numero_socio||'—';$('rutRead').textContent=formatRut(s.rut);$('fechaIngreso').textContent=fmtDate(s.fecha_ingreso);$('estado').textContent=s.estado;$('nombres').value=s.nombres||'';$('apellidoPaterno').value=s.apellido_paterno||'';$('apellidoMaterno').value=s.apellido_materno||'';$('fechaNacimiento').value=s.fecha_nacimiento||'';$('edad').value=calcAge(s.fecha_nacimiento);$('estadoCivil').value=s.estado_civil||'';$('ocupacion').value=s.ocupacion||'';$('ocupacionOtro').value=s.ocupacion_otro||'';syncOccupation();viaPicker.set(s.via_id,s.numero_domicilio,s.direccion);$('telefono').value=formatPhonePortal(s.telefono||'');$('correo').value=s.correo||'';if($('portalCertName')){$('portalCertName').value=s.nombre_completo||'';$('portalCertNationality').value=s.nacionalidad||'';$('portalCertRut').value=formatRut(s.rut);$('portalCertAddress').value=s.direccion||'';$('portalCertPhone').value=formatPhonePortal(s.telefono||'');$('portalCertEmail').value=s.correo||'';syncPortalCertRecipient();}const pending=Number(s.cuotas_pendientes||0);$('duesStatus').textContent=pending?'Pendiente':'Al día';$('duesStatus').classList.toggle('pending',pending>0);$('lastPaid').textContent=s.ultima_cuota_pagada?fmtDate(s.ultima_cuota_pagada):'Sin pagos registrados';$('pendingCount').textContent=pending;$('pendingAmount').textContent=money(s.monto_adeudado);await loadChildren();await loadPortalQuotas();await loadPortalBenefits()}catch(e){console.error(e);sessionStorage.removeItem('sigve_portal_token');token=null;$('loginView').hidden=false;$('portalView').hidden=true;$('logout').hidden=true;msg('authMsg','Tu sesión venció o no fue posible cargar tus datos. Ingresa nuevamente.','error')}}
  $('dataForm').addEventListener('submit',async(e)=>{e.preventDefault();const address=viaPicker.get();if(!address){msg('dataMsg','Selecciona una calle, pasaje o avenida válida e ingresa el número.','error');return}if($('ocupacion').value==='Otro'&&!$('ocupacionOtro').value.trim()){msg('dataMsg','Especifica tu ocupación.','error');return}const phone=phoneDbPortal($('telefono').value);if($('telefono').value&&!phone){msg('dataMsg','Ingresa un celular chileno válido: +56 9 1234 5678.','error');$('telefono').focus();return}msg('dataMsg','Guardando…');try{await rpc('portal_socio_actualizar_datos',{p_token:token,p_nombres:$('nombres').value.trim(),p_apellido_paterno:$('apellidoPaterno').value.trim(),p_apellido_materno:$('apellidoMaterno').value.trim(),p_fecha_nacimiento:$('fechaNacimiento').value,p_estado_civil:$('estadoCivil').value,p_ocupacion:$('ocupacion').value,p_ocupacion_otro:$('ocupacion').value==='Otro'?$('ocupacionOtro').value.trim():null,p_via_id:address.via_id,p_numero_domicilio:address.numero_domicilio,p_telefono:phone,p_correo:$('correo').value});$('welcomeName').textContent=[$('nombres').value.trim(),$('apellidoPaterno').value.trim(),$('apellidoMaterno').value.trim()].filter(Boolean).join(' ');msg('dataMsg','Datos actualizados correctamente.','success')}catch(err){msg('dataMsg',err.message,'error')}});
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

  let portalPendingQuotas=[];
  const quotaMonthLabel=v=>{if(!v)return '';const [y,m]=v.slice(0,7).split('-');return new Date(Number(y),Number(m)-1,1).toLocaleDateString('es-CL',{month:'long',year:'numeric'})};
  async function loadPortalQuotas(){
    const box=$('portalQuotaList'); if(!box)return;
    try{
      const allPendingQuotas=await rpc('portal_socio_mis_cuotas',{p_token:token})||[];
      const currentPeriod=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit'}).format(new Date());
      portalPendingQuotas=allPendingQuotas.filter(q=>String(q.periodo||'').slice(0,7)<=currentPeriod);
      // El resumen de "Mis datos" debe usar la misma regla que Pago de cuotas:
      // solo meses vencidos o el mes actual, nunca cuotas futuras.
      const exigibleTotal=portalPendingQuotas.reduce((sum,q)=>sum+Number(q.monto||0),0);
      const exigibleCount=portalPendingQuotas.length;
      $('duesStatus').textContent=exigibleCount?'Pendiente':'Al día';
      $('duesStatus').classList.toggle('pending',exigibleCount>0);
      $('pendingCount').textContent=exigibleCount;
      $('pendingAmount').textContent=money(exigibleTotal);
      if(!portalPendingQuotas.length){box.innerHTML='<div class="notice success-notice">✅ No tienes cuotas exigibles pendientes.</div>';$('portalQuotaTotal').textContent=money(0);$('sendQuotaWhatsapp').disabled=true;return}
      box.innerHTML=portalPendingQuotas.map(q=>`<label class="portal-quota-row"><input type="checkbox" data-portal-quota="${q.id}" value="${Number(q.monto)||0}"><span><b>${escape(quotaMonthLabel(q.periodo))}</b><small>Cuota pendiente</small></span><strong>${money(q.monto)}</strong></label>`).join('');
      box.querySelectorAll('[data-portal-quota]').forEach(c=>c.addEventListener('change',updatePortalQuotaTotal));
      updatePortalQuotaTotal();
    }catch(err){box.innerHTML='<div class="notice">No fue posible cargar el detalle de cuotas.</div>';msg('paymentMsg',err.message,'error')}
  }
  function selectedPortalQuotas(){return portalPendingQuotas.filter(q=>document.querySelector(`input[data-portal-quota="${CSS.escape(String(q.id))}"]`)?.checked)}
  function updatePortalQuotaTotal(){const selected=selectedPortalQuotas(),total=selected.reduce((a,q)=>a+Number(q.monto||0),0);$('portalQuotaTotal').textContent=money(total);$('sendQuotaWhatsapp').disabled=!selected.length}
  $('sendQuotaWhatsapp')?.addEventListener('click',()=>{
    const selected=selectedPortalQuotas();if(!selected.length)return;
    const months=selected.map(q=>quotaMonthLabel(q.periodo)).join(', '),total=selected.reduce((a,q)=>a+Number(q.monto||0),0);
    const name=$('welcomeName').textContent.trim(),number=$('numero').textContent.trim(),rut=$('rutRead').textContent.trim();
    const text=`Hola. Adjunto el comprobante del pago de mi cuota social.\n\nSOCIO: ${name}\nN° DE SOCIO: ${number}\nRUT: ${rut}\nCUOTA(S): ${months}\nMONTO TOTAL: ${money(total)}\nMEDIO: Transferencia\n\nPor favor confirmar la recepción del comprobante.\nJunta de Vecinos Villa El Trigal.`;
    window.SIGVE_WHATSAPP?.open?window.SIGVE_WHATSAPP.open('56974596793',text):window.open(`https://wa.me/56974596793?text=${encodeURIComponent(text)}`,'_blank','noopener');
  });


  async function loadPortalBenefits(){
    const box=$('portalBenefitsSummary'); if(!box)return;
    try{
      const rows=await rpc('portal_socio_mis_beneficios',{p_token:token})||[];
      const infoRows=await rpc('portal_socio_beneficios_informativos',{p_token:token})||[];
      if(!rows.length&&!infoRows.length){box.innerHTML='<div class="notice">Actualmente no hay beneficios activos.</div>';return}
      const operational=rows.map(b=>{
        const ok=!!b.cumple;
        const icon=b.tipo==='gratis'?'🎁':'🏅';
        const value=b.tipo==='gratis'?'1 arriendo gratuito disponible':b.tipo==='porcentaje'?`${Number(b.valor||0)}% de descuento`:`${money(b.valor)} de descuento`;
        return `<article class="benefit-status ${ok?'eligible':'pending'}"><div class="benefit-icon">${icon}</div><div><h3>${escape(b.nombre)}</h3><p class="benefit-result">${ok?'✅ Beneficio disponible':'⏳ Aún no disponible'}</p><p>${escape(b.motivo||'')}</p><small>${escape(b.detalle||value)}</small></div></article>`;
      }).join('');
      const informational=infoRows.map(b=>`<article class="benefit-status eligible"><div class="benefit-icon">🎁</div><div><h3>${escape(b.nombre)}</h3><p class="benefit-result">ℹ️ Beneficio para socios</p><p>${escape(b.descripcion||'')}</p>${b.requisitos_texto?`<small><strong>Cómo acceder:</strong> ${escape(b.requisitos_texto)}</small>`:''}${b.vigencia_hasta?`<small> · Vigente hasta ${new Date(b.vigencia_hasta+'T12:00:00').toLocaleDateString('es-CL')}</small>`:''}</div></article>`).join('');
      box.innerHTML=operational+informational;
    }catch(err){box.innerHTML='<div class="notice">No fue posible revisar tus beneficios.</div>';msg('benefitsMsg',err.message,'error')}
  }



  $('portalCertPurpose')?.addEventListener('change',()=>{const show=$('portalCertPurpose').value==='otro';$('portalCertPurposeOtherWrap').hidden=!show;$('portalCertPurposeOther').required=show;if(!show)$('portalCertPurposeOther').value='';});

  const portalCertRecipient=()=>document.querySelector('input[name="portalCertRecipient"]:checked')?.value||'titular';
  function syncPortalCertRecipient(){
    if(!currentSocio)return;
    const other=portalCertRecipient()==='otro';
    $('portalCertName').readOnly=!other;
    $('portalCertNationality').readOnly=false;
    $('portalCertRut').readOnly=!other;
    $('portalCertAddress').readOnly=true;
    $('portalCertPhone').readOnly=true;
    $('portalCertEmail').readOnly=true;
    if(other){
      $('portalCertName').value='';
      $('portalCertNationality').value='';
      $('portalCertRut').value='';
      $('portalCertName').focus();
    }else{
      $('portalCertName').value=currentSocio.nombre_completo||'';
      $('portalCertNationality').value=currentSocio.nacionalidad||'';
      $('portalCertRut').value=formatRut(currentSocio.rut);
    }
    $('portalCertAddress').value=currentSocio.direccion||'';
    $('portalCertPhone').value=formatPhonePortal(currentSocio.telefono||'');
    $('portalCertEmail').value=currentSocio.correo||'';
  }
  document.querySelectorAll('input[name="portalCertRecipient"]').forEach(r=>r.addEventListener('change',syncPortalCertRecipient));
  $('portalCertRut')?.addEventListener('input',()=>{$('portalCertRut').value=formatRut($('portalCertRut').value)});

  $('portalCertificateForm')?.addEventListener('submit',async(e)=>{
    e.preventDefault();
    const purpose=$('portalCertPurpose').value;
    const purposeOther=$('portalCertPurposeOther').value.trim();
    if(!purpose){msg('portalCertMsg','Selecciona la finalidad del certificado.','error');return}
    if(purpose==='otro'&&!purposeOther){msg('portalCertMsg','Especifica la otra finalidad.','error');$('portalCertPurposeOther').focus();return}
    const button=e.currentTarget.querySelector('button[type="submit"]'),original=button.textContent;
    button.disabled=true;button.textContent='Registrando solicitud…';msg('portalCertMsg','');
    try{
      const rutCert=formatRut($('portalCertRut').value);
      if(!validRut(rutCert)){msg('portalCertMsg','El RUT ingresado no es válido.','error');$('portalCertRut').focus();throw new Error('RUT inválido')}
      $('portalCertRut').value=rutCert;
      const paraOtro=portalCertRecipient()==='otro';
      const rows=await rpc('solicitar_certificado_residencia',{p_nombre:$('portalCertName').value.trim(),p_rut:rutCert,p_nacionalidad:$('portalCertNationality').value.trim(),p_direccion:$('portalCertAddress').value,p_finalidad:purpose,p_finalidad_otro:purposeOther||null,p_telefono:currentSocio?.telefono||null,p_correo:currentSocio?.correo||null,p_origen:'portal_socio',p_token:token,p_para_otro:paraOtro});
      const row=rows?.[0]||rows,folio=String(row.folio).padStart(5,'0');
      const text=`SOLICITUD DE CERTIFICADO DE RESIDENCIA

N° CERTIFICADO: CR-${folio}
ORIGEN: Portal Socio
SOLICITANTE: ${currentSocio?.nombre_completo||$('welcomeName').textContent.trim()}
CERTIFICADO PARA: ${$('portalCertName').value}
N° DE SOCIO: ${$('numero').textContent.trim()}
NACIONALIDAD: ${$('portalCertNationality').value}
RUT: ${row.rut_formateado||$('portalCertRut').value}
DIRECCIÓN: ${$('portalCertAddress').value}
FINALIDAD: ${purpose==='otro'?purposeOther:({laboral:'Laboral',estudiantil:'Estudiantil',transporte:'Transporte'}[purpose]||purpose)}
ESTADO: Pendiente de pago
VALOR: ${money(row.valor||1000)}

La solicitud quedó registrada en SIGVE.`;
      window.SIGVE_WHATSAPP?.open?window.SIGVE_WHATSAPP.open('56974596793',text):window.open(`https://wa.me/56974596793?text=${encodeURIComponent(text)}`,'_blank','noopener');
      $('portalCertPurpose').value='';$('portalCertPurposeOther').value='';$('portalCertPurposeOtherWrap').hidden=true;document.querySelector('input[name="portalCertRecipient"][value="titular"]').checked=true;syncPortalCertRecipient();msg('portalCertMsg',`Solicitud registrada como CR-${folio}.`,'success');
    }catch(err){msg('portalCertMsg',err.message,'error')}
    finally{button.disabled=false;button.textContent=original}
  });

  $('openRentalFromPortal')?.addEventListener('click',()=>{
    const context={
      origen:'portal_socio',
      portal_token:token,
      nombre:$('welcomeName').textContent.trim(),
      rut:$('rutRead').textContent.trim(),
      telefono:currentSocio?.telefono||'',
      creado_en:Date.now()
    };
    sessionStorage.setItem('sigve_reserva_context',JSON.stringify(context));
    location.href='index.html?reserva=portal_socio#arriendo';
  });

  if(token)enter();
})();
