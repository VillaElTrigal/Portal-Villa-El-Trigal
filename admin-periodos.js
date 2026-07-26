(() => {
  'use strict';
  const cfg = window.PORTAL_CONFIG || {};
  const hasSupabase = Boolean(window.supabase?.createClient && cfg.supabaseUrl && cfg.supabaseAnonKey);
  const sb = hasSupabase ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const dateCL = (v) => v ? new Date(`${v}T12:00:00`).toLocaleDateString('es-CL') : '—';
  let rows = [];

  function notify(text, isError = false) {
    const el = $('#global-message');
    if (el) {
      el.textContent = text;
      el.className = `form-message ${isError ? 'error' : 'success'}`;
      setTimeout(() => { if (el.textContent === text) el.textContent = ''; }, 5000);
    } else alert(text);
  }

  function addMenu() {
    const nav = $('.sidebar nav');
    if (!nav || nav.querySelector('[data-section="periodos"]')) return;
    const directiva = nav.querySelector('[data-section="directiva"]');
    const html = '<button data-section="periodos">🏛️ Períodos administrativos</button>';
    directiva ? directiva.insertAdjacentHTML('beforebegin', html) : nav.insertAdjacentHTML('beforeend', html);
  }

  function progressFor(p) {
    const start = new Date(`${p.fecha_inicio}T12:00:00`).getTime();
    const end = new Date(`${p.fecha_termino}T12:00:00`).getTime();
    const now = Date.now();
    if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return 0;
    return Math.max(0, Math.min(100, Math.round(((now - start) / (end - start)) * 100)));
  }

  function render() {
    const host = $('#periodos-list');
    if (!host) return;
    if (!rows.length) {
      host.innerHTML = '<div class="panel periodos-empty"><h3>Aún no existen períodos administrativos</h3><p>Crea el primer período para comenzar a organizar la historia de la Junta de Vecinos.</p></div>';
      return;
    }
    const ordered = [...rows].sort((a,b) => String(b.fecha_inicio).localeCompare(String(a.fecha_inicio)));
    host.innerHTML = `<div class="periodos-grid">${ordered.map(p => {
      const progress = progressFor(p);
      const editable = p.estado !== 'cerrado';
      return `<article class="periodo-card ${esc(p.estado)}">
        <span class="periodo-badge ${esc(p.estado)}">${esc(p.estado)}</span>
        <h4>${esc(p.nombre)}</h4>
        <div class="periodo-subtle">${dateCL(p.fecha_inicio)} → ${dateCL(p.fecha_termino)}</div>
        <div class="periodo-meta">
          <div><span>Presidente/a</span><strong>${esc(p.presidente || 'Sin registrar')}</strong></div>
          <div><span>Estado</span><strong>${esc(p.estado)}</strong></div>
        </div>
        ${p.estado === 'activo' ? `<div class="periodo-subtle">Avance estimado del mandato: ${progress}%</div><div class="periodo-progress"><span style="width:${progress}%"></span></div>` : ''}
        ${p.observaciones ? `<p class="periodo-subtle">${esc(p.observaciones)}</p>` : ''}
        <div class="actions">
          <button class="button secondary" data-view-periodo="${p.id}">Ver detalle</button>
          ${editable ? `<button class="button primary" data-edit-periodo="${p.id}">Editar</button>` : ''}
        </div>
      </article>`;
    }).join('')}</div>`;
    $$('[data-edit-periodo]', host).forEach(b => b.onclick = () => openForm(rows.find(x => x.id === b.dataset.editPeriodo)));
    $$('[data-view-periodo]', host).forEach(b => b.onclick = () => openDetail(rows.find(x => x.id === b.dataset.viewPeriodo)));
  }

  async function load() {
    const host = $('#periodos-list');
    if (!sb) {
      if (host) host.innerHTML = '<div class="panel"><h3>No se pudo iniciar el módulo</h3><p>Falta la configuración de conexión con Supabase.</p></div>';
      return;
    }
    if (host) host.innerHTML = '<div class="periodos-loading">Cargando períodos…</div>';
    const { data, error } = await sb.from('periodos_administrativos').select('*').order('fecha_inicio', { ascending: false });
    if (error) {
      if (host) host.innerHTML = `<div class="panel"><h3>No se pudo cargar el módulo</h3><p>${esc(error.message)}</p><p class="help">Ejecuta primero el archivo SQL incluido en la actualización.</p></div>`;
      return;
    }
    rows = data || [];
    render();
  }

  function modal(content) {
    const el = document.createElement('div');
    el.className = 'periodos-modal';
    el.innerHTML = `<div class="periodos-modal-card">${content}</div>`;
    el.onclick = e => { if (e.target === el || e.target.closest('[data-close-periodos]')) el.remove(); };
    document.body.appendChild(el);
    return el;
  }

  function openDetail(p) {
    if (!p) return;
    modal(`<h3>${esc(p.nombre)}</h3>
      <p><span class="periodo-badge ${esc(p.estado)}">${esc(p.estado)}</span></p>
      <div class="periodo-meta">
        <div><span>Fecha de inicio</span><strong>${dateCL(p.fecha_inicio)}</strong></div>
        <div><span>Fecha de término</span><strong>${dateCL(p.fecha_termino)}</strong></div>
        <div><span>Presidente/a</span><strong>${esc(p.presidente || 'Sin registrar')}</strong></div>
        <div><span>Creado</span><strong>${new Date(p.creado_en).toLocaleString('es-CL')}</strong></div>
      </div>
      <p><strong>Observaciones</strong><br>${esc(p.observaciones || 'Sin observaciones')}</p>
      <div class="periodos-actions"><button class="button secondary" data-close-periodos>Cerrar</button></div>`);
  }

  function openForm(p = {}) {
    if (p.estado === 'cerrado') return notify('Los períodos cerrados son de solo lectura.', true);
    const isEdit = Boolean(p.id);
    const el = modal(`<h3>${isEdit ? 'Editar' : 'Crear'} período administrativo</h3>
      <form id="periodo-form">
        <div class="periodos-form-grid">
          <label>Nombre del período<input name="nombre" required maxlength="80" placeholder="Ej.: Directiva 2024–2027" value="${esc(p.nombre || '')}"></label>
          <label>Estado<select name="estado" required>
            <option value="programado" ${p.estado === 'programado' ? 'selected' : ''}>Programado</option>
            <option value="activo" ${p.estado === 'activo' ? 'selected' : ''}>Activo</option>
          </select></label>
          <label>Fecha de inicio<input name="fecha_inicio" type="date" required value="${esc(p.fecha_inicio || '')}"></label>
          <label>Fecha de término<input name="fecha_termino" type="date" required value="${esc(p.fecha_termino || '')}"></label>
          <label class="full">Presidente/a del período<input name="presidente" maxlength="120" value="${esc(p.presidente || '')}" placeholder="Opcional por ahora"></label>
          <label class="full">Observaciones<textarea name="observaciones" rows="4" maxlength="1000">${esc(p.observaciones || '')}</textarea></label>
        </div>
        <div id="periodo-form-error" class="periodos-error" hidden></div>
        <div class="periodos-actions"><button type="button" class="button secondary" data-close-periodos>Cancelar</button><button class="button primary" type="submit">Guardar período</button></div>
      </form>`);
    $('#periodo-form', el).onsubmit = async e => {
      e.preventDefault();
      const f = e.currentTarget;
      const errorEl = $('#periodo-form-error', el);
      errorEl.hidden = true;
      if (f.fecha_termino.value < f.fecha_inicio.value) {
        errorEl.textContent = 'La fecha de término no puede ser anterior a la fecha de inicio.';
        errorEl.hidden = false;
        return;
      }
      if (!sb) {
        errorEl.textContent = 'No existe conexión con Supabase.';
        errorEl.hidden = false;
        return;
      }
      const { data: { user } } = await sb.auth.getUser();
      const payload = {
        nombre: f.nombre.value.trim(),
        estado: f.estado.value,
        fecha_inicio: f.fecha_inicio.value,
        fecha_termino: f.fecha_termino.value,
        presidente: f.presidente.value.trim() || null,
        observaciones: f.observaciones.value.trim() || null,
        actualizado_por: user?.id || null
      };
      const result = isEdit
        ? await sb.from('periodos_administrativos').update(payload).eq('id', p.id)
        : await sb.from('periodos_administrativos').insert({...payload, creado_por: user?.id || null});
      if (result.error) {
        errorEl.textContent = result.error.code === '23505'
          ? 'Ya existe un período activo. Debes dejarlo como programado o cerrar el período activo en una futura actualización.'
          : result.error.message;
        errorEl.hidden = false;
        return;
      }
      el.remove();
      notify('Período administrativo guardado correctamente.');
      load();
    };
  }

  function bind() {
    addMenu();
    $('#new-periodo')?.addEventListener('click', () => openForm());
    document.addEventListener('click', e => {
      const b = e.target.closest('[data-section="periodos"]');
      if (!b) return;
      e.stopImmediatePropagation();
      $$('[data-section]').forEach(x => x.classList.toggle('active', x === b));
      $$('.admin-section').forEach(s => { s.hidden = s.id !== 'section-periodos'; });
      const title = $('#page-title');
      if (title) title.textContent = 'Períodos administrativos';
      load();
    }, true);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', bind);
  else bind();
})();
