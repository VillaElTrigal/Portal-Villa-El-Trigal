/* SIGVE 4.1 Mobile Preview: navegación móvil no invasiva. */
(() => {
  const mq = window.matchMedia('(max-width: 820px)');
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];

  const items = [
    { section: 'dashboard', icon: '🏠', label: 'Inicio' },
    { section: 'socios', icon: '👥', label: 'Socios' },
    { section: 'finanzas', icon: '💰', label: 'Finanzas' },
    { section: 'reservas-v7', icon: '📅', label: 'Reservas' },
    { section: 'more', icon: '☰', label: 'Más' }
  ];

  function closeMenu() {
    document.body.classList.remove('mobile-menu-open');
    $('.mobile-menu-button')?.setAttribute('aria-expanded', 'false');
  }

  function openMenu() {
    document.body.classList.add('mobile-menu-open');
    $('.mobile-menu-button')?.setAttribute('aria-expanded', 'true');
  }

  function syncActive(section) {
    $$('.mobile-nav button').forEach(button => {
      button.classList.toggle('active', button.dataset.section === section);
    });
  }

  function go(section) {
    if (section === 'more') {
      openMenu();
      return;
    }
    const target = $(`.sidebar [data-section="${section}"]`);
    if (target) target.click();
    syncActive(section);
    closeMenu();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function build() {
    const topbar = $('.topbar');
    const shell = $('#admin-view');
    if (!topbar || !shell || $('.mobile-nav')) return;

    const menu = document.createElement('button');
    menu.type = 'button';
    menu.className = 'mobile-menu-button';
    menu.setAttribute('aria-label', 'Abrir menú');
    menu.setAttribute('aria-expanded', 'false');
    menu.textContent = '☰';
    menu.addEventListener('click', () => {
      document.body.classList.contains('mobile-menu-open') ? closeMenu() : openMenu();
    });
    topbar.prepend(menu);

    const backdrop = document.createElement('div');
    backdrop.className = 'mobile-sidebar-backdrop';
    backdrop.addEventListener('click', closeMenu);
    document.body.appendChild(backdrop);

    const nav = document.createElement('nav');
    nav.className = 'mobile-nav';
    nav.setAttribute('aria-label', 'Navegación móvil');
    nav.innerHTML = items.map(item => `
      <button type="button" data-section="${item.section}" aria-label="${item.label}">
        <span class="mobile-nav-icon" aria-hidden="true">${item.icon}</span>
        <span>${item.label}</span>
      </button>`).join('');
    nav.addEventListener('click', event => {
      const button = event.target.closest('button[data-section]');
      if (button) go(button.dataset.section);
    });
    document.body.appendChild(nav);

    document.addEventListener('click', event => {
      const sectionButton = event.target.closest('.sidebar [data-section]');
      if (!sectionButton) return;
      syncActive(sectionButton.dataset.section);
      if (mq.matches) closeMenu();
    }, true);

    document.addEventListener('keydown', event => {
      if (event.key === 'Escape') closeMenu();
    });

    mq.addEventListener?.('change', event => {
      if (!event.matches) closeMenu();
    });

    syncActive('dashboard');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', build);
  } else {
    build();
  }
})();
