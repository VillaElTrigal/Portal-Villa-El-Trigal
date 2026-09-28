(() => {
  'use strict';
  const COUNTRIES = [
    ['AR','🇦🇷','Argentina','54'],['BO','🇧🇴','Bolivia','591'],['BR','🇧🇷','Brasil','55'],['CL','🇨🇱','Chile','56'],['CO','🇨🇴','Colombia','57'],['CR','🇨🇷','Costa Rica','506'],['CU','🇨🇺','Cuba','53'],['DO','🇩🇴','Rep. Dominicana','1'],['EC','🇪🇨','Ecuador','593'],['SV','🇸🇻','El Salvador','503'],['GT','🇬🇹','Guatemala','502'],['HT','🇭🇹','Haití','509'],['HN','🇭🇳','Honduras','504'],['MX','🇲🇽','México','52'],['NI','🇳🇮','Nicaragua','505'],['PA','🇵🇦','Panamá','507'],['PY','🇵🇾','Paraguay','595'],['PE','🇵🇪','Perú','51'],['PR','🇵🇷','Puerto Rico','1'],['UY','🇺🇾','Uruguay','598'],['VE','🇻🇪','Venezuela','58'],
    ['US','🇺🇸','Estados Unidos','1'],['CA','🇨🇦','Canadá','1'],['ES','🇪🇸','España','34'],['PT','🇵🇹','Portugal','351'],['FR','🇫🇷','Francia','33'],['IT','🇮🇹','Italia','39'],['DE','🇩🇪','Alemania','49'],['GB','🇬🇧','Reino Unido','44'],['IE','🇮🇪','Irlanda','353'],['NL','🇳🇱','Países Bajos','31'],['BE','🇧🇪','Bélgica','32'],['CH','🇨🇭','Suiza','41'],['SE','🇸🇪','Suecia','46'],['NO','🇳🇴','Noruega','47'],['DK','🇩🇰','Dinamarca','45'],
    ['CN','🇨🇳','China','86'],['JP','🇯🇵','Japón','81'],['KR','🇰🇷','Corea del Sur','82'],['IN','🇮🇳','India','91'],['PH','🇵🇭','Filipinas','63'],['AU','🇦🇺','Australia','61'],['NZ','🇳🇿','Nueva Zelanda','64'],['ZA','🇿🇦','Sudáfrica','27']
  ];
  const digits = v => String(v || '').replace(/\D/g, '');
  const css = document.createElement('style');
  css.textContent = `.sigve-phone-wrap{display:flex;flex-direction:column;gap:.45rem}.sigve-phone-row{display:flex;align-items:center;gap:.45rem}.sigve-phone-row input{min-width:0;flex:1}.sigve-phone-prefix{white-space:nowrap;font-weight:600}.sigve-phone-foreign{display:flex;align-items:center;gap:.4rem;font-size:.85rem;font-weight:500}.sigve-phone-country{width:100%;max-width:100%;padding:.55rem .65rem;border:1px solid #cbd5e1;border-radius:8px;background:#fff}.sigve-phone-help{font-size:.78rem;color:#64748b}.sigve-phone-code{width:90px!important;flex:0 0 90px!important}@media(max-width:600px){.sigve-phone-row{flex-wrap:wrap}.sigve-phone-country{font-size:.9rem}}`;
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
    const toggle=document.createElement('label');toggle.className='sigve-phone-foreign';toggle.innerHTML='<input type="checkbox" data-sigve-foreign> Mi número de WhatsApp es extranjero';wrap.appendChild(toggle);
    const select=document.createElement('select');select.className='sigve-phone-country';select.hidden=true;select.innerHTML=COUNTRIES.filter(c=>c[0]!=='CL').map(c=>`<option value="${c[3]}">${c[1]} ${c[2]} (+${c[3]})</option>`).join('')+'<option value="other">🌎 Otro país / código</option>';wrap.appendChild(select);
    const code=document.createElement('input');code.type='text';code.inputMode='numeric';code.placeholder='+ código';code.className='sigve-phone-code';code.hidden=true;row.insertBefore(code,input);
    const help=document.createElement('small');help.className='sigve-phone-help';help.textContent='Ingresa los 8 dígitos después de +56 9.';wrap.appendChild(help);
    const cb=toggle.querySelector('input');
    const sync=()=>{const foreign=cb.checked;row.querySelector('.sigve-phone-prefix').hidden=foreign;select.hidden=!foreign;code.hidden=!foreign||select.value!=='other';input.maxLength=foreign?15:8;input.placeholder=foreign?'Número sin código de país':'12345678';help.textContent=foreign?'Selecciona el país del número e ingresa el número de WhatsApp sin el código internacional.':'Ingresa los 8 dígitos después de +56 9.';input.value=digits(input.value).slice(0,foreign?15:8)};
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
