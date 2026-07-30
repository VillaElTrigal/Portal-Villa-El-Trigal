(() => {
  'use strict';

  const init = () => {
    const adminView = document.getElementById('admin-view');
    const sidebar = adminView?.querySelector('.sidebar');
    if (!adminView || !sidebar || document.getElementById('sigve-mobile-menu')) return;

    const button = document.createElement('button');
    button.id = 'sigve-mobile-menu';
    button.className = 'mobile-menu-button';
    button.type = 'button';
    button.setAttribute('aria-label', 'Abrir menú');
    button.setAttribute('aria-controls', 'sigve-sidebar');
    button.setAttribute('aria-expanded', 'false');
    button.textContent = '☰';

    sidebar.id = sidebar.id || 'sigve-sidebar';

    const backdrop = document.createElement('button');
    backdrop.type = 'button';
    backdrop.className = 'mobile-menu-backdrop';
    backdrop.setAttribute('aria-label', 'Cerrar menú');

    adminView.prepend(backdrop);
    adminView.prepend(button);

    const isMobile = () => window.matchMedia('(max-width: 780px)').matches;
    const setOpen = (open) => {
      document.body.classList.toggle('sigve-menu-open', open && isMobile());
      button.setAttribute('aria-expanded', String(open && isMobile()));
      button.setAttribute('aria-label', open ? 'Cerrar menú' : 'Abrir menú');
      button.textContent = open ? '✕' : '☰';
    };

    button.addEventListener('click', () => {
      setOpen(!document.body.classList.contains('sigve-menu-open'));
    });
    backdrop.addEventListener('click', () => setOpen(false));

    sidebar.addEventListener('click', (event) => {
      if (event.target.closest('nav button, nav a, #logout-button')) setOpen(false);
    });

    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') setOpen(false);
    });

    window.addEventListener('resize', () => {
      if (!isMobile()) setOpen(false);
    });
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }
})();
