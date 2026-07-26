(() => {
  'use strict';
  const cfg = window.PORTAL_CONFIG || {};
  if (!window.supabase?.createClient || !cfg.supabaseUrl || !cfg.supabaseAnonKey) return;
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);
  const $ = (selector, root = document) => root.querySelector(selector);
  const esc = value => String(value ?? '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const dateCL = value => value ? new Date(`${value}T12:00:00`).toLocaleDateString('es-CL') : '—';
  const money = value => new Intl.NumberFormat('es-CL',{style:'currency',currency:'CLP',maximumFractionDigits:0}).format(Number(value || 0));
  const parseMoney = text => Number(String(text || '').replace(/[^0-9-]/g,'')) || 0;
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

  function periodProgress(periodo){
    if(!periodo?.fecha_inicio || !periodo?.fecha_termino) return 0;
    const start=new Date(`${periodo.fecha_inicio}T00:00:00`).getTime();
    const end=new Date(`${periodo.fecha_termino}T23:59:59`).getTime();
    const now=Date.now();
    if(now<=start) return 0;
    if(now>=end) return 100;
    return Math.max(0,Math.min(100,Math.round(((now-start)/(end-start))*100)));
  }

  function daysRemaining(periodo){
    if(!periodo?.fecha_termino) return null;
    return Math.ceil((new Date(`${periodo.fecha_termino}T23:59:59`).getTime()-Date.now())/86400000);
  }

  function ensureExecutiveDashboard(){
    const dashboard=$('#section-dashboard');
    if(!dashboard) return null;
    let executive=$('#sigve-executive-dashboard');
    if(!executive){
      executive=document.createElement('div');
      executive.id='sigve-executive-dashboard';
      dashboard.insertAdjacentElement('afterbegin',executive);
    }
    return executive;
  }

  function liveStat(id, fallback='0'){
    return $(id)?.textContent?.trim() || fallback;
  }

  function renderDashboard(){
    const executive=ensureExecutiveDashboard();
    if(!executive) return;
    if(!activePeriod){
      executive.innerHTML=`<section class="executive-hero no-period"><div><span class="historico-kicker">Centro de control institucional</span><h3>Configura una administración activa</h3><p>El panel ejecutivo se habilitará cuando exista un período vigente.</p></div><button class="button primary" data-open-periods>Gestionar períodos</button></section>`;
      executive.querySelector('[data-open-periods]')?.addEventListener('click',()=>openSection('periodos'));
      return;
    }
    const progress=periodProgress(activePeriod);
    const remaining=daysRemaining(activePeriod);
    const caja=liveStat('#stat-caja','$0');
    const banco=liveStat('#stat-banco','$0');
    const total=money(parseMoney(caja)+parseMoney(banco));
    executive.innerHTML=`
      <section class="executive-hero">
        <div class="executive-identity">
          <span class="historico-kicker">Centro de control institucional</span>
          <h3>${esc(activePeriod.nombre)}</h3>
          <p>Una vista rápida del estado de la Junta de Vecinos y de la administración vigente.</p>
        </div>
        <div class="executive-progress">
          <div class="executive-progress-head"><span>Avance del período</span><strong>${progress}%</strong></div>
          <div class="executive-progress-track"><i style="width:${progress}%"></i></div>
          <small>${remaining===null?'Vigencia no definida':remaining>=0?`${remaining} días para el término`:`Período vencido hace ${Math.abs(remaining)} días`}</small>
        </div>
      </section>
      <section class="executive-metrics">
        <article><span class="metric-icon">👥</span><div><small>Socios activos</small><strong>${liveStat('#stat-socios')}</strong></div><button data-go="socios" aria-label="Abrir socios">→</button></article>
        <article><span class="metric-icon">💰</span><div><small>Disponible total</small><strong>${total}</strong></div><button data-go="finanzas" aria-label="Abrir finanzas">→</button></article>
        <article><span class="metric-icon">🏠</span><div><small>Próximas reservas</small><strong>${liveStat('#stat-reservas')}</strong></div><button data-go="reservas-v7" aria-label="Abrir reservas">→</button></article>
        <article><span class="metric-icon">📄</span><div><small>Documentos</small><strong>${liveStat('#stat-documentos')}</strong></div><button data-go="documentos" aria-label="Abrir documentos">→</button></article>
      </section>
      <section class="executive-columns">
        <article class="panel executive-finance">
          <div class="panel-heading"><div><span class="historico-kicker">Resumen financiero</span><h3>Fondos disponibles</h3></div><button class="button secondary" data-go="finanzas">Abrir Finanzas</button></div>
          <div class="fund-row"><span>Caja chica</span><strong>${caja}</strong></div>
          <div class="fund-row"><span>Cuenta bancaria</span><strong>${banco}</strong></div>
          <div class="fund-row total"><span>Total institucional</span><strong>${total}</strong></div>
        </article>
        <article class="panel executive-actions">
          <span class="historico-kicker">Accesos rápidos</span><h3>Gestiones frecuentes</h3>
          <div class="quick-action-grid">
            <button data-go="finanzas">＋ Registrar movimiento</button>
            <button data-go="socios">＋ Gestionar socios</button>
            <button data-go="reservas-v7">＋ Revisar sede</button>
            <button data-go="historico">📚 Archivo histórico</button>
          </div>
        </article>
      </section>
      <section class="panel institutional-timeline">
        <div class="panel-heading"><div><span class="historico-kicker">Continuidad institucional</span><h3>Línea de tiempo de la administración</h3></div><span class="timeline-status">En curso</span></div>
        <div class="timeline-track">
          <div class="timeline-point done"><i></i><strong>Inicio</strong><span>${dateCL(activePeriod.fecha_inicio)}</span></div>
          <div class="timeline-line"><i style="width:${progress}%"></i></div>
          <div class="timeline-point current"><i></i><strong>Hoy</strong><span>${new Date().toLocaleDateString('es-CL')}</span></div>
          <div class="timeline-line remaining"></div>
          <div class="timeline-point"><i></i><strong>Término</strong><span>${dateCL(activePeriod.fecha_termino)}</span></div>
        </div>
      </section>`;
    executive.querySelectorAll('[data-go]').forEach(btn=>btn.addEventListener('click',()=>openSection(btn.dataset.go)));
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
    setTimeout(renderDashboard,700);
  }

  const statObserver=new MutationObserver(()=>{ if(activePeriod) renderDashboard(); });
  function observeStats(){
    ['#stat-socios','#stat-reservas','#stat-documentos','#stat-caja','#stat-banco'].forEach(sel=>{const el=$(sel);if(el)statObserver.observe(el,{childList:true,subtree:true,characterData:true});});
  }

  window.addEventListener('sigve:periodo-activo',event=>{activePeriod=event.detail||null;renderBar(activePeriod);renderDashboard();});
  window.addEventListener('sigve:periodos-actualizados',loadPeriods);
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',()=>{observeStats();loadPeriods();}); else {observeStats();loadPeriods();}
})();
