(function () {
  const STORAGE_KEY = 'villa-el-trigal-content-v1';
  const grid = document.getElementById('announcements-grid');
  if (!grid) return;

  const escapeHtml = (value = '') => String(value).replace(/[&<>'"]/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
  }[char]));

  const formatDate = value => {
    if (!value) return '';
    const date = new Date(value + 'T12:00:00');
    return new Intl.DateTimeFormat('es-CL', { day: '2-digit', month: 'long', year: 'numeric' }).format(date);
  };

  function render(items) {
    const today = new Date().toISOString().slice(0, 10);
    const active = items
      .filter(item => item.published !== false && (!item.expires_at || item.expires_at >= today))
      .sort((a, b) => (b.pinned === true) - (a.pinned === true) || String(b.created_at || '').localeCompare(String(a.created_at || '')));

    if (!active.length) return;
    grid.innerHTML = active.map(item => `
      <article class="announcement-card" data-category="${escapeHtml(item.category || 'Información')}">
        <span class="announcement-type">${item.pinned ? '📌 ' : ''}${escapeHtml(item.category || 'Información')}</span>
        <h3>${escapeHtml(item.title)}</h3>
        <p>${escapeHtml(item.description).replace(/\n/g, '<br>')}</p>
        <div class="announcement-meta">
          ${item.event_date ? `<span>📅 ${formatDate(item.event_date)}${item.event_time ? ` · ${escapeHtml(item.event_time)}` : ''}</span>` : ''}
          ${item.location ? `<span>📍 ${escapeHtml(item.location)}</span>` : ''}
        </div>
      </article>`).join('');
  }

  async function load() {
    const config = window.PORTAL_CONFIG || {};
    if (config.supabaseUrl && config.supabaseAnonKey && window.supabase) {
      try {
        const client = window.supabase.createClient(config.supabaseUrl, config.supabaseAnonKey);
        const { data, error } = await client.from('announcements').select('*').eq('published', true).order('created_at', { ascending: false });
        if (error) throw error;
        render(data || []);
        return;
      } catch (error) {
        console.warn('No se pudo cargar Supabase; se usarán datos locales.', error);
      }
    }
    try { render(JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]')); } catch (_) {}
  }

  load();
})();
