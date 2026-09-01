
(function(){
  'use strict';

  const cfg = window.PORTAL_CONFIG || {};
  if (!window.supabase || !cfg.supabaseUrl || !cfg.supabaseAnonKey) return;
  const sb = window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey);

  const AUTO_RANGES = [
    { key:'fiestas_patrias', start:'09-10', end:'09-20' },
    { key:'halloween',       start:'10-25', end:'10-31' },
    { key:'navidad',         start:'12-10', end:'12-26' }
  ];

  const THEMES = new Set(['normal','fiestas_patrias','halloween','navidad']);

  function currentAutoTheme(){
    const now = new Date();
    const md = String(now.getMonth()+1).padStart(2,'0') + '-' + String(now.getDate()).padStart(2,'0');
    const found = AUTO_RANGES.find(r => md >= r.start && md <= r.end);
    return found ? found.key : 'normal';
  }

  function removeDecor(){
    document.querySelectorAll('.sigve-seasonal-decor').forEach(x=>x.remove());
  }

  function addDecor(theme){
    removeDecor();
    if(theme === 'normal') return;

    const wrap = document.createElement('div');
    wrap.className = 'sigve-seasonal-decor sigve-seasonal-' + theme;
    wrap.setAttribute('aria-hidden','true');

    if(theme === 'fiestas_patrias'){
      wrap.innerHTML = `
        <div class="sigve-garland">🇨🇱  ·  ✦  ·  🇨🇱  ·  ✦  ·  🇨🇱  ·  ✦  ·  🇨🇱</div>
        <div class="sigve-corner sigve-left">🪁</div>
        <div class="sigve-corner sigve-right">🌺</div>`;
    } else if(theme === 'halloween'){
      wrap.innerHTML = `
        <div class="sigve-garland">🦇　🎃　🕸️　🦇　🎃　🕸️　🦇</div>
        <div class="sigve-corner sigve-left">🎃</div>
        <div class="sigve-corner sigve-right">👻</div>`;
    } else if(theme === 'navidad'){
      wrap.innerHTML = `
        <div class="sigve-garland">✨　🎄　🔔　⭐　🎄　🔔　✨</div>
        <div class="sigve-corner sigve-left">🎁</div>
        <div class="sigve-corner sigve-right">🎄</div>
        <div class="sigve-snow" id="sigve-snow"></div>`;
      const snow = wrap.querySelector('#sigve-snow');
      for(let i=0;i<28;i++){
        const f=document.createElement('i');
        f.textContent='❄';
        f.style.left=(Math.random()*100)+'%';
        f.style.animationDelay=(-Math.random()*12)+'s';
        f.style.animationDuration=(9+Math.random()*9)+'s';
        f.style.fontSize=(9+Math.random()*10)+'px';
        snow.appendChild(f);
      }
    }
    document.body.appendChild(wrap);
  }

  function applyTheme(theme){
    if(!THEMES.has(theme)) theme='normal';
    document.documentElement.dataset.sigveTheme = theme;
    document.body.dataset.sigveTheme = theme;
    addDecor(theme);
  }

  async function loadTheme(){
    let theme='normal';
    try{
      const {data,error}=await sb.rpc('portal_obtener_apariencia');
      if(error) throw error;
      const row=Array.isArray(data)?data[0]:data;
      if(row){
        if(row.modo === 'manual'){
          theme = row.tema_manual || 'normal';
        }else{
          theme = currentAutoTheme();
        }
      }
    }catch(e){
      console.warn('SIGVE apariencia: usando modo automático local.',e);
      theme=currentAutoTheme();
    }
    applyTheme(theme);
  }

  document.addEventListener('DOMContentLoaded',loadTheme);
})();
