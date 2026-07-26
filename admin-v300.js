(() => {
  'use strict';
  const cfg = window.PORTAL_CONFIG || {};
  if (!window.supabase?.createClient || !cfg.supabaseUrl || !cfg.supabaseAnonKey) return;
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = value => String(value ?? '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const dateCL = value => value ? new Date(`${value}T12:00:00`).toLocaleDateString('es-CL') : '—';
  const money = value => new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(value || 0));
  let activePeriod = null;
  let closedPeriods = [];

  function ensureBar(){
    let bar=$('#sigve-period-status');
    if(bar) return bar;
    bar=document.createElement('section');
    bar.id='sigve-period-status';
    bar.className='sigve-period-status loading';
    const topbar=$('.topbar');
    if(topbar) topbar.insertAdjacentElement('afterend',bar);
    else (document.querySelector('main')||document.body).insertAdjacentElement('afterbegin',bar);
    return bar;
  }

  function renderBar(periodo){
    const bar=ensureBar();
    if(!periodo){
      bar.className='sigve-period-status warning';
      bar.innerHTML='<div><strong>⚠️ Sin administración activa</strong><span>Activa un período para registrar operaciones.</span></div>';
      return;
    }
    bar.className='sigve-period-status active';
    bar.innerHTML=`<div class="sigve-main-period"><span class="sigve-period-kicker">Administración activa</span><strong>🏛️ ${esc(periodo.nombre)}</strong></div><div><span>Presidente/a</span><strong>${esc(periodo.presidente||'Sin registrar')}</strong></div><div><span>Vigencia</span><strong>${dateCL(periodo.fecha_inicio)} – ${dateCL(periodo.fecha_termino)}</strong></div><div><span>Estado</span><strong class="sigve-state">● ACTIVA</strong></div>`;
  }

  function openSection(name){ document.querySelector(`[data-section="${name}"]`)?.click(); }

  function renderDashboard(){
    const dashboard=$('#section-dashboard');
    if(!dashboard) return;
    let card=$('#sigve-dashboard-period');
    if(!card){
      card=document.createElement('div');
      card.id='sigve-dashboard-period';
      card.className='panel sigve-dashboard-period';
      const stats=dashboard.querySelector('.stats');
      stats ? stats.insertAdjacentElement('afterend',card) : dashboard.insertAdjacentElement('afterbegin',card);
    }
    if(!activePeriod){
      card.innerHTML='<div><h3>Administración institucional</h3><p class="help">No existe un período activo.</p></div><button class="button primary" data-open-periods>Gestionar períodos</button>';
      card.querySelector('[data-open-periods]')?.addEventListener('click',()=>openSection('periodos'));
      return;
    }
    card.innerHTML=`<div><span class="historico-kicker">Administración vigente</span><h3>${esc(activePeriod.nombre)}</h3><p class="help">${dateCL(activePeriod.fecha_inicio)} al ${dateCL(activePeriod.fecha_termino)} · Presidente/a: ${esc(activePeriod.presidente||'Sin registrar')}</p></div><div class="sigve-dashboard-actions"><div><span>Períodos archivados</span><strong>${closedPeriods.length}</strong></div><button class="button secondary" data-open-history>Ver archivo histórico</button></div>`;
    card.querySelector('[data-open-history]')?.addEventListener('click',()=>openSection('historico'));
  }

  function renderHistory(){
    const host=$('#historico-list');
    const summary=$('#historico-summary');
    if(!host||!summary) return;
    summary.innerHTML=`<div class="stat"><span>Administraciones archivadas</span><strong>${closedPeriods.length}</strong></div><div class="stat"><span>Último cierre de caja</span><strong>${closedPeriods.length?money(closedPeriods[0].saldo_caja_cierre):'—'}</strong></div><div class="stat"><span>Último cierre bancario</span><strong>${closedPeriods.length?money(closedPeriods[0].saldo_banco_cierre):'—'}</strong></div>`;
    if(!closedPeriods.length){
      host.innerHTML='<div class="panel historico-empty"><div class="historico-empty-icon">📚</div><h3>El archivo todavía está vacío</h3><p>Cuando una administración sea cerrada aparecerá aquí en modo de consulta.</p></div>';
      return;
    }
    host.innerHTML=`<div class="historico-grid">${closedPeriods.map(p=>`<article class="historico-card"><div class="historico-card-top"><span class="periodo-badge cerrado">Archivada</span><span class="historico-readonly">🔒 Solo lectura</span></div><h4>${esc(p.nombre)}</h4><p>${dateCL(p.fecha_inicio)} → ${dateCL(p.fecha_termino)}</p><dl><div><dt>Presidente/a</dt><dd>${esc(p.presidente||'Sin registrar')}</dd></div><div><dt>Caja final</dt><dd>${money(p.saldo_caja_cierre)}</dd></div><div><dt>Banco final</dt><dd>${money(p.saldo_banco_cierre)}</dd></div><div><dt>Total final</dt><dd>${money(p.saldo_total_cierre)}</dd></div></dl><button class="button secondary" data-history-detail="${esc(p.id)}">Ver expediente</button></article>`).join('')}</div>`;
    host.querySelectorAll('[data-history-detail]').forEach(button=>button.addEventListener('click',()=>showHistoryDetail(button.dataset.historyDetail)));
  }

  function showHistoryDetail(id){
    const p=closedPeriods.find(item=>String(item.id)===String(id));
    if(!p) return;
    const dialog=document.createElement('dialog');
    dialog.className='periodo-dialog historico-dialog';
    dialog.innerHTML=`<form method="dialog"><div class="historico-dialog-header"><div><span class="historico-kicker">Expediente histórico</span><h3>${esc(p.nombre)}</h3></div><button class="dialog-x" value="cancel" aria-label="Cerrar">×</button></div><div class="historico-mode-banner">👁 MODO CONSULTA · Esta administración no se puede modificar</div><div class="periodo-detail-grid"><div><span>Fecha de inicio</span><strong>${dateCL(p.fecha_inicio)}</strong></div><div><span>Fecha de término</span><strong>${dateCL(p.fecha_termino)}</strong></div><div><span>Presidente/a</span><strong>${esc(p.presidente||'Sin registrar')}</strong></div><div><span>Estado</span><strong>Archivada</strong></div><div><span>Saldo final de caja</span><strong>${money(p.saldo_caja_cierre)}</strong></div><div><span>Saldo final bancario</span><strong>${money(p.saldo_banco_cierre)}</strong></div><div><span>Saldo total final</span><strong>${money(p.saldo_total_cierre)}</strong></div><div><span>Fecha de cierre</span><strong>${p.cerrado_en?new Date(p.cerrado_en).toLocaleString('es-CL'):'—'}</strong></div></div>${p.cierre_observaciones?`<div class="panel historico-observations"><strong>Observaciones del cierre</strong><p>${esc(p.cierre_observaciones)}</p></div>`:''}<div class="actions"><button class="button secondary" value="cancel">Cerrar expediente</button></div></form>`;
    document.body.appendChild(dialog);
    dialog.addEventListener('close',()=>dialog.remove());
    dialog.showModal();
  }

  async function loadPeriods(){
    const bar=ensureBar();
    bar.innerHTML='<span>Cargando administración institucional…</span>';
    const {data,error}=await sb.from('periodos_administrativos').select('*').order('fecha_inicio',{ascending:false});
    if(error){
      bar.className='sigve-period-status error';
      bar.innerHTML=`<div><strong>No se pudieron cargar los períodos</strong><span>${esc(error.message)}</span></div>`;
      return;
    }
    const rows=data||[];
    activePeriod=rows.find(p=>p.estado==='activo')||null;
    closedPeriods=rows.filter(p=>p.estado==='cerrado');
    renderBar(activePeriod);
    renderDashboard();
    renderHistory();
  }

  window.addEventListener('sigve:periodo-activo',event=>{activePeriod=event.detail||null;renderBar(activePeriod);renderDashboard();});
  window.addEventListener('sigve:periodos-actualizados',loadPeriods);
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',loadPeriods); else loadPeriods();
})();
