(() => {
const cfg=window.PORTAL_CONFIG||{}; const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
const $=id=>document.getElementById(id); const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const state={user:null,admin:null,currentImages:{noticias:[],galeria:[],actividades:[]}};
const defs={
 anuncios:{title:'Anuncios',fields:[['titulo','Título','text',1],['categoria','Categoría','select',0,['reunion','urgente','actividad','informacion','seguridad','servicio']],['descripcion','Descripción','textarea',1],['fecha_evento','Fecha del evento','date'],['hora_evento','Hora','time'],['lugar','Lugar','text'],['fecha_vencimiento','Vence el','datetime-local'],['destacado','Destacado','checkbox'],['publicado','Publicado','checkbox']]},
 noticias:{title:'Noticias',fields:[['titulo','Título','text',1],['contenido','Texto de la noticia','textarea',1],['fecha_publicacion','Fecha','date'],['imagenes','Fotografías (opcional, máximo 5)','multiimage'],['destacado','Destacada','checkbox'],['publicado','Publicada','checkbox']]},
 actividades:{title:'Actividades realizadas',fields:[['titulo','Nombre de la actividad','text',1],['descripcion','¿Qué se realizó?','textarea',1],['fecha','Fecha de realización','date',1],['imagen_url','Fotografía','image',1],['publicado','Publicada','checkbox']]},
 galeria:{title:'Galería',fields:[['titulo','Título del álbum','text',1],['descripcion','Descripción breve','textarea'],['fecha','Fecha de la actividad','date'],['imagenes','Fotografías','multiimage',1],['publicado','Publicado','checkbox']]}
};
function message(t,bad=false){$('global-message').textContent=t;$('global-message').className='form-message '+(bad?'error':'success');setTimeout(()=>{$('global-message').textContent=''},5000)}
function fieldHtml(f){const[n,l,t,r,opts]=f;if(t==='textarea')return `<label>${l}<textarea name="${n}" ${r?'required':''}></textarea></label>`;if(t==='select')return `<label>${l}<select name="${n}">${opts.map(o=>`<option value="${o}">${o}</option>`).join('')}</select></label>`;if(t==='checkbox')return `<label class="check"><input name="${n}" type="checkbox" checked> ${l}</label>`;if(t==='image')return `<label>${l}<input name="${n}" type="file" accept="image/*" ${r?'required':''}><small class="current-image"></small></label>`;if(t==='multiimage')return `<label>${l}<input name="${n}" type="file" accept="image/*" multiple ${r?'required':''}><small class="help">Puedes seleccionar hasta 5 imágenes. <span class="image-count">0 de 5</span></small><div class="multi-preview"></div></label>`;return `<label>${l}<input name="${n}" type="${t}" ${r?'required':''}></label>`}
function buildForms(){for(const[k,d]of Object.entries(defs)){ $(`form-${k}`).innerHTML=`<section class="panel"><h3>Nueva publicación</h3><form data-table="${k}"><input type="hidden" name="id"><div class="form-grid">${d.fields.map(fieldHtml).join('')}</div><div class="actions"><button class="button primary" type="submit">Guardar</button><button class="button secondary cancel" type="button" hidden>Cancelar edición</button></div></form></section>`;}}
async function verify(){const{data:{session}}=await sb.auth.getSession();if(!session)return showLogin();state.user=session.user;const{data,error}=await sb.from('administradores').select('*').eq('user_id',state.user.id).eq('activo',true).single();if(error||!data){await sb.auth.signOut();$('login-message').textContent='Este usuario no tiene permisos de administrador.';return showLogin()}state.admin=data;showAdmin();await loadAll()}
function showLogin(){$('login-view').hidden=false;$('admin-view').hidden=true} function showAdmin(){$('login-view').hidden=true;$('admin-view').hidden=false;$('admin-name').textContent=state.admin?.nombre||state.user.email}
async function upload(file,folder){if(!file)return null;const ext=(file.name.split('.').pop()||'jpg').toLowerCase();const path=`${folder}/${Date.now()}-${crypto.randomUUID()}.${ext}`;const{error}=await sb.storage.from('portal-imagenes').upload(path,file,{cacheControl:'3600',upsert:false});if(error)throw error;return sb.storage.from('portal-imagenes').getPublicUrl(path).data.publicUrl}
async function uploadMany(files,folder){const arr=[...files].slice(0,5);return Promise.all(arr.map(f=>upload(f,folder)))}
function normalizeImages(row){if(Array.isArray(row.imagenes))return row.imagenes.filter(Boolean);if(row.imagen_url)return[row.imagen_url];return[]}
async function loadTable(table){const order=table==='actividades'?'fecha':table==='noticias'?'fecha_publicacion':table==='galeria'?'fecha':'creado_en';const{data,error}=await sb.from(table).select('*').order(order,{ascending:false,nullsFirst:false});if(error){message(error.message,true);return}renderList(table,data||[]);$(`stat-${table}`)&&($(`stat-${table}`).textContent=(data||[]).length)}
function renderList(table,rows){const el=$(`list-${table}`);if(!rows.length){el.innerHTML='<div class="panel empty">Todavía no hay publicaciones.</div>';return}el.innerHTML=rows.map(x=>{const imgs=normalizeImages(x);return `<article class="item"><div>${imgs[0]?`<img class="thumb" src="${esc(imgs[0])}" alt="">`:''}<h3>${esc(x.titulo||'Sin título')}</h3><p>${esc(x.descripcion||x.contenido||'')}</p>${imgs.length?`<div class="item-meta">${imgs.length} foto${imgs.length===1?'':'s'}</div>`:''}<div class="item-meta">${x.publicado===false?'Borrador':'Publicado'}</div></div><div class="actions"><button class="button secondary" data-edit="${x.id}">Editar</button><button class="button danger" data-delete="${x.id}">Eliminar</button></div></article>`}).join('');el.querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editRow(table,rows.find(r=>r.id===b.dataset.edit)));el.querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>deleteRow(table,b.dataset.delete))}
function renderPreviews(form,table){const box=form.querySelector('.multi-preview');if(!box)return;const imgs=state.currentImages[table]||[];box.innerHTML=imgs.map((src,i)=>`<figure><img src="${esc(src)}" alt=""><button type="button" data-remove="${i}" aria-label="Quitar imagen">×</button></figure>`).join('');const count=form.querySelector('.image-count');if(count)count.textContent=`${imgs.length} de 5`;box.querySelectorAll('[data-remove]').forEach(b=>b.onclick=()=>{imgs.splice(Number(b.dataset.remove),1);renderPreviews(form,table)})}
function bindMultiInputs(){document.querySelectorAll('input[type=file][multiple]').forEach(input=>input.onchange=()=>{const form=input.form,table=form.dataset.table;const existing=state.currentImages[table]||[];const selected=[...input.files];if(existing.length+selected.length>5){message('Solo puedes usar hasta 5 imágenes por publicación.',true);input.value='';return}selected.forEach(file=>existing.push(URL.createObjectURL(file)));state.currentImages[table]=existing;renderPreviews(form,table)})}
function editRow(table,row){const form=document.querySelector(`form[data-table="${table}"]`);form.id.value=row.id;state.currentImages[table]=normalizeImages(row);for(const f of defs[table].fields){const[n,,t]=f;const input=form.elements[n];if(!input)continue;if(t==='checkbox')input.checked=!!row[n];else if(t==='image'){input.required=false;input.closest('label').querySelector('.current-image').textContent=row[n]?'Imagen actual cargada':''}else if(t==='multiimage'){input.required=false;renderPreviews(form,table)}else if(t==='date'&&row[n])input.value=String(row[n]).slice(0,10);else if(t==='datetime-local'&&row[n])input.value=String(row[n]).slice(0,16);else input.value=row[n]??''}form.closest('.panel').querySelector('h3').textContent='Editar publicación';form.querySelector('.cancel').hidden=false;form.scrollIntoView({behavior:'smooth'})}
function resetForm(form){const table=form.dataset.table;form.reset();form.id.value='';state.currentImages[table]=[];renderPreviews(form,table);form.closest('.panel').querySelector('h3').textContent='Nueva publicación';form.querySelector('.cancel').hidden=true;form.querySelectorAll('input[type=file]').forEach(i=>i.required=!!defs[table].fields.find(f=>f[0]===i.name)?.[3])}
async function saveForm(form){
  const table=form.dataset.table;
  const button=form.querySelector('button[type="submit"]');
  const originalText=button.textContent;
  button.disabled=true;
  button.textContent='Guardando…';

  try{
    /* Noticias usa una ruta dedicada para evitar incompatibilidades con campos antiguos. */
    if(table==='noticias'){
      const titulo=form.elements.titulo.value.trim();
      const contenido=form.elements.contenido.value.trim();
      if(!titulo||!contenido)throw new Error('Escribe el título y el texto de la noticia.');

      const existing=normalizeBlobUrls(state.currentImages.noticias);
      const files=[...(form.elements.imagenes?.files||[])].slice(0,Math.max(0,5-existing.length));
      const uploaded=files.length?await uploadMany(files,'noticias'):[];
      const imagenes=[...existing,...uploaded].slice(0,5);
      const fecha=form.elements.fecha_publicacion.value || new Date().toISOString().slice(0,10);

      const payload={
        titulo,
        resumen:contenido.slice(0,500),
        contenido,
        categoria:'Comunidad',
        imagen_url:imagenes[0]||null,
        imagenes,
        publicado:form.elements.publicado.checked,
        destacado:form.elements.destacado.checked,
        fecha_publicacion:fecha,
        creado_por:state.user.id
      };

      const id=form.elements.id.value;
      let result;
      if(id){
        delete payload.creado_por;
        result=await sb.from('noticias').update(payload).eq('id',id).select('*').single();
      }else{
        result=await sb.from('noticias').insert([payload]).select('*').single();
      }
      if(result.error)throw result.error;
      console.info('Noticia guardada correctamente',result.data);
      message(id?'Noticia actualizada correctamente.':'Noticia publicada correctamente.');
      resetForm(form);
      await loadTable('noticias');
      return;
    }

    const fd=new FormData(form);
    const data={};
    for(const[n,,t]of defs[table].fields){
      if(t==='checkbox')data[n]=form.elements[n].checked;
      else if(t==='image'){
        const file=form.elements[n].files[0];
        if(file)data[n]=await upload(file,table);
      }else if(t==='multiimage'){
        // Las imágenes se procesan más abajo.
      }else data[n]=fd.get(n)||null;
    }

    if(defs[table].fields.some(f=>f[2]==='multiimage')){
      const input=form.elements.imagenes;
      const old=normalizeBlobUrls(state.currentImages[table]);
      const files=[...input.files].slice(0,5-old.length);
      const uploaded=files.length?await uploadMany(files,table):[];
      data.imagenes=[...old,...uploaded].slice(0,5);
      data.imagen_url=data.imagenes[0]||null;
      if(table==='galeria'&&!data.imagenes.length)throw new Error('Debes agregar al menos una fotografía al álbum.');
    }

    data.creado_por=state.user.id;
    const id=form.elements.id.value;
    let result;
    if(id){
      delete data.creado_por;
      if(!data.imagen_url&&table==='actividades')delete data.imagen_url;
      result=await sb.from(table).update(data).eq('id',id).select('id').single();
    }else{
      result=await sb.from(table).insert([data]).select('id').single();
    }
    if(result.error)throw result.error;
    message('Contenido guardado correctamente.');
    resetForm(form);
    await loadTable(table);
  }catch(err){
    const detail=err?.message||String(err);
    console.error('Error guardando',table,err);
    message('No se pudo guardar: '+detail,true);
    alert('No se pudo guardar la publicación.\n\nDetalle: '+detail);
  }finally{
    button.disabled=false;
    button.textContent=originalText;
  }
}
function normalizeBlobUrls(arr){return(arr||[]).filter(x=>!String(x).startsWith('blob:'))}
async function deleteRow(table,id){if(!confirm('¿Eliminar esta publicación?'))return;const{error}=await sb.from(table).delete().eq('id',id);if(error)return message(error.message,true);message('Publicación eliminada.');loadTable(table)}
async function loadConfig(){const{data,error}=await sb.from('configuracion_portal').select('*').eq('id',1).maybeSingle();if(error)return message(error.message,true);if(!data)return;const f=$('config-form');['titulo_portada','texto_portada','whatsapp','telefono','correo','direccion','periodo_directiva'].forEach(k=>f.elements[k].value=data[k]||'');f.dataset.portada=data.portada_url||'';$('portada-actual').textContent=data.portada_url?'Foto de portada actual cargada':''}
$('config-form').onsubmit=async e=>{e.preventDefault();try{const f=e.currentTarget;const d=Object.fromEntries(new FormData(f));delete d.portada;const file=f.elements.portada.files[0];d.portada_url=file?await upload(file,'configuracion'):f.dataset.portada||null;d.actualizado_por=state.user.id;const{error}=await sb.from('configuracion_portal').upsert({id:1,...d});if(error)throw error;f.dataset.portada=d.portada_url||'';message('Datos del portal actualizados.')}catch(err){message(err.message||String(err),true)}};
async function loadDirectiva(){const{data,error}=await sb.from('directiva').select('*').order('orden',{ascending:true});if(error)return message(error.message,true);const el=$('list-directiva');el.innerHTML=(data||[]).map(x=>`<article class="item"><div><h3>${esc(x.cargo)} · ${esc(x.nombre)}</h3><p>${esc(x.descripcion||'')}</p>${x.telefono?`<p><strong>Teléfono:</strong> ${esc(x.telefono)}</p>`:''}<div class="item-meta">${x.activo?'Visible':'Oculto'} · Orden ${x.orden}</div></div><div class="actions"><button class="button secondary" data-edit-dir="${x.id}">Editar</button><button class="button danger" data-delete-dir="${x.id}">Eliminar</button></div></article>`).join('')||'<div class="panel empty">No hay integrantes registrados.</div>';el.querySelectorAll('[data-edit-dir]').forEach(b=>b.onclick=()=>editDirectiva(data.find(x=>x.id===b.dataset.editDir)));el.querySelectorAll('[data-delete-dir]').forEach(b=>b.onclick=()=>deleteDirectiva(b.dataset.deleteDir))}
function editDirectiva(x){const f=$('directiva-form');['id','cargo','nombre','telefono','descripcion','orden'].forEach(k=>f.elements[k].value=x[k]??'');f.elements.activo.checked=!!x.activo;$('cancel-directiva').hidden=false;f.scrollIntoView({behavior:'smooth'})}
function resetDirectiva(){const f=$('directiva-form');f.reset();f.id.value='';f.orden.value=1;f.activo.checked=true;$('cancel-directiva').hidden=true}
$('directiva-form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget,d=Object.fromEntries(new FormData(f));d.activo=f.activo.checked;d.orden=Number(d.orden||1);const id=d.id;delete d.id;d.actualizado_por=state.user.id;const q=id?sb.from('directiva').update(d).eq('id',id):sb.from('directiva').insert(d);const{error}=await q;if(error)return message(error.message,true);message('Integrante guardado.');resetDirectiva();loadDirectiva()};$('cancel-directiva').onclick=resetDirectiva;
async function deleteDirectiva(id){if(!confirm('¿Eliminar este integrante?'))return;const{error}=await sb.from('directiva').delete().eq('id',id);if(error)return message(error.message,true);loadDirectiva()}
async function uploadDocument(file,isPublic){const bucket=isPublic?'documentos-publicos':'documentos-privados';const safe=(file.name||'documento').replace(/[^a-zA-Z0-9._-]+/g,'-');const path=`${Date.now()}-${crypto.randomUUID()}-${safe}`;const{error}=await sb.storage.from(bucket).upload(path,file,{cacheControl:'3600',upsert:false,contentType:file.type||undefined});if(error)throw error;let url=null;if(isPublic)url=sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;return{bucket,path,url}}
async function loadDocumentos(){const{data,error}=await sb.from('documentos').select('*').order('creado_en',{ascending:false});if(error)return message(error.message,true);$('stat-documentos')&&($('stat-documentos').textContent=(data||[]).length);const el=$('list-documentos');el.innerHTML=(data||[]).map(x=>`<article class="item"><div><h3>${x.es_publico?'🌐':'🔒'} ${esc(x.titulo)}</h3><p>${esc(x.descripcion||'')}</p><div class="item-meta">${esc(x.categoria||'Documento')} · ${x.publicado?'Publicado':'Oculto'} · ${esc(x.nombre_archivo||'')}</div></div><div class="actions"><button class="button secondary" data-open-doc="${x.id}">Abrir</button><button class="button secondary" data-edit-doc="${x.id}">Editar</button><button class="button danger" data-delete-doc="${x.id}">Eliminar</button></div></article>`).join('')||'<div class="panel empty">No hay documentos registrados.</div>';el.querySelectorAll('[data-edit-doc]').forEach(b=>b.onclick=()=>editDocumento(data.find(x=>x.id===b.dataset.editDoc)));el.querySelectorAll('[data-delete-doc]').forEach(b=>b.onclick=()=>deleteDocumento(data.find(x=>x.id===b.dataset.deleteDoc)));el.querySelectorAll('[data-open-doc]').forEach(b=>b.onclick=()=>openDocumento(data.find(x=>x.id===b.dataset.openDoc)))}
async function openDocumento(x){if(x.es_publico&&x.archivo_url)return window.open(x.archivo_url,'_blank','noopener');const{data,error}=await sb.storage.from(x.bucket_nombre).createSignedUrl(x.archivo_path,120);if(error)return message(error.message,true);window.open(data.signedUrl,'_blank','noopener')}
function editDocumento(x){const f=$('documentos-form');f.id.value=x.id;f.bucket_actual.value=x.bucket_nombre||'';['titulo','categoria','descripcion','fecha_documento'].forEach(k=>f.elements[k].value=x[k]??'');f.es_publico.checked=!!x.es_publico;f.publicado.checked=!!x.publicado;f.archivo.required=false;f.dataset.publico=String(!!x.es_publico);$('documento-actual').textContent=`Archivo actual: ${x.nombre_archivo||'documento cargado'}`;$('cancel-documento').hidden=false;f.scrollIntoView({behavior:'smooth'})}
function resetDocumento(){const f=$('documentos-form');f.reset();f.id.value='';f.bucket_actual.value='';f.archivo.required=true;f.es_publico.checked=true;f.publicado.checked=true;f.dataset.publico='';$('documento-actual').textContent='';$('cancel-documento').hidden=true}
$('documentos-form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget;try{const id=f.id.value;const isPublic=f.es_publico.checked;const oldPublic=f.dataset.publico===''?isPublic:f.dataset.publico==='true';const file=f.archivo.files[0];if(id&&oldPublic!==isPublic&&!file)throw new Error('Al cambiar un documento entre público y privado debes seleccionar nuevamente el archivo, para mantener la seguridad.');const data={titulo:f.titulo.value.trim(),categoria:f.categoria.value,descripcion:f.descripcion.value.trim()||null,fecha_documento:f.fecha_documento.value||null,es_publico:isPublic,publicado:f.publicado.checked,actualizado_por:state.user.id};if(file){const up=await uploadDocument(file,isPublic);data.bucket_nombre=up.bucket;data.archivo_path=up.path;data.archivo_url=up.url;data.nombre_archivo=file.name;data.mime_type=file.type||null}else if(!id)throw new Error('Debes seleccionar un archivo.');const q=id?sb.from('documentos').update(data).eq('id',id):sb.from('documentos').insert({...data,creado_por:state.user.id});const{error}=await q;if(error)throw error;message('Documento guardado correctamente.');resetDocumento();loadDocumentos()}catch(err){message(err.message||String(err),true)}};$('cancel-documento').onclick=resetDocumento;
async function deleteDocumento(x){if(!confirm('¿Eliminar este documento?'))return;const{error}=await sb.from('documentos').delete().eq('id',x.id);if(error)return message(error.message,true);if(x.bucket_nombre&&x.archivo_path)await sb.storage.from(x.bucket_nombre).remove([x.archivo_path]);message('Documento eliminado.');loadDocumentos()}

function popupIcon(tipo){return {informativo:'ℹ️',actividad:'📅',importante:'⚠️',emergencia:'🚨'}[tipo]||'📢'}
function popupDateValue(value){return value?String(value).slice(0,10):''}
function popupIsCurrent(x){const today=new Date().toISOString().slice(0,10);return !!x.activo&&(!x.fecha_inicio||x.fecha_inicio<=today)&&(!x.fecha_termino||x.fecha_termino>=today)}
function popupPreviewData(){const f=$('popup-form');return {id:f.id.value||'preview',titulo:f.titulo.value.trim()||'Título del aviso',mensaje:f.mensaje.value.trim()||'Aquí aparecerá el mensaje para los vecinos.',tipo:f.tipo.value,imagen_url:f.imagen_actual.value||'',boton_texto:f.boton_texto.value.trim(),boton_url:f.boton_url.value.trim()}}
function showPopupPreview(x){const host=$('popup-preview-host');host.innerHTML=`<div class="community-popup-overlay show"><div class="community-popup type-${esc(x.tipo)}" role="dialog" aria-modal="true"><button class="community-popup-close" type="button" aria-label="Cerrar">×</button><div class="community-popup-icon">${popupIcon(x.tipo)}</div><span class="community-popup-label">${esc(x.tipo)}</span><h2>${esc(x.titulo)}</h2>${x.imagen_url?`<img class="community-popup-image" src="${esc(x.imagen_url)}" alt="">`:''}<p>${esc(x.mensaje).replace(/\n/g,'<br>')}</p><div class="community-popup-actions">${x.boton_texto?`<span class="community-popup-link">${esc(x.boton_texto)}</span>`:''}<button class="community-popup-understood" type="button">Entendido</button></div></div></div>`;host.querySelectorAll('button').forEach(b=>b.onclick=()=>host.innerHTML='')}
async function loadPopups(){const{data,error}=await sb.from('avisos_popup').select('*').order('creado_en',{ascending:false});if(error){message('Avisos emergentes: '+error.message,true);return}const rows=data||[];const current=rows.find(popupIsCurrent);$('stat-popup').textContent=current?'Activo':'Inactivo';$('popup-status').textContent=current?'🟢 Activo ahora':'Sin aviso activo';$('popup-status').className='status-pill '+(current?'active':'inactive');const el=$('list-popup');el.innerHTML=rows.map(x=>`<article class="item"><div>${x.imagen_url?`<img class="thumb" src="${esc(x.imagen_url)}" alt="">`:''}<h3>${popupIcon(x.tipo)} ${esc(x.titulo)}</h3><p>${esc(x.mensaje)}</p><div class="item-meta">${esc(x.tipo)} · ${popupDateValue(x.fecha_inicio)} al ${popupDateValue(x.fecha_termino)} · ${x.activo?'Activo':'Inactivo'}${popupIsCurrent(x)?' · Visible ahora':''}</div></div><div class="actions"><button class="button secondary" data-preview-popup="${x.id}">Vista previa</button><button class="button secondary" data-edit-popup="${x.id}">Editar</button><button class="button danger" data-delete-popup="${x.id}">Eliminar</button></div></article>`).join('')||'<div class="panel empty">Todavía no hay avisos emergentes.</div>';el.querySelectorAll('[data-preview-popup]').forEach(b=>b.onclick=()=>showPopupPreview(rows.find(x=>x.id===b.dataset.previewPopup)));el.querySelectorAll('[data-edit-popup]').forEach(b=>b.onclick=()=>editPopup(rows.find(x=>x.id===b.dataset.editPopup)));el.querySelectorAll('[data-delete-popup]').forEach(b=>b.onclick=()=>deletePopup(b.dataset.deletePopup))}
function editPopup(x){const f=$('popup-form');['id','titulo','mensaje','tipo','boton_texto','boton_url'].forEach(k=>f.elements[k].value=x[k]??'');f.fecha_inicio.value=popupDateValue(x.fecha_inicio);f.fecha_termino.value=popupDateValue(x.fecha_termino);f.mostrar_una_vez.checked=!!x.mostrar_una_vez;f.activo.checked=!!x.activo;f.imagen_actual.value=x.imagen_url||'';$('popup-imagen-actual').textContent=x.imagen_url?'Imagen actual cargada':'';$('cancel-popup').hidden=false;f.scrollIntoView({behavior:'smooth'})}
function resetPopup(){const f=$('popup-form');f.reset();f.id.value='';f.imagen_actual.value='';f.mostrar_una_vez.checked=true;f.activo.checked=true;const today=new Date();const end=new Date(today);end.setDate(end.getDate()+7);f.fecha_inicio.value=today.toISOString().slice(0,10);f.fecha_termino.value=end.toISOString().slice(0,10);$('popup-imagen-actual').textContent='';$('cancel-popup').hidden=true}
$('popup-form').onsubmit=async e=>{e.preventDefault();const f=e.currentTarget;try{if(f.fecha_termino.value<f.fecha_inicio.value)throw new Error('La fecha de término no puede ser anterior a la fecha de inicio.');const file=f.imagen.files[0];const payload={titulo:f.titulo.value.trim(),mensaje:f.mensaje.value.trim(),tipo:f.tipo.value,fecha_inicio:f.fecha_inicio.value,fecha_termino:f.fecha_termino.value,mostrar_una_vez:f.mostrar_una_vez.checked,activo:f.activo.checked,boton_texto:f.boton_texto.value.trim()||null,boton_url:f.boton_url.value.trim()||null,imagen_url:file?await upload(file,'avisos-popup'):f.imagen_actual.value||null,actualizado_por:state.user.id};const id=f.id.value;const q=id?sb.from('avisos_popup').update(payload).eq('id',id):sb.from('avisos_popup').insert({...payload,creado_por:state.user.id});const{error}=await q;if(error)throw error;message('Aviso emergente guardado correctamente.');resetPopup();loadPopups()}catch(err){message(err.message||String(err),true)}};
$('preview-popup').onclick=()=>showPopupPreview(popupPreviewData());$('cancel-popup').onclick=resetPopup;
async function deletePopup(id){if(!confirm('¿Eliminar este aviso emergente?'))return;const{error}=await sb.from('avisos_popup').delete().eq('id',id);if(error)return message(error.message,true);message('Aviso eliminado.');loadPopups()}

async function loadAll(){for(const t of Object.keys(defs))await loadTable(t);await loadPopups();await loadConfig();await loadDirectiva();await loadDocumentos()}
$('login-form').onsubmit=async e=>{e.preventDefault();$('login-message').textContent='Ingresando...';const{error}=await sb.auth.signInWithPassword({email:$('login-email').value.trim(),password:$('login-password').value});if(error){$('login-message').textContent='No se pudo ingresar: '+(error.message==='Invalid login credentials'?'Correo o contraseña incorrectos.':error.message);return}$('login-message').textContent='';verify()};
$('forgot-password').onclick=async()=>{const email=$('login-email').value.trim();if(!email){$('login-message').textContent='Escribe primero tu correo electrónico.';return}const redirectTo=new URL('admin.html',window.location.href).href;const{error}=await sb.auth.resetPasswordForEmail(email,{redirectTo});$('login-message').textContent=error?'No se pudo enviar el enlace: '+error.message:'Te enviamos un enlace para crear una nueva contraseña.'};
$('recovery-form').onsubmit=async e=>{e.preventDefault();const a=$('new-password').value,b=$('confirm-password').value;if(a!==b){$('recovery-message').textContent='Las contraseñas no coinciden.';return}const{error}=await sb.auth.updateUser({password:a});if(error){$('recovery-message').textContent='No se pudo cambiar la contraseña: '+error.message;return}$('recovery-message').textContent='Contraseña actualizada.';setTimeout(()=>location.href='admin.html',1200)};
$('logout-button').onclick=async()=>{await sb.auth.signOut();showLogin()};document.querySelectorAll('[data-section]').forEach(b=>b.onclick=()=>{document.querySelectorAll('[data-section]').forEach(x=>x.classList.toggle('active',x===b));document.querySelectorAll('.admin-section').forEach(s=>s.hidden=s.id!==`section-${b.dataset.section}`);$('page-title').textContent=b.textContent.trim()});
buildForms();bindMultiInputs();resetPopup();document.querySelectorAll('form[data-table]').forEach(f=>{f.onsubmit=async e=>{e.preventDefault();try{await saveForm(f)}catch(err){message(err.message||String(err),true)}};f.querySelector('.cancel').onclick=()=>resetForm(f)});sb.auth.onAuthStateChange(event=>{if(event==='PASSWORD_RECOVERY'){$('login-form').hidden=true;$('recovery-form').hidden=false}else setTimeout(verify,0)});verify();
})();
