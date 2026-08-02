(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{};
  if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey)return;
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
  const $=s=>document.querySelector(s);
  const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const digits=v=>String(v||'').replace(/\D/g,'');
  const chileParts=()=>{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());const get=t=>Number(parts.find(x=>x.type===t)?.value);return {year:get('year'),month:get('month'),day:get('day')}};
  const isLeap=y=>(y%4===0&&y%100!==0)||y%400===0;
  const birthdayParts=(birth,year)=>{const [y,m0,d0]=String(birth||'').slice(0,10).split('-').map(Number);let month=m0,day=d0;if(month===2&&day===29&&!isLeap(year))day=28;return {year,month,day}};
  const dayNumber=({year,month,day})=>Math.floor(Date.UTC(year,month-1,day)/86400000);
  const birthdayDate=p=>new Date(p.year,p.month-1,p.day,12,0,0,0);
  const dateLabel=d=>d.toLocaleDateString('es-CL',{day:'2-digit',month:'short'}).replace('.','');
  const message=name=>`\u{1F389} ¡Feliz cumpleaños, ${name}!\n\nLa Junta de Vecinos Villa El Trigal te desea un excelente día junto a tus seres queridos. Que este nuevo año de vida venga lleno de salud, alegría y buenos momentos.\n\n¡Un afectuoso saludo de toda la directiva! \u{1F382}\u{1F388}`;
  async function markGreeting(socioId,year){try{const {data:{user}}=await sb.auth.getUser();await sb.from('cumpleanos_saludos').upsert({socio_id:socioId,anio:year,preparado_en:new Date().toISOString(),preparado_por:user?.id||null},{onConflict:'socio_id,anio'});}catch(e){console.warn('No fue posible registrar el saludo',e)}}
  async function load(){const todayBox=$('#birthday-today-list'),upcomingBox=$('#birthday-upcoming-list');if(!todayBox||!upcomingBox)return;try{const now=chileParts(),year=now.year,todayNumber=dayNumber(now);const [{data:socios,error},{data:sent}]=await Promise.all([sb.from('socios').select('id,numero_socio,nombre_completo,nombres,telefono,fecha_nacimiento,autoriza_whatsapp').eq('estado','activo').not('fecha_nacimiento','is',null),sb.from('cumpleanos_saludos').select('socio_id,anio,preparado_en').eq('anio',year)]);if(error)throw error;const sentMap=new Map((sent||[]).map(x=>[x.socio_id,x]));const rows=(socios||[]).map(s=>{let parts=birthdayParts(s.fecha_nacimiento,year);let days=dayNumber(parts)-todayNumber;if(days<0){parts=birthdayParts(s.fecha_nacimiento,year+1);days=dayNumber(parts)-todayNumber}return {...s,nextBirthday:birthdayDate(parts),days,sent:sentMap.get(s.id)}}).filter(x=>x.days>=0&&x.days<=7).sort((a,b)=>a.days-b.days||a.nombre_completo.localeCompare(b.nombre_completo,'es'));
    const today=rows.filter(x=>x.days===0),upcoming=rows.filter(x=>x.days>0);
    todayBox.innerHTML=today.length?today.map(personToday).join(''):'<p class="help">Hoy no hay cumpleaños registrados.</p>';
    upcomingBox.innerHTML=upcoming.length?upcoming.map(personUpcoming).join(''):'<p class="help">No hay cumpleaños en los próximos 7 días.</p>';
    todayBox.querySelectorAll('[data-birthday-whatsapp]').forEach(b=>b.onclick=async()=>{const s=today.find(x=>x.id===b.dataset.birthdayWhatsapp);if(!s)return;await markGreeting(s.id,year);window.SIGVEWhatsApp?.open(s.telefono,message((s.nombres||s.nombre_completo).split(' ')[0]));setTimeout(load,500)});
  }catch(e){console.error(e);todayBox.innerHTML='<p class="help">No fue posible cargar los cumpleaños.</p>';upcomingBox.innerHTML='<p class="help">Revisa la configuración de Supabase.</p>'}}
  function personToday(s){const phoneOk=digits(s.telefono).length>=11&&s.autoriza_whatsapp!==false;return `<div class="birthday-person"><div><h4>🎉 ${esc(s.nombre_completo)}</h4><p>Socio N.º ${esc(s.numero_socio||'—')}${s.telefono?' · '+esc(s.telefono):''}</p></div><div class="birthday-actions">${s.sent?'<span class="birthday-sent">✓ Saludo preparado</span>':''}${phoneOk?`<button class="button whatsapp" type="button" data-birthday-whatsapp="${s.id}">💬 Enviar WhatsApp</button>`:'<span class="help">Sin WhatsApp autorizado</span>'}</div></div>`}
  function personUpcoming(s){return `<div class="birthday-person"><div class="birthday-date">${esc(dateLabel(s.nextBirthday))}</div><div><h4>${esc(s.nombre_completo)}</h4><p>Socio N.º ${esc(s.numero_socio||'—')}</p></div></div>`}
  document.addEventListener('DOMContentLoaded',()=>{load();$('#birthday-refresh')?.addEventListener('click',load)});
  window.addEventListener('focus',()=>{if(!$('#section-dashboard')?.hidden)load()});
})();
