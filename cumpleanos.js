(() => {
  'use strict';
  const cfg=window.PORTAL_CONFIG||{};
  if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey)return;
  const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
  const $=s=>document.querySelector(s);
  const esc=s=>String(s??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const digits=v=>String(v||'').replace(/\D/g,'');
  const chileDate=()=>new Date(new Intl.DateTimeFormat('en-US',{timeZone:'America/Santiago',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));
  const isLeap=y=>(y%4===0&&y%100!==0)||y%400===0;
  const birthdayThisYear=(birth,year)=>{const d=new Date(birth+'T12:00:00Z');let m=d.getUTCMonth(),day=d.getUTCDate();if(m===1&&day===29&&!isLeap(year))day=28;return new Date(year,m,day,12)};
  const dateLabel=d=>d.toLocaleDateString('es-CL',{day:'2-digit',month:'short'}).replace('.','');
  const message=name=>`🎉 ¡Feliz cumpleaños, ${name}!\n\nLa Junta de Vecinos Villa El Trigal te desea un excelente día junto a tus seres queridos. Que este nuevo año de vida venga lleno de salud, alegría y buenos momentos.\n\n¡Un afectuoso saludo de toda la directiva! 🎂🎈`;
  async function markGreeting(socioId,year){try{const {data:{user}}=await sb.auth.getUser();await sb.from('cumpleanos_saludos').upsert({socio_id:socioId,anio:year,preparado_en:new Date().toISOString(),preparado_por:user?.id||null},{onConflict:'socio_id,anio'});}catch(e){console.warn('No fue posible registrar el saludo',e)}}
  async function load(){const todayBox=$('#birthday-today-list'),upcomingBox=$('#birthday-upcoming-list');if(!todayBox||!upcomingBox)return;try{const now=chileDate(),year=now.getFullYear(),start=new Date(year,now.getMonth(),now.getDate(),0),end=new Date(start);end.setDate(end.getDate()+7);const [{data:socios,error},{data:sent}]=await Promise.all([sb.from('socios').select('id,numero_socio,nombre_completo,nombres,telefono,fecha_nacimiento,autoriza_whatsapp').eq('estado','activo').not('fecha_nacimiento','is',null),sb.from('cumpleanos_saludos').select('socio_id,anio,preparado_en').eq('anio',year)]);if(error)throw error;const sentMap=new Map((sent||[]).map(x=>[x.socio_id,x]));const rows=(socios||[]).map(s=>{let date=birthdayThisYear(s.fecha_nacimiento,year);if(date<start){date=birthdayThisYear(s.fecha_nacimiento,year+1)}return {...s,nextBirthday:date,days:Math.round((date-start)/86400000),sent:sentMap.get(s.id)}}).filter(x=>x.days>=0&&x.days<=7).sort((a,b)=>a.days-b.days||a.nombre_completo.localeCompare(b.nombre_completo,'es'));
    const today=rows.filter(x=>x.days===0),upcoming=rows.filter(x=>x.days>0);
    todayBox.innerHTML=today.length?today.map(personToday).join(''):'<p class="help">Hoy no hay cumpleaños registrados.</p>';
    upcomingBox.innerHTML=upcoming.length?upcoming.map(personUpcoming).join(''):'<p class="help">No hay cumpleaños en los próximos 7 días.</p>';
    todayBox.querySelectorAll('[data-birthday-whatsapp]').forEach(b=>b.onclick=async()=>{const s=today.find(x=>x.id===b.dataset.birthdayWhatsapp);if(!s)return;await markGreeting(s.id,year);window.open(`https://wa.me/${digits(s.telefono)}?text=${encodeURIComponent(message((s.nombres||s.nombre_completo).split(' ')[0]))}`,'_blank','noopener');setTimeout(load,500)});
  }catch(e){console.error(e);todayBox.innerHTML='<p class="help">No fue posible cargar los cumpleaños.</p>';upcomingBox.innerHTML='<p class="help">Revisa la configuración de Supabase.</p>'}}
  function personToday(s){const phoneOk=digits(s.telefono).length>=11&&s.autoriza_whatsapp!==false;return `<div class="birthday-person"><div><h4>🎉 ${esc(s.nombre_completo)}</h4><p>Socio N.º ${esc(s.numero_socio||'—')}${s.telefono?' · '+esc(s.telefono):''}</p></div><div class="birthday-actions">${s.sent?'<span class="birthday-sent">✓ Saludo preparado</span>':''}${phoneOk?`<button class="button whatsapp" type="button" data-birthday-whatsapp="${s.id}">💬 Enviar WhatsApp</button>`:'<span class="help">Sin WhatsApp autorizado</span>'}</div></div>`}
  function personUpcoming(s){return `<div class="birthday-person"><div class="birthday-date">${esc(dateLabel(s.nextBirthday))}</div><div><h4>${esc(s.nombre_completo)}</h4><p>Socio N.º ${esc(s.numero_socio||'—')}</p></div></div>`}
  document.addEventListener('DOMContentLoaded',()=>{load();$('#birthday-refresh')?.addEventListener('click',load)});
  window.addEventListener('focus',()=>{if(!$('#section-dashboard')?.hidden)load()});
})();
