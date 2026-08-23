/* SIGVE v1.1.0 · Gestión Financiera Integrada */
(()=>{
'use strict';
const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];
const cfg=window.PORTAL_CONFIG||{};
const v110sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
const esc=v=>String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const money=v=>new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(v)||0);
const dateCL=v=>v?new Date(v+'T12:00:00').toLocaleDateString('es-CL'):'—';
const today=()=>{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()),v=Object.fromEntries(parts.map(x=>[x.type,x.value]));return `${v.year}-${v.month}-${v.day}`};
const monthBounds=m=>({from:m+'-01',to:new Date(+m.slice(0,4),+m.slice(5,7),0).toISOString().slice(0,10)});
const monthMove=(m,n)=>{const d=new Date(+m.slice(0,4),+m.slice(5,7)-1+n,1);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`};
function client(){return v110sb}
function modal(html){const d=document.createElement('dialog');d.className='v7-modal';d.innerHTML=`<div class="v7-modal-card">${html}</div>`;document.body.appendChild(d);d.showModal();d.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>d.remove());d.addEventListener('cancel',()=>d.remove());return d}
function toast(t,err=false){const el=$('#global-message');if(el){el.textContent=t;el.classList.toggle('error',err);setTimeout(()=>{if(el.textContent===t)el.textContent=''},5000)}else alert(t)}
function csv(name,rows){const text='\ufeff'+rows.map(r=>r.map(v=>`"${String(v??'').replaceAll('"','""')}"`).join(';')).join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([text],{type:'text/csv;charset=utf-8'}));a.download=name;a.click();URL.revokeObjectURL(a.href)}
function addMenu(){const nav=$('.sidebar nav');if(!nav||nav.querySelector('[data-section="cuotas"]'))return;const anchor=nav.querySelector('[data-section="finanzas"]');const html='<button data-section="cuotas">🗓️ Cuotas</button><button data-section="certificados">📄 Certificados</button><button data-section="libro-caja">📒 Libro de Caja</button><button data-section="informe-mensual">📊 Informe mensual</button>';
(anchor||nav.lastElementChild).insertAdjacentHTML(anchor?'beforebegin':'beforeend',html)}
async function settings(){const{data,error}=await client().from('configuracion_gestion').select('*').eq('id',1).single();if(error)throw error;return data}

let cuotas=[],cuotasDeuda=[],cuotasSeleccionadas=new Set();
const monthName=v=>{if(!v)return '';const [y,m]=v.slice(0,7).split('-');return new Date(Number(y),Number(m)-1,1).toLocaleDateString('es-CL',{month:'long',year:'numeric'})};
const phoneWA=v=>{const d=String(v||'').replace(/\D/g,'');if(!d)return '';if(d.startsWith('56')&&d.length>=11)return d;if(d.startsWith('9')&&d.length===9)return '56'+d;if(d.length===8)return '569'+d;return ''};
function debtFor(x){return cuotasDeuda.filter(d=>d.socio_id===x.socio_id&&d.estado==='pendiente'&&d.periodo<=($('#cuotas-month').value+'-01')).sort((a,b)=>a.periodo.localeCompare(b.periodo))}
function quotaVisual(x){const debt=debtFor(x),prior=debt.filter(d=>d.periodo<x.periodo);if(prior.length)return{key:'deuda_anterior',label:'Con deuda anterior',icon:'🔴',className:'deuda'};if(x.estado==='pendiente')return{key:'pendiente_mes',label:'Pendiente del mes',icon:'🟡',className:'pendiente-mes'};if(x.estado==='pagado')return{key:'al_dia',label:'Al día',icon:'🟢',className:'al-dia'};if(x.estado==='exento_incorporacion')return{key:'exento_incorporacion',label:'Exento',icon:'⚪',className:'exento'};return{key:x.estado,label:x.estado,icon:'⚪',className:'otro'}}
async function loadCuotas(){const m=$('#cuotas-month').value;if(!m)return;const current=m+'-01';const [currentRes,debtRes]=await Promise.all([
client().from('cuotas_socios').select('*,socios(id,numero_socio,nombre_completo,rut,fecha_ingreso,telefono,autoriza_whatsapp)').eq('periodo',current).order('socios(numero_socio)',{ascending:true}),
client().from('cuotas_socios').select('id,socio_id,periodo,estado,monto').eq('estado','pendiente').lte('periodo',current).order('periodo',{ascending:true})
]);if(currentRes.error)return toast('Cuotas: '+currentRes.error.message,true);if(debtRes.error)return toast('Deudas: '+debtRes.error.message,true);cuotas=currentRes.data||[];cuotasDeuda=debtRes.data||[];cuotasSeleccionadas.clear();renderCuotas()}
function setQuotaFilter(value){$('#cuotas-filter').value=value;renderCuotas()}
function renderCuotas(){const q=($('#cuotas-search').value||'').toLowerCase(),f=$('#cuotas-filter').value;const decorated=cuotas.map(x=>({...x,_visual:quotaVisual(x),_debt:debtFor(x)}));const rows=decorated.filter(x=>{const matchesStatus=f==='todos'||x.estado===f||x._visual.key===f;return matchesStatus&&`${x.socios?.numero_socio||''} ${x.socios?.nombre_completo||''} ${x.socios?.rut||''}`.toLowerCase().includes(q)});
const paid=decorated.filter(x=>x.estado==='pagado'),pending=decorated.filter(x=>x.estado==='pendiente'),upToDate=decorated.filter(x=>x._visual.key==='al_dia'),monthPending=decorated.filter(x=>x._visual.key==='pendiente_mes'),oldDebt=decorated.filter(x=>x._visual.key==='deuda_anterior'),exempt=decorated.filter(x=>x.estado==='exento_incorporacion'),cash=paid.filter(x=>x.medio_pago==='efectivo').reduce((a,x)=>a+Number(x.monto),0),bank=paid.filter(x=>x.medio_pago==='transferencia').reduce((a,x)=>a+Number(x.monto),0),expected=decorated.filter(x=>x.estado!=='exento_incorporacion'&&x.estado!=='anulado').reduce((a,x)=>a+Number(x.monto),0),collected=cash+bank,missing=Math.max(0,expected-collected),pct=expected?Math.round(collected/expected*100):0;
$('#cuotas-summary').innerHTML=`<button class="stat cuota-stat total" data-quota-filter="todos"><span>Socios del mes</span><strong>${cuotas.length}</strong></button><button class="stat cuota-stat al-dia" data-quota-filter="al_dia"><span>🟢 Al día</span><strong>${upToDate.length}</strong></button><button class="stat cuota-stat pendiente" data-quota-filter="pendiente_mes"><span>🟡 Pendientes del mes</span><strong>${monthPending.length}</strong></button><button class="stat cuota-stat deuda" data-quota-filter="deuda_anterior"><span>🔴 Con deuda anterior</span><strong>${oldDebt.length}</strong></button><button class="stat cuota-stat exento" data-quota-filter="exento_incorporacion"><span>⚪ Exentos</span><strong>${exempt.length}</strong></button><div class="stat cuota-money"><span>Total recaudado</span><strong>${money(collected)}</strong><small>Falta ${money(missing)}</small></div><div class="stat cuota-progress-card"><span>Cumplimiento</span><strong>${pct}%</strong><div class="cuota-progress"><i style="width:${Math.min(100,pct)}%"></i></div><small>${paid.length} cuotas pagadas</small></div>`;
$('#cuotas-body').innerHTML=rows.map(x=>{const canWA=phoneWA(x.socios?.telefono)&&x.socios?.autoriza_whatsapp;const debtMonths=x._debt.map(d=>monthName(d.periodo)).join(', ');const debtTotal=x._debt.reduce((a,d)=>a+Number(d.monto),0);return `<tr class="quota-row ${x._visual.className}"><td><input class="quota-select" type="checkbox" data-select-quota="${x.id}" ${cuotasSeleccionadas.has(x.id)?'checked':''} aria-label="Seleccionar a ${esc(x.socios?.nombre_completo)}"></td><td>${x.socios?.numero_socio||'—'}</td><td><strong>${x._visual.icon} ${esc(x.socios?.nombre_completo)}</strong><br><small>${esc(x.socios?.rut)}</small>${debtMonths?`<div class="quota-debt-detail">Debe: ${esc(debtMonths)} · <strong>${money(debtTotal)}</strong></div>`:''}</td><td><span class="v110-status ${x._visual.className}">${x._visual.label}</span><br><small>${x.estado==='pagado'?'Mes pagado':x.estado==='pendiente'?'Mes sin pagar':x.estado==='exento_incorporacion'?'No corresponde cobro':''}</small></td><td>${dateCL(x.fecha_pago)}</td><td>${esc(x.medio_pago||'—')}</td><td>${money(x.monto)}</td><td><div class="v110-table-actions">${x.estado==='pendiente'?`<button class="button primary" data-pay-quota="${x.id}">Registrar pago</button><button class="button secondary" data-pay-year="${x.socio_id}">Pago anual</button>`:''}${x.estado==='pagado'?`<button class="button danger" data-void-quota="${x.id}">Anular pago</button>`:''}${x._visual.key!=='al_dia'?`<button class="button whatsapp" data-wa-quota="${x.id}" ${canWA?'':'disabled title="Sin celular o sin autorización de WhatsApp"'}>📲 Recordar</button>`:''}<button class="button secondary" data-history="${x.socio_id}">Historial</button></div></td></tr>`}).join('')||'<tr><td colspan="8">No hay cuotas que coincidan con el filtro.</td></tr>';
$$('[data-quota-filter]').forEach(b=>b.onclick=()=>setQuotaFilter(b.dataset.quotaFilter));$$('[data-pay-quota]').forEach(b=>b.onclick=()=>payQuota(b.dataset.payQuota));$$('[data-pay-year]').forEach(b=>b.onclick=()=>payAnnualQuota(b.dataset.payYear));$$('[data-void-quota]').forEach(b=>b.onclick=()=>voidQuota(b.dataset.voidQuota));$$('[data-history]').forEach(b=>b.onclick=()=>quotaHistory(b.dataset.history));$$('[data-wa-quota]').forEach(b=>b.onclick=()=>openQuotaWhatsApp(b.dataset.waQuota));$$('[data-select-quota]').forEach(b=>b.onchange=()=>{b.checked?cuotasSeleccionadas.add(b.dataset.selectQuota):cuotasSeleccionadas.delete(b.dataset.selectQuota);updateQuotaSelection()});updateQuotaSelection()}
function updateQuotaSelection(){const count=cuotasSeleccionadas.size;const label=$('#cuotas-selected-count');if(label)label.textContent=count?`${count} seleccionado${count===1?'':'s'}`:'Ningún seleccionado';const send=$('#cuotas-whatsapp-selected');if(send)send.disabled=!count}
function selectQuotaDebtors(){cuotasSeleccionadas=new Set(cuotas.filter(x=>['pendiente_mes','deuda_anterior'].includes(quotaVisual(x).key)&&phoneWA(x.socios?.telefono)&&x.socios?.autoriza_whatsapp).map(x=>String(x.id)));renderCuotas()}
function quotaMessage(x){const debt=debtFor(x),months=debt.length?debt.map(d=>monthName(d.periodo)).join(', '):monthName(x.periodo),total=debt.length?debt.reduce((a,d)=>a+Number(d.monto),0):Number(x.monto);return `Hola ${x.socios?.nombre_completo||''}.\n\nEsperamos que se encuentre bien. Según nuestros registros, mantiene pendiente ${debt.length>1?'las cuotas de':'la cuota de'} ${months}, por un total de ${money(total)}.\n\nSi ya realizó el pago, por favor ignore este mensaje o envíenos el comprobante.\n\nMuchas gracias.\nJunta de Vecinos Villa El Trigal.`}
function openQuotaWhatsApp(id){const x=cuotas.find(q=>String(q.id)===String(id));if(!x)return;const phone=phoneWA(x.socios?.telefono);if(!phone||!x.socios?.autoriza_whatsapp)return toast('El vecino no tiene celular válido o no autorizó comunicaciones por WhatsApp.',true);window.SIGVE_WHATSAPP?.open?window.SIGVE_WHATSAPP.open(phone,quotaMessage(x)):window.open(`https://wa.me/${phone}?text=${encodeURIComponent(quotaMessage(x))}`,'_blank','noopener')}
function openBulkQuotaWhatsApp(){const selected=cuotas.filter(x=>cuotasSeleccionadas.has(String(x.id)));const valid=selected.filter(x=>phoneWA(x.socios?.telefono)&&x.socios?.autoriza_whatsapp);if(!valid.length)return toast('Selecciona vecinos con celular y autorización de WhatsApp.',true);const d=modal(`<h3>📲 Cobranza por WhatsApp</h3><p>Se prepararon <strong>${valid.length}</strong> mensajes individuales. Revisa y abre cada conversación antes de enviarla.</p><div class="quota-wa-list">${valid.map(x=>`<article><div><strong>${esc(x.socios?.nombre_completo)}</strong><br><small>${esc(phoneWA(x.socios?.telefono))} · ${quotaVisual(x).label}</small></div><button class="button whatsapp" data-open-wa="${x.id}">Abrir WhatsApp</button></article>`).join('')}</div><div class="actions"><button class="button secondary" data-close>Cerrar</button></div>`);d.querySelectorAll('[data-open-wa]').forEach(b=>b.onclick=()=>openQuotaWhatsApp(b.dataset.openWa))}
async function generateQuotas(){const m=$('#cuotas-month').value;if(!m)return;const{data,error}=await client().rpc('generar_cuotas_mes',{p_periodo:m+'-01'});if(error)return toast(error.message,true);toast(`Mes preparado. Se crearon ${data||0} registros nuevos.`);loadCuotas()}
async function payAnnualQuota(socioId){
 const year=Number(today().slice(0,4));
 const currentSocio=(cuotas.find(x=>String(x.socio_id)===String(socioId))||{}).socios;
 if(!currentSocio)return toast('No fue posible identificar al socio.',true);
 if(!confirm(`¿Preparar todas las cuotas pendientes de ${year} para ${currentSocio.nombre_completo}?\n\nLos meses ya pagados no se duplicarán.`))return;

 const prep=await client().rpc('preparar_cuotas_anuales_socio',{p_socio_id:socioId,p_anio:year});
 if(prep.error)return toast(prep.error.message,true);

 const from=`${year}-01-01`,to=`${year}-12-01`;
 const {data,error}=await client().from('cuotas_socios')
   .select('id,socio_id,periodo,monto,estado,socios(id,numero_socio,nombre_completo,rut)')
   .eq('socio_id',socioId).eq('estado','pendiente')
   .gte('periodo',from).lte('periodo',to)
   .order('periodo',{ascending:true});

 if(error)return toast(error.message,true);
 const selected=data||[];
 if(!selected.length)return toast(`El socio no tiene cuotas pendientes de ${year}.`);

 const total=selected.reduce((a,x)=>a+Number(x.monto||0),0);
 const d=modal(`<h3>Registrar pago anual ${year}</h3><p><strong>${esc(currentSocio.nombre_completo)}</strong> · Socio N° ${esc(currentSocio.numero_socio||'—')}</p><div class="caja-review">${selected.map(q=>`<div><span>${esc(monthName(q.periodo))}</span><strong>${money(q.monto)}</strong></div>`).join('')}<div class="total"><span>Total</span><strong>${money(total)}</strong></div></div><form><div class="v7-grid"><label>Fecha<input name="fecha" type="date" value="${today()}" required></label><label>Medio<select name="medio"><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option></select></label><label>Fondo<select name="fondo"><option value="caja">Caja chica</option><option value="banco">Cuenta bancaria</option></select></label><label>Referencia transferencia<input name="referencia"></label><label>Observaciones<textarea name="obs" placeholder="Pago anual ${year}"></textarea></label></div><div class="actions"><button class="button primary">Confirmar ${selected.length} cuota(s)</button><button type="button" class="button secondary" data-close>Cancelar</button></div></form>`);

 const f=d.querySelector('form');
 const sync=()=>{f.fondo.value=f.medio.value==='transferencia'?'banco':'caja';f.referencia.closest('label').style.display=f.medio.value==='transferencia'?'':'none'};
 f.medio.onchange=sync;sync();

 f.onsubmit=async e=>{
   e.preventDefault();
   const ids=selected.map(q=>q.id);
   const {data:count,error:payError}=await client().rpc('registrar_pago_cuotas_caja',{
     p_cuota_ids:ids,
     p_fecha:f.fecha.value,
     p_medio:f.medio.value,
     p_fondo:f.fondo.value,
     p_referencia:f.referencia.value||null,
     p_observaciones:f.obs.value||`Pago anual ${year}`
   });
   if(payError)return toast(payError.message,true);
   d.remove();
   toast(`Pago anual registrado: ${count||ids.length} cuota(s) ingresadas a Finanzas.`);
   loadCuotas();
 };
}

async function payQuota(id){const x=cuotas.find(q=>q.id===id);const d=modal(`<h3>Registrar pago de cuota</h3><p><strong>${esc(x?.socios?.nombre_completo)}</strong> · ${money(x?.monto)}</p><form><div class="v7-grid"><label>Fecha<input name="fecha" type="date" value="${today()}" required></label><label>Medio<select name="medio"><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option></select></label><label>Fondo<select name="fondo"><option value="caja">Caja chica</option><option value="banco">Cuenta bancaria</option></select></label><label>Referencia transferencia<input name="referencia"></label><label>Observaciones<textarea name="obs"></textarea></label></div><div class="actions"><button class="button primary">Guardar pago</button><button type="button" class="button secondary" data-close>Cancelar</button></div></form>`);d.querySelector('[name="medio"]').onchange=e=>d.querySelector('[name="fondo"]').value=e.target.value==='transferencia'?'banco':'caja';d.querySelector('form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget;const{error}=await client().rpc('registrar_pago_cuota',{p_cuota_id:id,p_fecha:f.fecha.value,p_medio:f.medio.value,p_fondo:f.fondo.value,p_referencia:f.referencia.value||null,p_observaciones:f.obs.value||null});if(error)return toast(error.message,true);d.remove();toast('Pago registrado e integrado con Finanzas.');loadCuotas()}}
async function voidQuota(id){const motivo=prompt('Motivo de la anulación:');if(motivo===null)return;const{error}=await client().rpc('anular_pago_cuota',{p_cuota_id:id,p_motivo:motivo||'Sin motivo informado'});if(error)return toast(error.message,true);toast('Pago anulado y movimiento financiero reversado.');loadCuotas()}
async function quotaHistory(socioId){const{data,error}=await client().from('cuotas_socios').select('*').eq('socio_id',socioId).order('periodo',{ascending:false});if(error)return toast(error.message,true);modal(`<h3>Historial de cuotas</h3><div class="v7-table-wrap"><table class="v7-table"><thead><tr><th>Mes</th><th>Estado</th><th>Medio</th><th>Monto</th></tr></thead><tbody>${(data||[]).map(x=>`<tr><td>${monthName(x.periodo)}</td><td>${esc(x.estado)}</td><td>${esc(x.medio_pago||'—')}</td><td>${money(x.monto)}</td></tr>`).join('')}</tbody></table></div><div class="actions"><button class="button secondary" data-close>Cerrar</button></div>`)}

let certs=[];
async function loadCerts(){const{data,error}=await client().from('certificados_emitidos').select('*').order('folio',{ascending:false}).limit(500);if(error)return toast('Certificados: '+error.message,true);certs=data||[];renderCerts()}
function renderCerts(){const q=($('#cert-search').value||'').toLowerCase(),rows=certs.filter(x=>`${x.folio||x.numero||''} ${x.nombre} ${x.rut}`.toLowerCase().includes(q));const paid=certs.filter(x=>x.estado_pago==='pagado');$('#cert-summary').innerHTML=`<div class="stat"><span>Emitidos</span><strong>${certs.length}</strong></div><div class="stat"><span>Pagados</span><strong>${paid.length}</strong></div><div class="stat"><span>Pendientes</span><strong>${certs.filter(x=>x.estado_pago==='pendiente').length}</strong></div><div class="stat"><span>Recaudado</span><strong>${money(paid.reduce((a,x)=>a+Number(x.valor),0))}</strong></div>`;
$('#cert-body').innerHTML=rows.map(x=>`<tr><td><strong>${String(x.folio||x.numero||0).padStart(5,'0')}</strong></td><td>${dateCL(x.fecha)}</td><td>${esc(x.nombre)}<br><small>${esc(x.rut)}</small></td><td>${esc(x.direccion)}</td><td><span class="v110-status ${x.estado_pago}">${esc(x.estado_pago)}</span></td><td>${money(x.valor)}</td><td><button class="button secondary" data-print-cert="${x.id}">Imprimir</button></td></tr>`).join('')||'<tr><td colspan="7">Sin certificados.</td></tr>';$$('[data-print-cert]').forEach(b=>b.onclick=()=>printCert(certs.find(x=>x.id===b.dataset.printCert)))}
async function newCert(){const [st,so]=await Promise.all([settings(),client().from('socios').select('id,numero_socio,nombre_completo,rut,direccion,telefono,correo').eq('estado','activo').order('nombre_completo')]);const opts=(so.data||[]).map(x=>`<option value="${x.id}">${esc(x.nombre_completo)} · N° ${x.numero_socio||'—'}</option>`).join('');const d=modal(`<h3>Emitir certificado de residencia</h3><form><div class="v7-grid"><label>Vincular socio<select name="socio"><option value="">No es socio / ingreso manual</option>${opts}</select></label><label>Fecha<input name="fecha" type="date" value="${today()}" required></label><label>Nombre completo<input name="nombre" required></label><label>RUT<input name="rut" required></label><label>Dirección<input name="direccion" required></label><label>Teléfono<input name="telefono"></label><label>Correo<input name="correo" type="email"></label><label>Destino / institución<input name="destino"></label><label>Estado de pago<select name="estado"><option value="pagado">Pagado</option><option value="pendiente">Pendiente</option><option value="exento">Exento</option></select></label><label>Medio<select name="medio"><option value="efectivo">Efectivo</option><option value="transferencia">Transferencia</option></select></label><label>Fondo<select name="fondo"><option value="caja">Caja chica</option><option value="banco">Cuenta bancaria</option></select></label><label>Referencia<input name="referencia"></label><label>Valor<input value="${st.valor_certificado}" disabled></label><label>Observaciones<textarea name="obs"></textarea></label></div><div class="actions"><button class="button primary">Emitir certificado</button><button type="button" class="button secondary" data-close>Cancelar</button></div></form>`);const f=d.querySelector('form');f.socio.onchange=()=>{const x=(so.data||[]).find(s=>s.id===f.socio.value);if(x){f.nombre.value=x.nombre_completo;f.rut.value=x.rut;f.direccion.value=x.direccion;f.telefono.value=x.telefono||'';f.correo.value=x.correo||''}};f.medio.onchange=()=>f.fondo.value=f.medio.value==='transferencia'?'banco':'caja';f.onsubmit=async e=>{e.preventDefault();const p={p_socio_id:f.socio.value||null,p_nombre:f.nombre.value,p_rut:f.rut.value,p_direccion:f.direccion.value,p_telefono:f.telefono.value,p_correo:f.correo.value,p_destino:f.destino.value,p_fecha:f.fecha.value,p_estado_pago:f.estado.value,p_medio:f.medio.value,p_fondo:f.fondo.value,p_referencia:f.referencia.value,p_observaciones:f.obs.value};const{data,error}=await client().rpc('registrar_certificado_v110',p);if(error)return toast(error.message,true);d.remove();toast(`Certificado folio ${String(data).padStart(5,'0')} emitido.`);loadCerts()}}
function printCert(x){const w=window.open('','_blank');w.document.write(`<html><head><title>Certificado ${x.folio}</title><style>body{font-family:Arial;padding:2cm;line-height:1.7}.head{text-align:center}.head img{width:90px}.folio{text-align:right}h1{font-size:22px}.sign{margin-top:100px;text-align:center}</style></head><body><div class="folio">Folio N° ${String(x.folio||x.numero).padStart(5,'0')}</div><div class="head"><img src="assets/logo.svg"><h1>JUNTA DE VECINOS VILLA EL TRIGAL</h1><h2>CERTIFICADO DE RESIDENCIA</h2></div><p>Se certifica que <strong>${esc(x.nombre)}</strong>, RUT <strong>${esc(x.rut)}</strong>, acredita domicilio en <strong>${esc(x.direccion)}</strong>.</p><p>Se extiende el presente certificado a petición de la persona interesada${x.destino?` para ser presentado en <strong>${esc(x.destino)}</strong>`:''}.</p><p>San Antonio, ${dateCL(x.fecha)}.</p><div class="sign">_________________________________<br>Firma y timbre de la Junta de Vecinos</div><script>window.onload=()=>window.print()<\/script></body></html>`);w.document.close()}

let ledger=[];
async function loadLedger(){const from=$('#libro-from').value,to=$('#libro-to').value;let q=client().from('libro_caja').select('*').order('fecha').order('creado_en');if(from)q=q.gte('fecha',from);if(to)q=q.lte('fecha',to);const{data,error}=await q;if(error)return toast('Libro de Caja: '+error.message,true);ledger=data||[];const inc=ledger.filter(x=>x.tipo==='ingreso').reduce((a,x)=>a+Number(x.monto),0),out=ledger.filter(x=>x.tipo==='gasto').reduce((a,x)=>a+Number(x.monto),0);$('#libro-summary').innerHTML=`<div class="stat"><span>Ingresos</span><strong>${money(inc)}</strong></div><div class="stat"><span>Egresos</span><strong>${money(out)}</strong></div><div class="stat"><span>Resultado período</span><strong>${money(inc-out)}</strong></div><div class="stat"><span>Saldo acumulado final</span><strong>${money(ledger.at(-1)?.saldo_acumulado||0)}</strong></div>`;$('#libro-body').innerHTML=ledger.map(x=>`<tr><td>${dateCL(x.fecha)}</td><td>${esc(x.concepto)}</td><td>${x.tipo==='ingreso'?money(x.monto):'—'}</td><td>${x.tipo==='gasto'?money(x.monto):'—'}</td><td>${esc(x.fondo)}</td><td><strong>${money(x.saldo_acumulado)}</strong></td></tr>`).join('')||'<tr><td colspan="6">Sin movimientos.</td></tr>'}
function exportLedger(){csv(`libro-caja-${$('#libro-from').value}-${$('#libro-to').value}.csv`,[['Fecha','Concepto','Ingreso','Egreso','Fondo','Saldo'],...ledger.map(x=>[x.fecha,x.concepto,x.tipo==='ingreso'?x.monto:'',x.tipo==='gasto'?x.monto:'',x.fondo,x.saldo_acumulado])])}
async function officialReport(){const m=$('#official-month').value;if(!m)return toast('Selecciona el mes del informe.',true);const b=monthBounds(m),st=await settings();const{data,error}=await client().from('movimientos_financieros').select('*').gte('fecha',b.from).lte('fecha',b.to).eq('anulado',false).in('tipo',['ingreso','gasto']).order('fecha',{ascending:true}).order('creado_en',{ascending:true});if(error)return toast(error.message,true);const rows=data||[],inc=rows.filter(x=>x.tipo==='ingreso'),out=rows.filter(x=>x.tipo==='gasto');const detail=a=>a.map(x=>[x.concepto||x.categoria||'Sin descripción',Number(x.monto),x.fecha]);const ti=inc.reduce((a,x)=>a+Number(x.monto),0),to=out.reduce((a,x)=>a+Number(x.monto),0);const before=await client().from('movimientos_financieros').select('tipo,monto').lt('fecha',b.from).eq('anulado',false).in('tipo',['ingreso','gasto']);const opening=(before.data||[]).reduce((a,x)=>a+(x.tipo==='ingreso'?Number(x.monto):-Number(x.monto)),0),closing=opening+ti-to;const label=new Date(b.from+'T12:00:00').toLocaleDateString('es-CL',{month:'long',year:'numeric'});const renderDetail=a=>a.length?detail(a).map(([concept,mount,date])=>`<tr><td class="report-date">${dateCL(date)}</td><td>${esc(concept)}</td><td class="report-amount">${money(mount)}</td></tr>`).join(''):'<tr><td colspan="3">Sin movimientos.</td></tr>';$('#official-report').innerHTML=`<article class="report-letter"><div class="report-letter-header"><img src="assets/logo.svg"><div><h2>${esc(st.nombre_organizacion||'Junta de Vecinos Villa El Trigal')}</h2><h3>Informe Financiero Mensual · ${label}</h3></div></div><p>Saldo inicial: <strong>${money(opening)}</strong></p><h3>Ingresos</h3><table class="v7-table report-detail-table"><thead><tr><th>Fecha</th><th>Detalle</th><th>Monto</th></tr></thead><tbody>${renderDetail(inc)}<tr><th colspan="2">Total ingresos</th><th class="report-amount">${money(ti)}</th></tr></tbody></table><h3>Egresos</h3><table class="v7-table report-detail-table"><thead><tr><th>Fecha</th><th>Detalle</th><th>Monto</th></tr></thead><tbody>${renderDetail(out)}<tr><th colspan="2">Total egresos</th><th class="report-amount">${money(to)}</th></tr></tbody></table><h3>Resumen</h3><table class="v7-table"><tbody><tr><td>Resultado del mes</td><td class="report-amount">${money(ti-to)}</td></tr><tr><th>Saldo final acumulado</th><th class="report-amount">${money(closing)}</th></tr></tbody></table><div class="report-signatures"><div>Presidente(a)</div><div>Secretario(a)</div><div>Tesorero(a)</div></div></article>`}
async function printOfficialReport(){
  // Abrir la ventana inmediatamente mantiene el gesto del clic y evita bloqueos del navegador.
  const printWindow=window.open('','_blank');
  if(!printWindow){
    return toast('El navegador bloqueó la ventana de impresión. Habilita las ventanas emergentes para este sitio.',true);
  }
  printWindow.document.write('<!doctype html><html lang="es"><head><meta charset="utf-8"><title>Preparando informe…</title></head><body style="font-family:Arial,sans-serif;padding:24px">Preparando informe mensual…</body></html>');
  printWindow.document.close();

  try{
    if(!$('#official-report .report-letter')) await officialReport();
    const report=$('#official-report .report-letter');
    if(!report){
      printWindow.close();
      return toast('No fue posible generar el informe mensual.',true);
    }

    const base=document.baseURI;
    const month=$('#official-month').value||today().slice(0,7);
    printWindow.document.open();
    printWindow.document.write(`<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<base href="${esc(base)}">
<title>Informe financiero mensual ${esc(month)}</title>
<style>
  @page{size:letter;margin:12mm}
  *{box-sizing:border-box}
  html,body{margin:0;padding:0;background:#fff;color:#111;font-family:Arial,sans-serif;font-size:12px}
  .report-letter{width:100%;margin:0;padding:0;border:0;background:#fff;color:#111}
  .report-letter-header{display:flex;align-items:center;gap:14px;border-bottom:2px solid #222;padding-bottom:12px;margin-bottom:14px}
  .report-letter-header img{width:64px;height:64px;object-fit:contain}
  h2{margin:0 0 5px;font-size:19px} h3{margin:14px 0 7px;font-size:15px;page-break-after:avoid}
  p{margin:8px 0}
  table{width:100%;border-collapse:collapse;margin:7px 0 15px;page-break-inside:auto}
  th,td{border:1px solid #aaa;padding:6px 8px;text-align:left;vertical-align:top}
  th{background:#f1f1f1;font-weight:700}
  tr{page-break-inside:avoid;page-break-after:auto}
  .report-date{width:95px;white-space:nowrap}
  .report-amount{text-align:right;white-space:nowrap;width:115px}
  .report-signatures{display:grid;grid-template-columns:repeat(3,1fr);gap:28px;margin-top:70px;text-align:center}
  .report-signatures div{border-top:1px solid #333;padding-top:6px}
  @media print{html,body{width:100%}.report-letter{width:100%}}
</style>
</head>
<body>${report.outerHTML}</body>
</html>`);
    printWindow.document.close();

    const images=[...printWindow.document.images];
    await Promise.all(images.map(img=>img.complete?Promise.resolve():new Promise(resolve=>{
      img.addEventListener('load',resolve,{once:true});
      img.addEventListener('error',resolve,{once:true});
    })));

    setTimeout(()=>{
      printWindow.focus();
      printWindow.print();
    },250);
  }catch(error){
    try{printWindow.close()}catch(_){ }
    console.error('Error al imprimir informe mensual:',error);
    toast('No fue posible preparar la impresión del informe mensual.',true);
  }
}

function bind(){addMenu();const m=today().slice(0,7);$('#cuotas-month').value=m;$('#official-month').value=m;$('#libro-from').value=m+'-01';$('#libro-to').value=today();$('#cuotas-generate').onclick=generateQuotas;$('#cuotas-prev').onclick=()=>{$('#cuotas-month').value=monthMove($('#cuotas-month').value,-1);loadCuotas()};$('#cuotas-next').onclick=()=>{$('#cuotas-month').value=monthMove($('#cuotas-month').value,1);loadCuotas()};$('#cuotas-month').onchange=loadCuotas;$('#cuotas-search').oninput=renderCuotas;$('#cuotas-filter').onchange=renderCuotas;$('#cuotas-select-debtors').onclick=selectQuotaDebtors;$('#cuotas-clear-selection').onclick=()=>{cuotasSeleccionadas.clear();renderCuotas()};$('#cuotas-whatsapp-selected').onclick=openBulkQuotaWhatsApp;$('#new-certificado').onclick=newCert;$('#cert-search').oninput=renderCerts;$('#libro-load').onclick=loadLedger;$('#libro-export').onclick=exportLedger;$('#official-generate').onclick=officialReport;$('#official-print').onclick=printOfficialReport;document.addEventListener('click',e=>{const b=e.target.closest('[data-section]');if(!b)return;const k=b.dataset.section;if(!['cuotas','certificados','libro-caja','informe-mensual'].includes(k))return;document.querySelectorAll('[data-section]').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('.admin-section').forEach(s=>s.hidden=s.id!==`section-${k}`);$('#page-title').textContent=b.textContent.trim();setTimeout(()=>({cuotas:loadCuotas,certificados:loadCerts,'libro-caja':loadLedger,'informe-mensual':officialReport}[k]?.()),30)},true)}
window.addEventListener('load',()=>setTimeout(bind,300));
})();
