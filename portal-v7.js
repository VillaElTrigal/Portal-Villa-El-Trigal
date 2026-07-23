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
    if (!host) return;
    host.innerHTML = '<p>Cargando calendario…</p>';

    const start = new Date();
    start.setHours(0,0,0,0);
    start.setDate(1);
    const end = new Date(start.getFullYear() + 1, start.getMonth(), 1);
    const { data, error } = await sb
      .from('reservas_publicas')
      .select('*')
      .gte('fecha_evento', iso(start.getFullYear(), start.getMonth(), 1))
      .lt('fecha_evento', iso(end.getFullYear(), end.getMonth(), 1));

    if (error) {
      console.error('No fue posible cargar reservas_publicas:', error);
      host.innerHTML = '<p>No fue posible cargar el calendario.</p>';
      if (status) status.textContent = 'Error al consultar la disponibilidad. Ejecuta primero el archivo SQL de la versión 8.0.';
      return;
    }

    const map = new Map((data || []).map(entry => [entry.fecha_evento, entry]));
    host.innerHTML = '';
    for (let index = 0; index < 12; index++) {
      const year = start.getFullYear() + Math.floor((start.getMonth() + index) / 12);
      const month = (start.getMonth() + index) % 12;
      const card = document.createElement('article');
      card.className = 'month-card';
      card.innerHTML = `<h4>${monthNames[month]} ${year}</h4>`;
      const days = document.createElement('div');
      days.className = 'month-days';
      dayNames.forEach(name => days.insertAdjacentHTML('beforeend', `<span class="day-name">${name}</span>`));
      const offset = (new Date(year, month, 1).getDay() + 6) % 7;
      for (let blank = 0; blank < offset; blank++) days.insertAdjacentHTML('beforeend', '<span class="calendar-blank"></span>');
      const count = new Date(year, month + 1, 0).getDate();

      for (let day = 1; day <= count; day++) {
        const dateKey = iso(year, month, day);
        const entry = map.get(dateKey);
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.date = dateKey;
        button.textContent = day;
        const date = new Date(year, month, day);
        const past = date < new Date(new Date().setHours(0,0,0,0));
        if (past) {
          button.className = 'calendar-day past';
          button.disabled = true;
          button.title = 'Fecha pasada';
        } else if (entry) {
          const cssClass = entry.tipo === 'zumba' ? 'zumba' : entry.tipo === 'actividad' ? 'activity' : 'reserved';
          button.className = `calendar-day ${cssClass}`;
          button.disabled = true;
          button.title = entry.descripcion_publica || (entry.tipo === 'arriendo' ? 'Reservado' : 'Fecha no disponible');
        } else {
          button.className = 'calendar-day available';
          button.onclick = () => selectDate(dateKey, readable(year, month, day));
          button.title = 'Disponible para solicitar';
        }
        days.appendChild(button);
      }
      card.appendChild(days);
      host.appendChild(card);
    }
    if (status) status.textContent = 'Calendario actualizado desde Gestión de la Sede.';
  }

  function openRentalForm() {
    if (!selectedRentalDate) {
      alert('Primero selecciona una fecha disponible en el calendario.');
      return;
    }
    document.querySelector('.public-reservation-modal')?.remove();
    const modal = document.createElement('div');
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
          <p class="public-form-message" aria-live="polite"></p>
          <div class="public-reservation-actions">
            <button type="submit" class="button primary">Guardar y continuar a WhatsApp</button>
            <button type="button" class="button secondary" data-cancel>Cancelar</button>
          </div>
        </form>
      </div>`;
    document.body.appendChild(modal);
    const close = () => modal.remove();
    modal.addEventListener('click', event => { if (event.target === modal) close(); });
    modal.querySelector('.public-modal-close').onclick = close;
    modal.querySelector('[data-cancel]').onclick = close;
    const form = modal.querySelector('form');
    const rut = form.elements.rut;
    const phone = form.elements.telefono;
    rut.addEventListener('input', () => rut.value = formatRut(rut.value));
    phone.addEventListener('input', () => phone.value = formatPhone(phone.value));

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
        const { error } = await sb.rpc('crear_solicitud_reserva', {
          p_nombre: form.elements.nombre.value.trim(),
          p_telefono: dbPhone,
          p_fecha: selectedRentalDate,
          p_rut: formattedRut || null,
          p_observaciones: form.elements.observaciones.value.trim() || null
        });
        if (error) throw error;
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

  function setupSocioForm() {
    const form = document.getElementById('public-socio-form');
    const message = document.getElementById('public-socio-message');
    if (!form) return;
    const rut = form.elements.rut;
    const phone = form.elements.telefono;
    rut.dataset.rut = '1';
    rut.addEventListener('input', () => rut.value = formatRut(rut.value));
    phone.addEventListener('input', () => phone.value = formatPhone(phone.value));
    form.onsubmit = async event => {
      event.preventDefault();
      const formattedRut = formatRut(rut.value);
      const dbPhone = phoneDb(phone.value);
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
        nombre_completo: form.elements.nombre.value.trim(),
        rut: formattedRut,
        direccion: form.elements.direccion.value.trim(),
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
      form.reset();
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
    renderCalendar();
    setupRentalRequest();
    setupSocioForm();
    setupChildRegistration();
  });
})();
