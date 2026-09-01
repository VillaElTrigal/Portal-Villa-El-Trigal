
(function(){
  'use strict';
  const cfg=window.PORTAL_CONFIG||{};
  const THEMES=new Set(['normal','fiestas_patrias','halloween','navidad']);
  const LABELS={
    normal:'Modo normal',
    fiestas_patrias:'Fiestas Patrias',
    halloween:'Halloween',
    navidad:'Navidad'
  };
  const RANGES=[
    {key:'fiestas_patrias',start:'09-10',end:'09-20'},
    {key:'halloween',start:'10-25',end:'10-31'},
    {key:'navidad',start:'12-10',end:'12-26'}
  ];

  function autoTheme(){
    const d=new Date();
    const md=String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
    return (RANGES.find(x=>md>=x.start&&md<=x.end)||{}).key||'normal';
  }

  function portalType(){
    const p=(location.pathname.split('/').pop()||'index.html').toLowerCase();
    if(p.includes('admin')) return 'admin';
    if(p.includes('portal-socio')) return 'socio';
    return 'principal';
  }

  function makeAtmosphere(theme){
    document.querySelectorAll('.sigve-theme-atmosphere,.sigve-theme-banner').forEach(x=>x.remove());
    if(theme==='normal') return;

    const a=document.createElement('div');
    a.className='sigve-theme-atmosphere';
    a.setAttribute('aria-hidden','true');

    if(theme==='fiestas_patrias'){
      // El diseño patrio vive en header/hero/tarjetas mediante CSS.
      // No usamos banderas flotantes para evitar saltos de capas al hacer scroll.
      a.innerHTML='';
    }
    if(theme==='halloween'){
      a.innerHTML=`
        <div class="theme-halloween-corner">🎃</div>
        <div class="theme-halloween-bats">⌁ ⌁ ⌁</div>`;
    }
    if(theme==='navidad'){
      a.innerHTML=`
        <div class="theme-lights">${'<b></b>'.repeat(32)}</div>
        <div class="theme-snow">${'<i>❄</i>'.repeat(48)}</div>`;
    }
    document.body.appendChild(a);
  }


  function renderSeasonHero(theme){
    document.querySelectorAll('.sigve-season-scene').forEach(x=>x.remove());
    const hero=document.querySelector('.hero');
    if(!hero || theme==='normal') return;
    const s=document.createElement('div');
    s.className='sigve-season-scene';
    s.setAttribute('aria-hidden','true');
    if(theme==='fiestas_patrias'){
      s.innerHTML='<div class="sigve-season-garland"></div><div class="season-fp-flower"></div><div class="season-fp-kite"></div><div class="season-fp-guitar"></div>';
    }else if(theme==='halloween'){
      s.innerHTML='<div class="season-hw-web"></div><div class="season-hw-bats">⌁ ⌁ ⌁</div><div class="season-hw-castle"></div><div class="season-hw-pumpkin"></div>';
    }else if(theme==='navidad'){
      s.innerHTML='<div class="season-nv-house"></div><div class="season-nv-tree"></div>';
    }
    hero.prepend(s);
  }

  function apply(theme){
    if(!THEMES.has(theme)) theme='normal';
    document.documentElement.dataset.sigveTheme=theme;
    document.documentElement.dataset.sigvePortal=portalType();
    document.body.dataset.sigveTheme=theme;
    document.body.dataset.sigvePortal=portalType();
    document.body.classList.add('sigve-theme-ready');
    makeAtmosphere(theme);
    renderSeasonHero(theme);
    window.dispatchEvent(new CustomEvent('sigve-theme-change',{detail:{theme,label:LABELS[theme]}}));
  }

  async function load(){
    let theme=autoTheme();
    try{
      if(window.supabase&&cfg.supabaseUrl&&cfg.supabaseAnonKey){
        const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
        const {data,error}=await sb.rpc('portal_obtener_apariencia');
        if(!error&&data){
          const row=Array.isArray(data)?data[0]:data;
          if(row) theme=row.modo==='manual'?(row.tema_manual||'normal'):autoTheme();
        }
      }
    }catch(e){ console.warn('Apariencia SIGVE:',e); }
    apply(theme);
  }

  document.addEventListener('DOMContentLoaded',load);
})();
