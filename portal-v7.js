(() => {
  const q = new URLSearchParams(window.location.search);
  const childToken = q.get('registro_ninos');
  if (childToken) {
    const target = new URL('./registro-ninos.html', window.location.href);
    target.searchParams.set('token', childToken);
    window.location.replace(target.href);
    return;
  }

  const cfg = window.PORTAL_CONFIG || {};
  if (!window.supabase || !cfg.supabaseUrl || !cfg.supabaseAnonKey) return;

  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  const monthNames = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
  const dayNames = ['Lu','Ma','Mi','Ju','Vi','Sá','Do'];
  let selectedRentalDate = null;
  let selectedRentalLabel = '';
  const MIN_RENTAL_YEAR = 2026;
  let rentalCalendarYear = Math.max(MIN_RENTAL_YEAR, new Date().getFullYear());

  const rutClean = value => String(value || '').replace(/[^0-9kK]/g, '').toUpperCase();
  const formatRut = value => {
    const clean = rutClean(value);
    if (clean.length < 2) return clean;
    let body = clean.slice(0, -1);
    const dv = clean.slice(-1);
    let output = '';
    while (body.length > 3) {
      output = '.' + body.slice(-3) + output;
      body = body.slice(0, -3);
    }
    return body + output + '-' + dv;
  };
  function validRut(value) {
    const clean = rutClean(value);
    if (!clean) return true;
    if (clean.length < 2) return false;
    const body = clean.slice(0, -1);
    const dv = clean.slice(-1);
    let sum = 0;
    let multiplier = 2;
    for (let i = body.length - 1; i >= 0; i--) {
      sum += Number(body[i]) * multiplier;
      multiplier = multiplier === 7 ? 2 : multiplier + 1;
    }
    const result = 11 - (sum % 11);
    const expected = result === 11 ? '0' : result === 10 ? 'K' : String(result);
    return dv === expected;
  }
  const phoneDigits = value => {
    let digits = String(value || '').replace(/\D/g, '');
    if (digits.startsWith('56')) digits = digits.slice(2);
    if (digits.startsWith('9')) digits = digits.slice(1);
    return digits.slice(0, 8);
  };
  const formatPhone = value => {
    const digits = phoneDigits(value);
    return digits ? `+56 9 ${digits.slice(0,4)}${digits.length > 4 ? ' ' + digits.slice(4) : ''}` : '';
  };
  const phoneDb = value => {
    const digits = phoneDigits(value);
    return digits.length === 8 ? `+569${digits}` : null;
  };
  const iso = (year, month, day) => `${year}-${String(month + 1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
  const readable = (year, month, day) => `${day} de ${monthNames[month].toLowerCase()} de ${year}`;

  function selectDate(dateIso, label) {
    selectedRentalDate = dateIso;
    selectedRentalLabel = label;
    const text = document.getElementById('selected-date-text');
    if (text) text.innerHTML = `Fecha seleccionada: <strong>${label}</strong>. Presiona el botón para ingresar tus datos y enviar la solicitud.`;
    document.querySelectorAll('.calendar-day.selected').forEach(element => element.classList.remove('selected'));
    document.querySelector(`[data-date="${dateIso}"]`)?.classList.add('selected');
  }

  async function renderCalendar() {
    const host = document.getElementById('rental-calendars');
    const status = document.getElementById('calendar-sync-status');
    const yearLabel = document.getElementById('rental-year-label');
    const previousButton = document.getElementById('rental-year-prev');
    if (!host) return;

    rentalCalendarYear = Math.max(MIN_RENTAL_YEAR, rentalCalendarYear);
    if (yearLabel) yearLabel.textContent = String(rentalCalendarYear);
    if (previousButton) previousButton.disabled = rentalCalendarYear <= MIN_RENTAL_YEAR;
    host.innerHTML = '<p>Cargando calendario…</p>';

    const startKey = iso(rentalCalendarYear, 0, 1);
    const endKey = iso(rentalCalendarYear + 1, 0, 1);
    const { data, error } = await sb
      .from('reservas_publicas')
      .select('*')
      .gte('fecha_evento', startKey)
      .lt('fecha_evento', endKey);

    if (error) {
      console.error('No fue posible cargar reservas_publicas:', error);
      host.innerHTML = '<p>No fue posible cargar el calendario.</p>';
      if (status) status.textContent = 'Error al consultar la disponibilidad. Revisa la conexión con Supabase.';
      return;
    }

    const map = new Map((data || []).map(entry => [entry.fecha_evento, entry]));
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    host.innerHTML = '';

    for (let month = 0; month < 12; month++) {
      const card = document.createElement('article');
      card.className = 'month-card';
      card.innerHTML = `<h4>${monthNames[month]} ${rentalCalendarYear}</h4>`;
      const days = document.createElement('div');
      days.className = 'month-days';
      dayNames.forEach(name => days.insertAdjacentHTML('beforeend', `<span class="day-name">${name}</span>`));
      const offset = (new Date(rentalCalendarYear, month, 1).getDay() + 6) % 7;
      for (let blank = 0; blank < offset; blank++) days.insertAdjacentHTML('beforeend', '<span class="calendar-blank"></span>');
      const count = new Date(rentalCalendarYear, month + 1, 0).getDate();

      for (let day = 1; day <= count; day++) {
        const dateKey = iso(rentalCalendarYear, month, day);
        const entry = map.get(dateKey);
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.date = dateKey;
        button.textContent = day;
        const date = new Date(rentalCalendarYear, month, day);
        const past = date < today;
        if (past) {
          button.className = 'calendar-day past';
          button.disabled = true;
          button.title = 'Fecha pasada';
        } else if (entry) {
          const cssClass = entry.tipo === 'zumba' ? 'zumba' : entry.tipo === 'actividad' || entry.tipo === 'administrativa' ? 'activity' : 'reserved';
          button.className = `calendar-day ${cssClass}`;
          button.disabled = true;
          button.title = entry.descripcion_publica || (entry.tipo === 'arriendo' ? 'Reservado' : 'Fecha no disponible');
        } else {
          button.className = 'calendar-day available';
          button.onclick = () => selectDate(dateKey, readable(rentalCalendarYear, month, day));
          button.title = 'Disponible para solicitar';
        }
        days.appendChild(button);
      }
      card.appendChild(days);
      host.appendChild(card);
    }
    if (status) status.textContent = `Calendario ${rentalCalendarYear} actualizado desde Gestión de la Sede.`;
  }

  function configureRentalYearNavigation() {
    const previousButton = document.getElementById('rental-year-prev');
    const nextButton = document.getElementById('rental-year-next');
    if (previousButton) previousButton.onclick = async () => {
      if (rentalCalendarYear <= MIN_RENTAL_YEAR) return;
      rentalCalendarYear -= 1;
      selectedRentalDate = null;
      selectedRentalLabel = '';
      await renderCalendar();
    };
    if (nextButton) nextButton.onclick = async () => {
      rentalCalendarYear += 1;
      selectedRentalDate = null;
      selectedRentalLabel = '';
      await renderCalendar();
    };
  }

  function openRentalForm() {
    if (!selectedRentalDate) {
      alert('Primero selecciona una fecha disponible en el calendario.');
      return;
    }
    document.querySelector('.public-reservation-modal')?.remove();
    const modal = document.createElement('dialog');
    modal.className = 'public-reservation-modal';
    modal.innerHTML = `
      <div class="public-reservation-card" role="dialog" aria-modal="true" aria-labelledby="reservation-title">
        <button type="button" class="public-modal-close" aria-label="Cerrar">×</button>
        <p class="eyebrow">Solicitud de arriendo</p>
        <h3 id="reservation-title">Reserva para ${selectedRentalLabel}</h3>
        <p class="public-reservation-help">La fecha quedará bloqueada como pendiente mientras la Junta revisa la solicitud y el abono.</p>
        <form id="public-reservation-form">
          <label>Nombre completo<input name="nombre" required maxlength="120" autocomplete="name"></label>
          <label>Celular<div class="public-phone"><span>+56 9</span><input name="telefono" required inputmode="numeric" maxlength="16" placeholder="1234 5678" autocomplete="tel"></div></label>
          <label>RUT (opcional)<input name="rut" maxlength="15" placeholder="12.345.678-9"></label>
          <label>Tipo de actividad / comentario<textarea name="observaciones" maxlength="500" placeholder="Ej.: cumpleaños familiar"></textarea></label>
          <section class="public-benefit-panel" id="public-benefit-panel" hidden><p class="eyebrow">Programa de beneficios</p><div id="public-benefit-options"></div><div id="public-benefit-summary"></div></section>
          <p class="public-form-message" aria-live="polite"></p>
          <div class="public-reservation-actions">
            <button type="submit" class="button primary">Guardar y continuar a WhatsApp</button>
            <button type="button" class="button secondary" data-cancel>Cancelar</button>
          </div>
        </form>
      </div>`;
    document.body.appendChild(modal);
    // showModal() coloca el formulario en la capa superior del navegador,
    // por encima del calendario y de cualquier otro modal del portal.
    if (typeof modal.showModal === 'function') modal.showModal();
    else modal.setAttribute('open', '');
    const close = () => {
      try { if (modal.open && typeof modal.close === 'function') modal.close(); } catch (_) {}
      modal.remove();
    };
    modal.addEventListener('click', event => {
      const card = modal.querySelector('.public-reservation-card');
      if (event.target === modal && card) {
        const r = card.getBoundingClientRect();
        const outside = event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom;
        if (outside) close();
      }
    });
    modal.addEventListener('cancel', event => { event.preventDefault(); close(); });
    modal.querySelector('.public-modal-close').onclick = close;
    modal.querySelector('[data-cancel]').onclick = close;
    const form = modal.querySelector('form');
    const rut = form.elements.rut;
    const phone = form.elements.telefono;
    let portalToken = null;
    let benefitRows = [];
    let selectedBenefitId = null;
    let selectedBenefitType = null;
    let originalValue = 0;
    const benefitPanel = modal.querySelector('#public-benefit-panel');
    const benefitOptions = modal.querySelector('#public-benefit-options');
    const benefitSummary = modal.querySelector('#public-benefit-summary');
    const moneyCL = value => new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(value||0));
    const renderBenefitSummary = () => {
      if (!benefitRows.length) return;
      const chosen = benefitRows.find(x => x.beneficio_id === selectedBenefitId);
      const finalValue = chosen ? Number(chosen.valor_final||originalValue) : originalValue;
      benefitSummary.innerHTML = `<div class="benefit-price-row"><span>Valor normal</span><strong>${moneyCL(originalValue)}</strong></div>${chosen?`<div class="benefit-price-row"><span>Beneficio aplicado</span><strong>${chosen.nombre}</strong></div><div class="benefit-price-row"><span>Descuento</span><strong>-${moneyCL(Math.max(0,originalValue-finalValue))}</strong></div>`:''}<div class="benefit-price-row total"><span>Total</span><strong>${moneyCL(finalValue)}</strong></div>`;
    };
    const loadBenefits = async () => {
      if (!portalToken) return;
      benefitPanel.hidden = false; benefitOptions.innerHTML = '<p>Revisando beneficios…</p>';
      const {data,error} = await sb.rpc('portal_socio_beneficios_arriendo',{p_token:portalToken,p_fecha:selectedRentalDate});
      if(error){benefitOptions.innerHTML='<p>No fue posible evaluar los beneficios. La solicitud continuará con precio normal.</p>';return}
      benefitRows=(data||[]).filter(x=>x.cumple);
      originalValue=Number((data||[])[0]?.valor_original||0);
      const discounts=benefitRows.filter(x=>x.tipo!=='gratis');
      const free=benefitRows.find(x=>x.tipo==='gratis');
      const automatic=discounts.sort((a,b)=>Number(a.valor_final)-Number(b.valor_final))[0]||null;
      selectedBenefitId=automatic?.beneficio_id||null; selectedBenefitType=automatic?.tipo||null;
      if(!benefitRows.length){benefitOptions.innerHTML='<p>No hay beneficios disponibles para esta fecha.</p>';renderBenefitSummary();return}
      benefitOptions.innerHTML = `${automatic?`<p class="benefit-auto">✅ Se aplicará automáticamente <strong>${automatic.nombre}</strong>.</p>`:''}${free?`<label class="benefit-free-choice"><input type="checkbox" id="use-free-benefit"> Usar mi arriendo gratuito anual</label>`:''}`;
      const check=benefitOptions.querySelector('#use-free-benefit');
      if(check) check.onchange=()=>{if(check.checked){selectedBenefitId=free.beneficio_id;selectedBenefitType='gratis'}else{selectedBenefitId=automatic?.beneficio_id||null;selectedBenefitType=automatic?.tipo||null}renderBenefitSummary()};
      renderBenefitSummary();
    };
    try {
      const prefill = JSON.parse(sessionStorage.getItem('sigve_reserva_prefill') || 'null');
      if (prefill) {
        form.elements.nombre.value = prefill.nombre || '';
        rut.value = formatRut(prefill.rut || '');
        phone.value = formatPhone(prefill.telefono || '');
        portalToken = prefill.portal_token || null;
        sessionStorage.removeItem('sigve_reserva_prefill');
      }
    } catch (_) { sessionStorage.removeItem('sigve_reserva_prefill'); }
    rut.addEventListener('input', () => rut.value = formatRut(rut.value));
    phone.addEventListener('input', () => phone.value = formatPhone(phone.value));
    loadBenefits();

    form.onsubmit = async event => {
      event.preventDefault();
      const message = form.querySelector('.public-form-message');
      const submit = form.querySelector('button[type="submit"]');
      const formattedRut = formatRut(rut.value);
      const dbPhone = phoneDb(phone.value);
      if (formattedRut && !validRut(formattedRut)) {
        message.textContent = 'Revisa el RUT ingresado.';
        return;
      }
      if (!dbPhone) {
        message.textContent = 'El celular debe tener 8 dígitos después de +56 9.';
        return;
      }
      submit.disabled = true;
      submit.textContent = 'Guardando solicitud…';
      message.textContent = '';
      const whatsappWindow = window.open('about:blank', '_blank');
      try {
        const rpcName = portalToken ? 'crear_solicitud_reserva_portal' : 'crear_solicitud_reserva';
        const rpcArgs = portalToken ? {
          p_token: portalToken,
          p_nombre: form.elements.nombre.value.trim(),
          p_telefono: dbPhone,
          p_fecha: selectedRentalDate,
          p_rut: formattedRut || null,
          p_observaciones: form.elements.observaciones.value.trim() || null,
          p_beneficio_id: selectedBenefitId
        } : {
          p_nombre: form.elements.nombre.value.trim(),
          p_telefono: dbPhone,
          p_fecha: selectedRentalDate,
          p_rut: formattedRut || null,
          p_observaciones: form.elements.observaciones.value.trim() || null
        };
        const { error } = await sb.rpc(rpcName, rpcArgs);
        if (error) throw error;
        const chosenBenefit = benefitRows.find(x=>x.beneficio_id===selectedBenefitId);
        const benefitText = chosenBenefit ? ` Beneficio aplicado: ${chosenBenefit.nombre}. Total estimado: ${moneyCL(chosenBenefit.valor_final)}.` : '';
        const whatsappText = `Hola, envié una solicitud de arriendo de la Sede Social Villa El Trigal para el día ${selectedRentalLabel}. Mi nombre es ${form.elements.nombre.value.trim()} y mi celular es ${formatPhone(dbPhone)}. Adjuntaré el comprobante del abono de $10.000. Entiendo que la reserva queda confirmada únicamente cuando la Junta de Vecinos responda por WhatsApp.`;
        const whatsappUrl = `https://wa.me/56974596793?text=${encodeURIComponent(whatsappText)}`;
        if (whatsappWindow) whatsappWindow.location.href = whatsappUrl;
        else window.location.href = whatsappUrl;
        close();
        selectedRentalDate = null;
        selectedRentalLabel = '';
        const selectedText = document.getElementById('selected-date-text');
        if (selectedText) selectedText.innerHTML = '<strong>Solicitud registrada.</strong> La fecha quedó bloqueada como pendiente y aparecerá en Gestión de la Sede.';
        await renderCalendar();
      } catch (error) {
        if (whatsappWindow) whatsappWindow.close();
        console.error('Error al crear solicitud de reserva:', error);
        const duplicate = /disponible|duplicate|unique|fecha/i.test(error?.message || '');
        message.textContent = duplicate ? 'La fecha acaba de ser ocupada. Selecciona otra fecha disponible.' : `No se pudo guardar la solicitud: ${error?.message || 'Error desconocido.'}`;
        submit.disabled = false;
        submit.textContent = 'Guardar y continuar a WhatsApp';
        if (duplicate) renderCalendar();
      }
    };
    form.elements.nombre.focus();
  }

  function setupRentalRequest() {
    const link = document.getElementById('rental-whatsapp');
    if (!link) return;
    link.removeAttribute('target');
    link.removeAttribute('href');
    link.setAttribute('role', 'button');
    link.addEventListener('click', event => {
      event.preventDefault();
      openRentalForm();
    });
  }

  const normalizeSearch = value => String(value || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
  const viaLabel = via => `${via.tipo} ${via.nombre}`.trim();
  async function loadPublicVias() {
    const {data,error}=await sb.from('vias').select('id,tipo,nombre,aliases').eq('activa',true).order('nombre');
    if(error){console.error('No fue posible cargar las vías:',error);return []}
    return (data||[]).sort((a,b)=>viaLabel(a).localeCompare(viaLabel(b),'es',{sensitivity:'base'}));
  }
  function bindPublicViaPicker(form,vias){
    const root=form.querySelector('[data-via-picker]'),input=form.elements.via_busqueda,hidden=form.elements.via_id,list=root.querySelector('.via-suggestions'),number=form.elements.numero_domicilio,preview=form.querySelector('[data-address-preview]');
    let matches=[];
    const updatePreview=()=>{const via=vias.find(v=>v.id===hidden.value);preview.textContent=via&&number.value.trim()?`📍 ${viaLabel(via)} ${number.value.trim()}`:'📍 Selecciona una vía e ingresa el número.'};
    const close=()=>{list.hidden=true;input.setAttribute('aria-expanded','false')};
    const choose=via=>{hidden.value=via.id;input.value=viaLabel(via);root.classList.remove('invalid');close();updatePreview()};
    const render=()=>{const q=normalizeSearch(input.value);hidden.value='';matches=vias.filter(v=>!q||normalizeSearch([viaLabel(v),...(v.aliases||[])].join(' ')).includes(q)).slice(0,30);list.innerHTML=matches.length?matches.map((v,i)=>`<button type="button" class="via-suggestion" data-index="${i}" role="option">${viaLabel(v)}</button>`).join(''):'<div class="via-empty">No hay coincidencias. Consulta a la directiva.</div>';list.hidden=false;input.setAttribute('aria-expanded','true');list.querySelectorAll('[data-index]').forEach(b=>b.onclick=()=>choose(matches[Number(b.dataset.index)]));updatePreview()};
    input.addEventListener('focus',render);input.addEventListener('input',render);input.addEventListener('keydown',e=>{if(e.key==='Escape')close()});number.addEventListener('input',()=>{number.value=number.value.replace(/[^0-9]/g,'');updatePreview()});document.addEventListener('click',e=>{if(!root.contains(e.target))close()});
    return {valid:()=>{const ok=!!hidden.value;if(!ok)root.classList.add('invalid');return ok},reset:()=>{hidden.value='';input.value='';updatePreview()}};
  }

  async function setupSocioForm() {
    const form = document.getElementById('public-socio-form');
    const message = document.getElementById('public-socio-message');
    if (!form) return;
    const vias=await loadPublicVias();
    const picker=bindPublicViaPicker(form,vias);
    const rut = form.elements.rut;
    const phone = form.elements.telefono;
    const birth = form.elements.fecha_nacimiento;
    const occupation = form.elements.ocupacion;
    const otherOccupation = form.querySelector('[data-otra-ocupacion]');
    const calculateAge = value => { if(!value) return ''; const today=new Date(), born=new Date(value+'T00:00:00'); let years=today.getFullYear()-born.getFullYear(); const beforeBirthday=today.getMonth()<born.getMonth()||(today.getMonth()===born.getMonth()&&today.getDate()<born.getDate()); return years-(beforeBirthday?1:0); };
    birth.max = new Date().toISOString().slice(0,10);
    birth.addEventListener('change',()=>{form.elements.edad_calculada.value=calculateAge(birth.value)});
    const syncOtherOccupation=()=>{const show=occupation.value==='Otro';otherOccupation.hidden=!show;form.elements.ocupacion_otro.required=show;if(!show)form.elements.ocupacion_otro.value=''};
    occupation.addEventListener('change',syncOtherOccupation);
    syncOtherOccupation();
    rut.dataset.rut = '1';
    rut.addEventListener('input', () => rut.value = formatRut(rut.value));
    phone.addEventListener('input', () => phone.value = formatPhone(phone.value));
    form.onsubmit = async event => {
      event.preventDefault();
      const formattedRut = formatRut(rut.value);
      const dbPhone = phoneDb(phone.value);
      const via=vias.find(v=>v.id===form.elements.via_id.value);
      const numero=form.elements.numero_domicilio.value.trim();
      if (!picker.valid() || !via) {message.textContent='Selecciona una calle, pasaje o avenida válida de la lista.';return}
      if (!numero) {message.textContent='Ingresa el número del domicilio.';return}
      if (!validRut(formattedRut)) {
        message.textContent = 'Revisa el RUT ingresado.';
        return;
      }
      if (!dbPhone) {
        message.textContent = 'El celular debe tener 8 dígitos después de +56 9.';
        return;
      }
      message.textContent = 'Enviando…';
      const { error } = await sb.from('solicitudes_socios').insert({
        nombres: form.elements.nombres.value.trim(),
        apellido_paterno: form.elements.apellido_paterno.value.trim(),
        apellido_materno: form.elements.apellido_materno.value.trim() || null,
        nombre_completo: [form.elements.nombres.value,form.elements.apellido_paterno.value,form.elements.apellido_materno.value].map(v=>v.trim()).filter(Boolean).join(' '),
        rut: formattedRut,
        fecha_nacimiento: form.elements.fecha_nacimiento.value,
        estado_civil: form.elements.estado_civil.value,
        ocupacion: form.elements.ocupacion.value,
        ocupacion_otro: form.elements.ocupacion.value==='Otro' ? form.elements.ocupacion_otro.value.trim() : null,
        via_id: via.id,
        numero_domicilio: numero,
        direccion: `${viaLabel(via)} ${numero}`,
        telefono: dbPhone,
        correo: form.elements.correo.value.trim() || null,
        observaciones: form.elements.observaciones.value.trim() || null,
        autoriza_whatsapp: !!form.elements.autoriza_whatsapp?.checked,
        estado: 'pendiente'
      });
      if (error) {
        message.textContent = 'No se pudo enviar: ' + error.message;
        return;
      }
      form.reset();picker.reset();
      message.textContent = 'Solicitud enviada correctamente. La directiva la revisará.';
    };
  }

  async function setupChildRegistration() {
    const token = new URLSearchParams(location.search).get('registro_ninos');
    if (!token) return;
    const { data: socio, error } = await sb.rpc('obtener_socio_por_token_ninos', { p_token: token });
    if (error || !socio || !socio.length) {
      alert('El enlace para registrar niños y niñas no es válido o ya no está disponible.');
      return;
    }
    const info = socio[0];
    const overlay = document.createElement('div');
    overlay.className = 'public-child-overlay';
    overlay.innerHTML = `<div class="public-child-card"><button type="button" class="public-child-close" aria-label="Cerrar">×</button><h2>Niños y niñas del hogar</h2><p>Socio titular: <strong>${escapeHtml(info.nombre_completo)}</strong></p><p>Domicilio asociado: <strong>${escapeHtml(info.direccion)}</strong></p><p class="help">Registra únicamente a los niños y niñas que viven en este domicilio. La dirección se asocia automáticamente y no puede modificarse.</p><form id="public-child-form" class="public-grid"><label>Nombre completo<input name="nombre" required></label><label>Fecha de nacimiento<input name="fecha_nacimiento" type="date" required></label><label>Sexo<select name="sexo"><option value="F">Niña</option><option value="M">Niño</option></select></label><div class="full"><button class="button primary" type="submit">Guardar niño o niña</button><p id="public-child-message"></p></div></form><div id="public-child-list"></div></div>`;
    document.body.appendChild(overlay);
    overlay.querySelector('.public-child-close').onclick=()=>overlay.remove();
    const form=overlay.querySelector('#public-child-form'), message=overlay.querySelector('#public-child-message'), list=overlay.querySelector('#public-child-list');
    async function refresh(){const{data}=await sb.rpc('listar_ninos_por_token',{p_token:token});list.innerHTML=(data||[]).length?`<h3>Registros guardados</h3>${data.map(x=>`<p>🧒 ${escapeHtml(x.nombre_completo)} · ${new Date(x.fecha_nacimiento+'T12:00:00').toLocaleDateString('es-CL')}</p>`).join('')}`:'<p>Aún no hay niños o niñas registrados.</p>'}
    form.onsubmit=async e=>{e.preventDefault();message.textContent='Guardando…';const{error}=await sb.rpc('registrar_nino_por_token',{p_token:token,p_nombre:form.elements.nombre.value.trim(),p_fecha_nacimiento:form.elements.fecha_nacimiento.value,p_sexo:form.elements.sexo.value});if(error){message.textContent='No se pudo guardar: '+error.message;return}form.reset();message.textContent='Registro guardado correctamente.';refresh()};
    refresh();
  }

  document.addEventListener('DOMContentLoaded', () => {
    configureRentalYearNavigation();
    renderCalendar();
    setupRentalRequest();
    setupSocioForm();
    setupChildRegistration();
  });
})();
