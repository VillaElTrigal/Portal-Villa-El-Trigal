
(function(){
  'use strict';
  document.addEventListener('DOMContentLoaded',()=>{
    const modo=document.getElementById('apariencia-modo');
    const tema=document.getElementById('apariencia-tema');
    const estado=document.getElementById('apariencia-estado');
    const guardar=document.getElementById('apariencia-guardar');
    const preview=document.getElementById('apariencia-preview');
    if(!modo||!tema||!estado||!guardar)return;

    const cfg=window.PORTAL_CONFIG||{};
    if(!window.supabase||!cfg.supabaseUrl||!cfg.supabaseAnonKey){
      estado.textContent='No se pudo iniciar Supabase.'; return;
    }
    const sb=window.supabase.createClient(cfg.supabaseUrl,cfg.supabaseAnonKey);
    const labels={
      normal:'Normal',
      fiestas_patrias:'🇨🇱 Fiestas Patrias',
      halloween:'🎃 Halloween',
      navidad:'🎄 Navidad'
    };

    const sync=()=>{
      tema.disabled=modo.value!=='manual';
      if(preview) preview.textContent=modo.value==='manual'
        ?'Vista seleccionada: '+labels[tema.value]
        :'El sistema elegirá el tema según la fecha.';
    };
    modo.addEventListener('change',sync);
    tema.addEventListener('change',sync);

    async function load(){
      const {data,error}=await sb.rpc('admin_obtener_apariencia');
      if(error){estado.textContent='Error: '+error.message;return;}
      const row=Array.isArray(data)?data[0]:data;
      if(row){
        modo.value=row.modo||'auto';
        tema.value=row.tema_manual||'normal';
        sync();
        estado.textContent=row.modo==='manual'
          ?'Tema activo: '+labels[row.tema_manual]
          :'Modo automático activado.';
      }
    }

    guardar.addEventListener('click',async()=>{
      guardar.disabled=true;estado.textContent='Guardando…';
      try{
        const {error}=await sb.rpc('admin_guardar_apariencia',{
          p_modo:modo.value,p_tema_manual:tema.value
        });
        if(error)throw error;
        estado.textContent=modo.value==='manual'
          ?'✅ Tema activado: '+labels[tema.value]+'. Recarga los portales para verlo.'
          :'✅ Modo automático activado. Recarga los portales para verlo.';
      }catch(e){estado.textContent='Error: '+e.message}
      finally{guardar.disabled=false}
    });
    load();
  });
})();
