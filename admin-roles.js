(()=>{
'use strict';
const $=s=>document.querySelector(s);
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
let currentRole='';
let rows=[];

const roleLabel=r=>({administrador:'Administrador principal',tesorero:'Tesorero',secretario:'Secretario'}[r]||r||'Sin rol');

async function getMyRole(){
 const {data:{user}}=await sb.auth.getUser(); if(!user)return '';
 const {data}=await sb.from('administradores').select('rol,activo').eq('user_id',user.id).maybeSingle();
 currentRole=data?.activo?String(data.rol||'').toLowerCase():'';
 return currentRole;
}

function ensureUI(){
 if($('#section-usuarios'))return;
 const nav=$('.sidebar nav'); if(!nav)return;
 const cfg=nav.querySelector('[data-section="configuracion"]');
 (cfg||nav.lastElementChild)?.insertAdjacentHTML(cfg?'afterend':'beforebegin','<button data-section="usuarios" id="nav-usuarios">🔐 Usuarios y permisos</button>');
 const main=$('.admin-main');
 main.insertAdjacentHTML('beforeend',`<section id="section-usuarios" class="admin-section" hidden>
  <div class="panel"><div class="panel-heading"><div><h3>🔐 Usuarios y permisos</h3><p class="help">Los cargos pueden quedar sin asignar. No se crean cuentas ni contraseñas genéricas.</p></div><button id="roles-refresh" class="button secondary" type="button">↻ Actualizar</button></div>
  <div class="role-cards" id="role-cards"></div></div>
  <div class="panel"><h3>Asignar Tesorero o Secretario</h3><p class="help">Por seguridad, primero crea la persona en <strong>Supabase → Authentication → Users</strong>. Luego escribe aquí ese mismo correo. Puedes dejarla inactiva hasta que asuma el cargo.</p>
   <form id="role-form"><div class="form-grid"><label>Cargo<select name="rol" required><option value="tesorero">Tesorero</option><option value="secretario">Secretario</option></select></label><label>Nombre<input name="nombre" required placeholder="Nombre de la persona"></label><label>Correo de acceso<input name="email" type="email" required placeholder="correo@ejemplo.cl"></label><label class="check"><input name="activo" type="checkbox"> Activar acceso inmediatamente</label></div><div class="actions"><button class="button primary" type="submit">Asignar usuario</button></div><p id="role-message" class="form-message"></p></form>
  </div>
  <div class="panel"><h3>Cómo funciona</h3><p class="help">Administrador: control total. Tesorero y Secretario se pueden asignar, activar o desactivar sin borrar la cuenta de Authentication. Al cambiar la directiva puedes desactivar al usuario anterior y asignar al nuevo.</p></div>
 </section>`);
 $('#roles-refresh').onclick=loadRoles;
 $('#role-form').onsubmit=assignUser;
 document.addEventListener('click',onRoleAction);
 document.addEventListener('click',e=>{
   const b=e.target.closest('[data-section="usuarios"]'); if(!b)return;
   e.stopImmediatePropagation();
   document.querySelectorAll('[data-section]').forEach(x=>x.classList.toggle('active',x===b));
   document.querySelectorAll('.admin-section').forEach(s=>s.hidden=s.id!=='section-usuarios');
   $('#page-title').textContent='🔐 Usuarios y permisos'; loadRoles();
 },true);
}

function render(){
 const host=$('#role-cards'); if(!host)return;
 const roles=['administrador','tesorero','secretario'];
 host.innerHTML=roles.map(role=>{
   const list=rows.filter(x=>String(x.rol).toLowerCase()===role);
   const active=list.find(x=>x.activo); const shown=active||list[0];
   if(!shown)return `<article class="role-card"><div><span class="role-icon">${role==='administrador'?'👑':role==='tesorero'?'💰':'📋'}</span><h4>${roleLabel(role)}</h4></div><span class="role-status empty">Sin asignar</span><p>No existe una persona vinculada a este cargo.</p>${role==='administrador'?'<small>El administrador principal se mantiene protegido.</small>':'<small>Puedes asignarlo cuando esté definida la nueva directiva.</small>'}</article>`;
   return `<article class="role-card"><div><span class="role-icon">${role==='administrador'?'👑':role==='tesorero'?'💰':'📋'}</span><h4>${roleLabel(role)}</h4></div><span class="role-status ${shown.activo?'on':'off'}">${shown.activo?'Activo':'Inactivo'}</span><p><strong>${esc(shown.nombre||'Sin nombre')}</strong><br><span>${esc(shown.email||'Sin correo disponible')}</span></p>${role==='administrador'?'<small>Cuenta principal. No puede desactivarse desde aquí.</small>':`<div class="actions"><button class="button ${shown.activo?'danger':'primary'} role-toggle" data-id="${shown.user_id}" data-active="${shown.activo}">${shown.activo?'Desactivar':'Activar'}</button><button class="button secondary role-remove" data-id="${shown.user_id}">Desasignar</button></div>`}</article>`;
 }).join('');
}

async function loadRoles(){
 if(currentRole!=='administrador')return;
 const {data,error}=await sb.rpc('sigve_listar_usuarios');
 if(error){$('#role-cards').innerHTML=`<p class="form-message error">${esc(error.message)}. Ejecuta primero ACTUALIZAR_SUPABASE_SIGVE_V6_3_USUARIOS_ROLES.sql.</p>`;return}
 rows=data||[]; render();
}

async function assignUser(e){
 e.preventDefault(); const f=e.currentTarget,m=$('#role-message'); m.textContent='Guardando…';
 const {error}=await sb.rpc('sigve_asignar_usuario',{p_email:f.email.value.trim(),p_nombre:f.nombre.value.trim(),p_rol:f.rol.value,p_activo:f.activo.checked});
 if(error){m.textContent=error.message; m.classList.add('error'); return}
 m.classList.remove('error');m.textContent=f.activo.checked?'Usuario asignado y activado.':'Usuario asignado. Quedó inactivo hasta que decidas activarlo.'; f.reset(); await loadRoles();
}

async function onRoleAction(e){
 const t=e.target.closest('.role-toggle,.role-remove'); if(!t)return;
 const id=t.dataset.id; if(!id)return;
 if(t.classList.contains('role-toggle')){
   const activate=t.dataset.active!=='true';
   const {error}=await sb.rpc('sigve_cambiar_estado_usuario',{p_user_id:id,p_activo:activate});
   if(error)return alert(error.message);
 }else{
   if(!confirm('¿Desasignar esta persona del cargo? Su cuenta de Authentication no será eliminada.'))return;
   const {error}=await sb.rpc('sigve_desasignar_usuario',{p_user_id:id}); if(error)return alert(error.message);
 }
 await loadRoles();
}

function applyRoleUI(){
 const badge=$('#admin-name'); if(badge&&currentRole)badge.insertAdjacentHTML('afterend',`<span class="admin-role-badge">${esc(roleLabel(currentRole))}</span>`);
 const navUsers=$('#nav-usuarios'); if(navUsers)navUsers.hidden=currentRole!=='administrador';
 // Protección visual adicional. La protección real está en Supabase.
 if(currentRole==='tesorero'){
   ['popup','anuncios','noticias','actividades','galeria','configuracion','periodos','directiva','autoridades','gestion','socios','vias','documentos','certificados'].forEach(k=>{const x=$(`[data-section="${k}"]`);if(x)x.hidden=true});
 }
 if(currentRole==='secretario'){
   ['popup','configuracion','periodos','gestion','finanzas','libro-caja','informe-mensual','zumba'].forEach(k=>{const x=$(`[data-section="${k}"]`);if(x)x.hidden=true});
 }
}

async function init(){
 await new Promise(r=>setTimeout(r,350));
 await getMyRole(); ensureUI(); applyRoleUI(); if(currentRole==='administrador')loadRoles();
}
window.addEventListener('load',init);
})();
