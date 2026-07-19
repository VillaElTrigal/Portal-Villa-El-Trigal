(() => {
  const SHEET_CSV_URL = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vQo8YdCw3rOw3IOtFxfKfYgu1yabOF3ypf2Nbrl3k546PToTmiGIkzHMTW1DD1LHevEaOYtWYHmuijx/pub?gid=0&single=true&output=csv';

  const fallbackReservedDates = new Set([
    '2026-07-25','2026-07-26','2026-08-01','2026-08-15',
    '2026-09-13','2026-10-17','2026-11-14'
  ]);

  const monthNames = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
  const dayNames = ['Lu','Ma','Mi','Ju','Vi','Sá','Do'];
  let sheetEntries = new Map();

  function parseCsv(text) {
    const rows = [];
    let row = [];
    let value = '';
    let quoted = false;

    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const next = text[i + 1];

      if (char === '"' && quoted && next === '"') {
        value += '"';
        i++;
      } else if (char === '"') {
        quoted = !quoted;
      } else if (char === ',' && !quoted) {
        row.push(value.trim());
        value = '';
      } else if ((char === '\n' || char === '\r') && !quoted) {
        if (char === '\r' && next === '\n') i++;
        row.push(value.trim());
        if (row.some(cell => cell !== '')) rows.push(row);
        row = [];
        value = '';
      } else {
        value += char;
      }
    }

    row.push(value.trim());
    if (row.some(cell => cell !== '')) rows.push(row);
    return rows;
  }

  function normalizeHeader(value) {
    return String(value || '')
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .trim()
      .toLowerCase();
  }

  function normalizeDate(value) {
    const raw = String(value || '').trim();
    if (!raw) return null;

    let match = raw.match(/^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$/);
    if (match) {
      const [, year, month, day] = match;
      return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    }

    match = raw.match(/^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$/);
    if (match) {
      const [, day, month, year] = match;
      return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    }

    return null;
  }

  function normalizeStatus(value) {
    const status = normalizeHeader(value);
    if (status.includes('reserv')) return 'reserved';
    if (status.includes('zumba')) return 'zumba';
    if (status.includes('dispon')) return 'available';
    if (status.includes('bloque')) return 'reserved';
    return 'reserved';
  }

  async function loadSheet() {
    const statusText = document.getElementById('calendar-sync-status');
    try {
      const separator = SHEET_CSV_URL.includes('?') ? '&' : '?';
      const response = await fetch(`${SHEET_CSV_URL}${separator}v=${Date.now()}`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`Respuesta ${response.status}`);

      const rows = parseCsv(await response.text());
      if (rows.length < 1) return;

      const headers = rows[0].map(normalizeHeader);
      const dateIndex = headers.findIndex(h => h === 'fecha' || h.includes('fecha'));
      const statusIndex = headers.findIndex(h => h === 'estado' || h === 'tipo' || h.includes('estado'));
      const noteIndex = headers.findIndex(h => h.includes('observ') || h.includes('descripcion') || h.includes('detalle'));

      if (dateIndex === -1) throw new Error('La hoja no contiene una columna llamada Fecha');

      const parsed = new Map();
      rows.slice(1).forEach(row => {
        const iso = normalizeDate(row[dateIndex]);
        if (!iso) return;
        const status = statusIndex >= 0 ? normalizeStatus(row[statusIndex]) : 'reserved';
        const note = noteIndex >= 0 ? String(row[noteIndex] || '').trim() : '';
        parsed.set(iso, { status, note });
      });

      sheetEntries = parsed;
      if (statusText) statusText.textContent = 'Calendario actualizado desde la hoja de reservas.';
    } catch (error) {
      console.warn('No fue posible leer Google Sheets. Se mostrarán las fechas incorporadas.', error);
      if (statusText) statusText.textContent = 'No se pudo actualizar la hoja en este momento; se muestran las fechas guardadas en el portal.';
    }
  }

  function isoDate(year, month, day) {
    return `${year}-${String(month + 1).padStart(2,'0')}-${String(day).padStart(2,'0')}`;
  }

  function selectRentalDate(dateIso, readable) {
    const message = `Hola, me gustaría solicitar el arriendo de la Sede Social Villa El Trigal para el día ${readable}. Realizaré o adjuntaré el comprobante del abono de $10.000. Entiendo que la reserva quedará confirmada únicamente cuando la Junta de Vecinos responda por WhatsApp. Muchas gracias.`;
    const link = document.getElementById('rental-whatsapp');
    link.href = `https://wa.me/56974596793?text=${encodeURIComponent(message)}`;
    document.getElementById('selected-date-text').innerHTML = `Fecha seleccionada: <strong>${readable}</strong>. Presiona el botón para enviar la solicitud.`;
    document.querySelectorAll('.calendar-day.selected').forEach(el => el.classList.remove('selected'));
    document.querySelector(`[data-date="${dateIso}"]`)?.classList.add('selected');
  }

  function getStatus(iso, weekday) {
    const sheet = sheetEntries.get(iso);
    if (sheet) return sheet;
    if (fallbackReservedDates.has(iso)) return { status: 'reserved', note: 'Fecha reservada' };
    if (weekday === 2 || weekday === 4) return { status: 'zumba', note: 'Clase de Zumba' };
    return { status: 'available', note: '' };
  }

  function renderCalendars() {
    const container = document.getElementById('rental-calendars');
    if (!container) return;
    container.innerHTML = '';

    for (let month = 6; month <= 11; month++) {
      const card = document.createElement('article');
      card.className = 'month-card';
      card.innerHTML = `<h4>${monthNames[month]} 2026</h4>`;
      const days = document.createElement('div');
      days.className = 'month-days';

      dayNames.forEach(name => {
        const label = document.createElement('span');
        label.className = 'day-name';
        label.textContent = name;
        days.appendChild(label);
      });

      const first = new Date(2026, month, 1);
      const offset = (first.getDay() + 6) % 7;
      for (let i = 0; i < offset; i++) {
        const blank = document.createElement('span');
        blank.className = 'calendar-blank';
        days.appendChild(blank);
      }

      const count = new Date(2026, month + 1, 0).getDate();
      for (let day = 1; day <= count; day++) {
        const date = new Date(2026, month, day);
        const iso = isoDate(2026, month, day);
        const readable = `${day} de ${monthNames[month].toLowerCase()} de 2026`;
        const current = getStatus(iso, date.getDay());
        const button = document.createElement('button');
        button.type = 'button';
        button.className = `calendar-day ${current.status}`;
        button.textContent = day;
        button.dataset.date = iso;
        button.title = current.note || (current.status === 'available' ? 'Disponible para consultar' : 'Fecha no disponible');

        if (current.status === 'available') {
          button.addEventListener('click', () => selectRentalDate(iso, readable));
          button.setAttribute('aria-label', `${readable}: disponible para consultar`);
        } else {
          button.disabled = true;
          button.setAttribute('aria-label', `${readable}: ${current.note || 'no disponible'}`);
        }
        days.appendChild(button);
      }

      card.appendChild(days);
      container.appendChild(card);
    }
  }

  document.addEventListener('DOMContentLoaded', async () => {
    renderCalendars();
    await loadSheet();
    renderCalendars();
  });
})();
