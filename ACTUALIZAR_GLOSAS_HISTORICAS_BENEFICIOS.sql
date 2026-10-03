-- SIGVE · Completar glosas históricas de arriendos con beneficio confirmado
-- No modifica montos, fechas, fondos ni reservas.
begin;

update public.movimientos_financieros mf
set concepto = mf.concepto
  || ' · '
  || case
       when r.beneficio_nombre ~* '^beneficio([[:space:]]|$)' then btrim(r.beneficio_nombre)
       else 'Beneficio ' || btrim(r.beneficio_nombre)
     end
  || case
       when coalesce(r.valor_original,0)>0 and coalesce(r.descuento_aplicado,0)>0
       then ' (' || trim(trailing '.' from trim(trailing '0' from
              to_char(round((r.descuento_aplicado/r.valor_original)*100,2),'FM999990.00')
            )) || '%)'
       else ''
     end
from public.reservas_sede r
where mf.reserva_id=r.id
  and mf.categoria='Arriendo sede'
  and r.beneficio_nombre is not null
  and btrim(r.beneficio_nombre)<>''
  and mf.concepto not ilike '%beneficio%';

commit;
