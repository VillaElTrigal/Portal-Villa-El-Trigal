(() => {
  'use strict';
  const COUNTRIES = [
    ['AR','🇦🇷','Argentina','54'],['BO','🇧🇴','Bolivia','591'],['BR','🇧🇷','Brasil','55'],['CL','🇨🇱','Chile','56'],['CO','🇨🇴','Colombia','57'],['CR','🇨🇷','Costa Rica','506'],['CU','🇨🇺','Cuba','53'],['DO','🇩🇴','Rep. Dominicana','1'],['EC','🇪🇨','Ecuador','593'],['SV','🇸🇻','El Salvador','503'],['GT','🇬🇹','Guatemala','502'],['HT','🇭🇹','Haití','509'],['HN','🇭🇳','Honduras','504'],['MX','🇲🇽','México','52'],['NI','🇳🇮','Nicaragua','505'],['PA','🇵🇦','Panamá','507'],['PY','🇵🇾','Paraguay','595'],['PE','🇵🇪','Perú','51'],['PR','🇵🇷','Puerto Rico','1'],['UY','🇺🇾','Uruguay','598'],['VE','🇻🇪','Venezuela','58'],
    ['US','🇺🇸','Estados Unidos','1'],['CA','🇨🇦','Canadá','1'],['ES','🇪🇸','España','34'],['PT','🇵🇹','Portugal','351'],['FR','🇫🇷','Francia','33'],['IT','🇮🇹','Italia','39'],['DE','🇩🇪','Alemania','49'],['GB','🇬🇧','Reino Unido','44'],['IE','🇮🇪','Irlanda','353'],['NL','🇳🇱','Países Bajos','31'],['BE','🇧🇪','Bélgica','32'],['CH','🇨🇭','Suiza','41'],['SE','🇸🇪','Suecia','46'],['NO','🇳🇴','Noruega','47'],['DK','🇩🇰','Dinamarca','45'],
    ['CN','🇨🇳','China','86'],['JP','🇯🇵','Japón','81'],['KR','🇰🇷','Corea del Sur','82'],['IN','🇮🇳','India','91'],['PH','🇵🇭','Filipinas','63'],['AU','🇦🇺','Australia','61'],['NZ','🇳🇿','Nueva Zelanda','64'],['ZA','🇿🇦','Sudáfrica','27']
  ];
  const digits = v => String(v || '').replace(/\D/g, '');
  const css = document.createElement('style');
  css.textContent = `
    .sigve-phone-wrap{display:flex;flex-direction:column;gap:.55rem;width:100%}
    .sigve-phone-row{display:flex;align-items:stretch;gap:.55rem;width:100%}
    .sigve-phone-row input{min-width:0;flex:1}
    .sigve-phone-prefix{display:flex;align-items:center;justify-content:center;white-space:nowrap;font-weight:700;color:#334155;background:#f8fafc;border:1px solid #cbd5e1;border-radius:10px;padding:0 .8rem;min-width:78px}
    .sigve-phone-foreign{display:inline-flex;align-items:center;gap:.5rem;font-size:.86rem;font-weight:600;color:#334155;cursor:pointer;width:max-content;max-width:100%}
    .sigve-phone-foreign input{width:16px!important;height:16px!important;min-width:16px!important;flex:0 0 16px!important;margin:0;accent-color:#198754}
    .sigve-phone-intl{display:flex;align-items:center;gap:.55rem;width:100%}
    .sigve-phone-countrybox{display:flex;align-items:center;gap:.45rem;position:relative;flex:0 0 230px;min-width:0}
    .sigve-phone-flag{width:25px;height:18px;object-fit:cover;border-radius:3px;box-shadow:0 0 0 1px rgba(15,23,42,.12);flex:0 0 auto}
    .sigve-phone-country{width:100%;min-width:0;height:44px;padding:.55rem 2rem .55rem .65rem;border:1px solid #cbd5e1;border-radius:10px;background:#fff;color:#0f172a;font:inherit}
    .sigve-phone-country:focus,.sigve-phone-code:focus{outline:none;border-color:#1f9d67;box-shadow:0 0 0 3px rgba(31,157,103,.12)}
    .sigve-phone-help{font-size:.78rem;color:#64748b;line-height:1.35;margin-top:-.1rem}
    .sigve-phone-code{height:44px;width:105px!important;flex:0 0 105px!important;border-radius:10px!important}
    @media(max-width:600px){
      .sigve-phone-row,.sigve-phone-intl{flex-wrap:wrap}
      .sigve-phone-countrybox{flex:1 1 100%}
      .sigve-phone-code{flex:0 0 100%!important;width:100%!important}
      .sigve-phone-prefix{min-height:44px}
    }`;
  document.head.appendChild(css);

  function inferForeign(raw) {
    const d = digits(raw).replace(/^0+/, '');
    if (!d || /^569\d{8}$/.test(d)) return null;
    const candidates = COUNTRIES.filter(c => d.startsWith(c[3])).sort((a,b)=>b[3].length-a[3].length);
    const c = candidates[0];
    return c ? {country:c, national:d.slice(c[3].length)} : {country:null, national:d};
  }
  function enhance(input) {
    if (!input || input.dataset.sigvePhoneReady === '1') return;
    if (!(input.matches('[data-phone], .phone-field input[name=\"telefono\"], .public-phone input[name=\"telefono\"], #public-socio-form input[name=\"telefono\"], #public-reservation-form input[name=\"telefono\"], #dataForm #telefono, #associatedForm input[name=\"telefono\"]'))) return;
    input.dataset.sigvePhoneReady='1';
    const original = input.value || '';
    const parent = input.parentElement;
    const existingPrefix = parent?.querySelector('span');
    const wrap = document.createElement('div'); wrap.className='sigve-phone-wrap';
    const row = document.createElement('div'); row.className='sigve-phone-row';
    if (existingPrefix) { existingPrefix.classList.add('sigve-phone-prefix'); existingPrefix.textContent='+56 9'; row.appendChild(existingPrefix); }
    else { const p=document.createElement('span');p.className='sigve-phone-prefix';p.textContent='+56 9';row.appendChild(p); }
    input.parentNode.insertBefore(wrap,input); row.appendChild(input); wrap.appendChild(row);
    const toggle=document.createElement('label');toggle.className='sigve-phone-foreign';toggle.innerHTML='<input type="checkbox" data-sigve-foreign> <span>Mi número de WhatsApp es extranjero</span>';wrap.appendChild(toggle);
    const intl=document.createElement('div');intl.className='sigve-phone-intl';intl.hidden=true;
    const countryBox=document.createElement('div');countryBox.className='sigve-phone-countrybox';
    const flag=document.createElement('img');flag.className='sigve-phone-flag';flag.alt='';flag.loading='lazy';
    const select=document.createElement('select');select.className='sigve-phone-country';select.innerHTML=COUNTRIES.filter(c=>c[0]!=='CL').map(c=>`<option value="${c[3]}" data-iso="${c[0]}">${c[2]} (+${c[3]})</option>`).join('')+'<option value="other" data-iso="">Otro país / código</option>';
    countryBox.append(flag,select);intl.appendChild(countryBox);wrap.appendChild(intl);
    const code=document.createElement('input');code.type='text';code.inputMode='numeric';code.placeholder='Código, ej. +51';code.className='sigve-phone-code';code.hidden=true;intl.appendChild(code);
    const help=document.createElement('small');help.className='sigve-phone-help';help.textContent='Ingresa los 8 dígitos después de +56 9.';wrap.appendChild(help);
    const cb=toggle.querySelector('input');
    const updateFlag=()=>{const opt=select.options[select.selectedIndex];const iso=opt?.dataset?.iso||'';flag.hidden=!iso;if(iso)flag.src=`https://flagcdn.com/40x30/${iso.toLowerCase()}.png`;};
    const sync=()=>{const foreign=cb.checked;row.querySelector('.sigve-phone-prefix').hidden=foreign;intl.hidden=!foreign;code.hidden=!foreign||select.value!=='other';input.maxLength=foreign?15:8;input.placeholder=foreign?'Número de WhatsApp':'12345678';help.textContent=foreign?'Ingresa el número sin el código de país.':'Ingresa los 8 dígitos después de +56 9.';updateFlag();input.value=digits(input.value).slice(0,foreign?15:8)};
    cb.addEventListener('change',sync);select.addEventListener('change',sync);input.addEventListener('input',()=>{input.value=digits(input.value).slice(0,cb.checked?15:8)});code.addEventListener('input',()=>{code.value='+'+digits(code.value).slice(0,4)});
    const foreign=inferForeign(original);
    if(foreign){cb.checked=true;if(foreign.country){select.value=foreign.country[3]}else{select.value='other';code.value='+';}input.value=foreign.national}else{let d=digits(original);if(d.startsWith('569')&&d.length>=11)d=d.slice(3);else if(d.startsWith('56'))d=d.slice(2).replace(/^9/,'');else if(d.length===9&&d.startsWith('9'))d=d.slice(1);input.value=d.slice(0,8)}
    sync(); input._sigvePhone={wrap,row,cb,select,code,help};
  }
  function setValue(input, value){
    if(!input)return; enhance(input); const ui=input._sigvePhone; if(!ui)return;
    const raw=String(value||''); const f=inferForeign(raw);
    if(f){ui.cb.checked=true;if(f.country){ui.select.value=f.country[3]}else{ui.select.value='other';ui.code.value='+';}input.value=f.national}
    else{ui.cb.checked=false;let d=digits(raw);if(d.startsWith('569')&&d.length>=11)d=d.slice(3);else if(d.startsWith('56'))d=d.slice(2).replace(/^9/,'');else if(d.length===9&&d.startsWith('9'))d=d.slice(1);input.value=d.slice(0,8)}
    ui.cb.dispatchEvent(new Event('change'));
  }
  function getDbValue(input){
    if(!input)return null; enhance(input); const ui=input._sigvePhone; const n=digits(input.value);
    if(!ui || !ui.cb.checked) return n.length===8?`+569${n}`:null;
    if(!n)return null; let cc=ui.select.value==='other'?digits(ui.code.value):ui.select.value; if(!cc)return null; const full=cc+n; return full.length>=7&&full.length<=15?`+${full}`:null;
  }
  function format(value){const raw=String(value||'').trim();const d=digits(raw);if(/^569\d{8}$/.test(d))return `+56 9 ${d.slice(3,7)} ${d.slice(7)}`;return d?`+${d}`:''}
  function observe(){document.querySelectorAll('input[data-phone],.phone-field input[name="telefono"],.public-phone input[name="telefono"],#dataForm #telefono,#associatedForm input[name="telefono"]').forEach(enhance);new MutationObserver(()=>document.querySelectorAll('input[data-phone],.phone-field input[name="telefono"],.public-phone input[name="telefono"],#dataForm #telefono,#associatedForm input[name="telefono"]').forEach(enhance)).observe(document.body,{childList:true,subtree:true})}
  window.SIGVE_PHONE={enhance,setValue,getDbValue,format,normalizeE164:v=>{const d=digits(v).replace(/^0+/,'');if(d.length===8)return '+569'+d;if(d.length===9&&d.startsWith('9'))return '+56'+d;if(d.length>=7&&d.length<=15)return '+'+d;return ''}};
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',observe);else observe();
})();
