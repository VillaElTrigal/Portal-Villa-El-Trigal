(() => {
  'use strict';
  const cfg = window.PORTAL_CONFIG || {};
  if (!window.supabase?.createClient || !cfg.supabaseUrl || !cfg.supabaseAnonKey) return;
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  const esc = v => String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const dateCL = v => v ? new Date(`${v}T12:00:00`).toLocaleDateString('es-CL') : '—';

  function ensureBar() {
    let bar = document.querySelector('#sigve-period-status');
    if (bar) return bar;
    bar = document.createElement('section');
    bar.id = 'sigve-period-status';
    bar.className = 'sigve-period-status loading';
    const main = document.querySelector('main') || document.querySelector('.main') || document.body;
    const title = document.querySelector('#page-title');
    if (title?.parentElement) title.parentElement.insertAdjacentElement('afterend', bar);
    else main.insertAdjacentElement('afterbegin', bar);
    return bar;
  }

  function render(periodo) {
    const bar = ensureBar();
    if (!periodo) {
      bar.className = 'sigve-period-status warning';
      bar.innerHTML = '<strong>⚠️ Sin administración activa</strong><span>Activa un período para trabajar con Finanzas.</span>';
      return;
    }
    bar.className = 'sigve-period-status active';
    bar.innerHTML = `<div><span class="sigve-period-kicker">Administración activa</span><strong>🏛️ ${esc(periodo.nombre)}</strong></div>
      <div><span>Presidente/a</span><strong>${esc(periodo.presidente || 'Sin registrar')}</strong></div>
      <div><span>Vigencia</span><strong>${dateCL(periodo.fecha_inicio)} – ${dateCL(periodo.fecha_termino)}</strong></div>
      <div><span>Estado</span><strong class="sigve-state">● ACTIVA</strong></div>`;
  }

  async function load() {
    const bar = ensureBar();
    bar.innerHTML = '<span>Cargando administración activa…</span>';
    const { data, error } = await sb.from('periodos_administrativos').select('*').eq('estado', 'activo').maybeSingle();
    if (error) {
      bar.className = 'sigve-period-status error';
      bar.innerHTML = `<strong>No se pudo cargar el período activo</strong><span>${esc(error.message)}</span>`;
      return;
    }
    render(data);
  }

  window.addEventListener('sigve:periodo-activo', e => render(e.detail));
  window.addEventListener('sigve:periodos-actualizados', load);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', load);
  else load();
})();
