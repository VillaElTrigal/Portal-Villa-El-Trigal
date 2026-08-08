(() => {
  'use strict';
  const cfg = window.PORTAL_CONFIG || {};
  const hasSupabase = Boolean(window.supabase?.createClient && cfg.supabaseUrl && cfg.supabaseAnonKey);
  const sb = hasSupabase ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const dateCL = (v) => v ? new Date(`${v}T12:00:00`).toLocaleDateString('es-CL') : '—';
  const money = (v) => new Intl.NumberFormat('es-CL', { style: 'currency', currency: 'CLP', maximumFractionDigits: 0 }).format(Number(v || 0));
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
        ${p.saldo_caja_inicial != null || p.saldo_banco_inicial != null ? `<div class="periodo-balance-row"><span>Saldo inicial caja: <strong>${money(p.saldo_caja_inicial)}</strong></span><span>Saldo inicial banco: <strong>${money(p.saldo_banco_inicial)}</strong></span></div>` : ''}
        ${p.estado === 'cerrado' ? `<div class="periodo-balance-row cierre"><span>Saldo final caja: <strong>${money(p.saldo_caja_cierre)}</strong></span><span>Saldo final banco: <strong>${money(p.saldo_banco_cierre)}</strong></span></div>` : ''}
        ${p.observaciones ? `<p class="periodo-subtle">${esc(p.observaciones)}</p>` : ''}
        <div class="actions">
          <button class="button secondary" data-view-periodo="${p.id}">Ver detalle</button>
          ${editable ? `<button class="button primary" data-edit-periodo="${p.id}">Editar</button>` : ''}
          ${p.estado === 'activo' ? `<button class="button secondary" data-simulate-admin-period="${p.id}">🔎 Simular cierre</button><button class="button danger" data-close-admin-period="${p.id}">Cerrar período</button>` : ''}
        </div>
      </article>`;
    }).join('')}</div>`;
    $$('[data-edit-periodo]', host).forEach(b => b.onclick = () => openForm(rows.find(x => x.id === b.dataset.editPeriodo)));
    $$('[data-view-periodo]', host).forEach(b => b.onclick = () => openDetail(rows.find(x => x.id === b.dataset.viewPeriodo)));
    $$('[data-simulate-admin-period]', host).forEach(b => b.onclick = () => openCloseSimulation(rows.find(x => x.id === b.dataset.simulateAdminPeriod)));
    $$('[data-close-admin-period]', host).forEach(b => b.onclick = () => openClosePeriod(rows.find(x => x.id === b.dataset.closeAdminPeriod)));
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
        <div><span>Creado</span><strong>${p.creado_en ? new Date(p.creado_en).toLocaleString('es-CL') : '—'}</strong></div>
        <div><span>Saldo inicial caja</span><strong>${money(p.saldo_caja_inicial)}</strong></div>
        <div><span>Saldo inicial banco</span><strong>${money(p.saldo_banco_inicial)}</strong></div>
        ${p.estado === 'cerrado' ? `<div><span>Saldo final caja</span><strong>${money(p.saldo_caja_cierre)}</strong></div><div><span>Saldo final banco</span><strong>${money(p.saldo_banco_cierre)}</strong></div><div><span>Cerrado</span><strong>${p.cerrado_en ? new Date(p.cerrado_en).toLocaleString('es-CL') : '—'}</strong></div>` : ''}
      </div>
      <p><strong>Observaciones</strong><br>${esc(p.observaciones || 'Sin observaciones')}</p>
      <div class="periodos-actions"><button class="button secondary" data-close-periodos>Cerrar</button></div>`);
  }


  async function getSimulationSnapshot(p) {
    const [movements, logs] = await Promise.all([
      sb.from('movimientos_financieros').select('id,tipo,monto,fondo,fondo_origen,fondo_destino').eq('periodo_id', p.id),
      sb.from('bitacora_institucional').select('id', { count: 'exact', head: true }).eq('periodo_id', p.id)
    ]);
    if (movements.error) throw movements.error;
    // La bitácora es complementaria. Si la tabla no existe/no responde, la simulación continúa.
    const financialRows = movements.data || [];
    let caja = Number(p.saldo_caja_inicial || 0);
    let banco = Number(p.saldo_banco_inicial || 0);
    let ingresos = 0;
    let gastos = 0;
    let transferencias = 0;
    for (const x of financialRows) {
      const monto = Number(x.monto || 0);
      if (x.tipo === 'ingreso') {
        ingresos += monto;
        if (x.fondo === 'caja') caja += monto;
        if (x.fondo === 'banco') banco += monto;
      } else if (x.tipo === 'gasto') {
        gastos += monto;
        if (x.fondo === 'caja') caja -= monto;
        if (x.fondo === 'banco') banco -= monto;
      } else if (x.tipo === 'transferencia') {
        transferencias += 1;
        if (x.fondo_origen === 'caja') caja -= monto;
        if (x.fondo_origen === 'banco') banco -= monto;
        if (x.fondo_destino === 'caja') caja += monto;
        if (x.fondo_destino === 'banco') banco += monto;
      }
    }
    return {
      movimientos: financialRows.length,
      ingresos,
      gastos,
      transferencias,
      caja,
      banco,
      total: caja + banco,
      bitacora: logs.error ? null : Number(logs.count || 0)
    };
  }

  async function openCloseSimulation(p) {
    if (!p || p.estado !== 'activo') return notify('Solo se puede simular el cierre del período activo.', true);
    const el = modal(`<h3>Simulación de cierre</h3>
      <div class="periodos-simulation-loading">
        <strong>Preparando vista previa…</strong>
        <p>Esta simulación es solo lectura. No modificará ningún dato en Supabase.</p>
      </div>`);
    try {
      const x = await getSimulationSnapshot(p);
      const logText = x.bitacora == null ? 'No disponible' : `${x.bitacora} eventos`;
      el.querySelector('.periodos-modal-card').innerHTML = `<div class="periodos-simulation-head">
          <div><span class="periodos-simulation-badge">🔎 SOLO SIMULACIÓN</span><h3>Vista previa del cierre</h3><p><strong>${esc(p.nombre)}</strong> · ${dateCL(p.fecha_inicio)} → ${dateCL(p.fecha_termino)}</p></div>
        </div>
        <div class="periodos-simulation-safe"><strong>No se cerrará nada.</strong><span>Esta pantalla únicamente consulta los datos actuales y muestra cómo quedaría el período si hoy ejecutaras el cierre real.</span></div>
        <section class="periodos-simulation-grid">
          <div><span>Movimientos financieros</span><strong>${x.movimientos}</strong></div>
          <div><span>Ingresos acumulados</span><strong>${money(x.ingresos)}</strong></div>
          <div><span>Gastos acumulados</span><strong>${money(x.gastos)}</strong></div>
          <div><span>Transferencias</span><strong>${x.transferencias}</strong></div>
          <div><span>Caja al cierre</span><strong>${money(x.caja)}</strong></div>
          <div><span>Banco al cierre</span><strong>${money(x.banco)}</strong></div>
          <div class="periodos-simulation-total"><span>Total institucional</span><strong>${money(x.total)}</strong></div>
          <div><span>Bitácora institucional</span><strong>${esc(logText)}</strong></div>
        </section>
        <section class="periodos-simulation-result">
          <h4>¿Qué ocurriría al cerrar realmente?</h4>
          <ul>
            <li>El período <strong>${esc(p.nombre)}</strong> cambiaría de <em>activo</em> a <em>cerrado</em> y quedaría en modo de solo lectura.</li>
            <li>Se guardarían como referencia final los saldos de Caja y Banco mostrados arriba.</li>
            <li>La administración aparecería en <strong>Archivo Histórico</strong> y se podría abrir su expediente.</li>
            <li>Los movimientos financieros y los eventos de Bitácora que ya están vinculados a este período seguirían asociados a él.</li>
            <li>Los socios continúan como registro comunitario permanente; no se eliminan al cambiar de administración.</li>
          </ul>
        </section>
        <section class="periodos-simulation-limit">
          <strong>Estado actual del Archivo Histórico</strong>
          <p>Finanzas y Bitácora están integradas por período. Documentos, actividades, reservas, inventario, proyectos y acta de entrega todavía figuran en el expediente como módulos pendientes de vinculación histórica específica. La simulación no los presenta como archivados si el sistema actual no los vincula realmente al período.</p>
        </section>
        <div class="periodos-actions"><button type="button" class="button secondary" data-close-periodos>Cerrar simulación</button><button type="button" class="button danger" data-go-real-close>Cerrar período realmente</button></div>`;
      el.querySelector('[data-go-real-close]')?.addEventListener('click', () => { el.remove(); openClosePeriod(p); });
    } catch (error) {
      el.querySelector('.periodos-modal-card').innerHTML = `<h3>No se pudo preparar la simulación</h3><div class="periodos-error">${esc(error.message || error)}</div><div class="periodos-actions"><button type="button" class="button secondary" data-close-periodos>Cerrar</button></div>`;
    }
  }


  function openClosePeriod(p) {
    if (!p || p.estado !== 'activo') return notify('Solo se puede cerrar el período activo.', true);
    const el = modal(`<h3>Cerrar período administrativo</h3>
      <div class="periodos-close-warning">
        <strong>Esta acción es definitiva.</strong>
        <p>El período quedará en modo histórico y ya no se podrá editar. SIGVE guardará una fotografía de los saldos actuales de Caja chica y Cuenta bancaria.</p>
        <p>Los saldos financieros no se duplican ni se reinician: continuarán normalmente y quedarán registrados como referencia inicial del siguiente período activo.</p>
      </div>
      <form id="periodo-close-form">
        <label>Observaciones de entrega<textarea name="observaciones" rows="4" maxlength="1000" placeholder="Ej.: Entrega realizada con documentación y saldos revisados."></textarea></label>
        <label>Para confirmar, escribe <strong>CERRAR</strong><input name="confirmacion" autocomplete="off" required></label>
        <div id="periodo-close-error" class="periodos-error" hidden></div>
        <div class="periodos-actions"><button type="button" class="button secondary" data-close-periodos>Cancelar</button><button class="button danger" type="submit">Cerrar definitivamente</button></div>
      </form>`);
    $('#periodo-close-form', el).onsubmit = async e => {
      e.preventDefault();
      const f = e.currentTarget;
      const errorEl = $('#periodo-close-error', el);
      errorEl.hidden = true;
      if (f.confirmacion.value.trim().toUpperCase() !== 'CERRAR') {
        errorEl.textContent = 'Debes escribir CERRAR para confirmar.';
        errorEl.hidden = false;
        return;
      }
      const submit = f.querySelector('[type="submit"]');
      submit.disabled = true;
      submit.textContent = 'Cerrando…';
      const { error } = await sb.rpc('cerrar_periodo_administrativo', {
        p_periodo_id: p.id,
        p_observaciones: f.observaciones.value.trim() || null
      });
      if (error) {
        errorEl.textContent = error.message;
        errorEl.hidden = false;
        submit.disabled = false;
        submit.textContent = 'Cerrar definitivamente';
        return;
      }
      el.remove();
      notify('Período cerrado y saldos finales registrados correctamente.');
      window.dispatchEvent(new Event('sigve:periodos-actualizados'));
      load();
    };
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
      window.dispatchEvent(new Event('sigve:periodos-actualizados'));
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
