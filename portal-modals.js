(() => {
  'use strict';

  const MODALS = {
    certificado: {
      elementId: 'certificate-modal-root',
      title: 'Certificado de residencia',
      focusSelector: '#cert-name'
    },
    reserva: {
      elementId: 'arriendo',
      title: 'Reserva de sede',
      focusSelector: '#rental-calendars button:not([disabled])'
    },
    socio: {
      elementId: 'socios-solicitud',
      title: 'Hazte socio',
      focusSelector: 'input[name="nombres"]'
    }
  };

  let activeModal = null;
  let lastTrigger = null;

  const getModal = name => {
    const config = MODALS[name];
    return config ? document.getElementById(config.elementId) : null;
  };

  function addTopbar(name) {
    if (name === 'certificado') return;
    const modal = getModal(name);
    const container = modal?.querySelector(':scope > .container');
    if (!container || container.querySelector(':scope > .portal-modal-topbar')) return;

    const bar = document.createElement('div');
    bar.className = 'portal-modal-topbar';
    bar.innerHTML = `<strong>${MODALS[name].title}</strong><button type="button" class="portal-modal-close" data-close-portal-modal aria-label="Cerrar ${MODALS[name].title}">×</button>`;
    container.prepend(bar);
  }

  function openModal(name, trigger = null) {
    const modal = getModal(name);
    if (!modal) return;

    if (activeModal && activeModal !== name) closeModal(false);
    lastTrigger = trigger || document.activeElement;
    activeModal = name;

    if (name === 'certificado') modal.hidden = false;
    modal.classList.add('portal-modal-active');
    modal.setAttribute('role', 'dialog');
    modal.setAttribute('aria-modal', 'true');
    modal.setAttribute('aria-label', MODALS[name].title);
    document.body.classList.add('portal-modal-lock');

    requestAnimationFrame(() => {
      modal.scrollTop = 0;
      const isSmallScreen = window.matchMedia('(max-width: 720px)').matches;
      const target = isSmallScreen
        ? (modal.querySelector('.close-panel, [data-close-portal-modal]') || modal.querySelector('button, a[href]'))
        : (modal.querySelector(MODALS[name].focusSelector) || modal.querySelector('button, input, select, textarea, a[href]'));
      target?.focus({ preventScroll: true });
      setTimeout(() => { modal.scrollTop = 0; }, 80);
    });
  }

  function closeModal(restoreFocus = true) {
    if (!activeModal) return;
    const modal = getModal(activeModal);
    const closingName = activeModal;
    modal?.classList.remove('portal-modal-active');
    modal?.removeAttribute('role');
    modal?.removeAttribute('aria-modal');
    modal?.removeAttribute('aria-label');
    if (closingName === 'certificado' && modal) modal.hidden = true;
    document.body.classList.remove('portal-modal-lock');
    activeModal = null;

    if (restoreFocus && lastTrigger instanceof HTMLElement) {
      lastTrigger.focus({ preventScroll: true });
    }
  }

  function modalFromHref(href) {
    if (!href) return null;
    const hash = href.includes('#') ? `#${href.split('#').pop()}` : href;
    if (hash === '#arriendo') return 'reserva';
    if (hash === '#socios-solicitud') return 'socio';
    return null;
  }

  function installTriggers() {
    document.querySelectorAll('a[href="#arriendo"], a[href="#socios-solicitud"]').forEach(link => {
      const name = modalFromHref(link.getAttribute('href'));
      if (name) link.dataset.openPortalModal = name;
    });

    const certificateShortcut = document.querySelector('.shortcuts a[href="#tramites"]');
    if (certificateShortcut) certificateShortcut.dataset.openPortalModal = 'certificado';

    document.querySelectorAll('button[onclick="toggleCertificateForm()"], #certificate-form-panel .close-panel').forEach(button => {
      button.removeAttribute('onclick');
      if (button.classList.contains('close-panel')) button.dataset.closePortalModal = '';
      else button.dataset.openPortalModal = 'certificado';
    });
  }

  function trapTab(event) {
    if (event.key !== 'Tab' || !activeModal) return;
    const modal = getModal(activeModal);
    if (!modal) return;
    const focusables = [...modal.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')]
      .filter(el => el.offsetParent !== null);
    if (!focusables.length) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  document.addEventListener('DOMContentLoaded', () => {
    document.body.classList.add('portal-modal-ready');
    addTopbar('reserva');
    addTopbar('socio');
    installTriggers();

    window.toggleCertificateForm = () => {
      if (activeModal === 'certificado') closeModal();
      else openModal('certificado');
    };

    document.addEventListener('click', event => {
      const openButton = event.target.closest('[data-open-portal-modal]');
      if (openButton) {
        event.preventDefault();
        document.body.classList.remove('menu-open');
        openModal(openButton.dataset.openPortalModal, openButton);
        return;
      }

      if (event.target.closest('[data-close-portal-modal]')) {
        event.preventDefault();
        closeModal();
        return;
      }

      if (activeModal) {
        const modal = getModal(activeModal);
        if (event.target === modal) closeModal();
      }
    });

    document.addEventListener('keydown', event => {
      if (event.key === 'Escape' && activeModal) closeModal();
      trapTab(event);
    });

    const initialName = modalFromHref(window.location.hash);
    if (initialName) {
      history.replaceState(null, '', `${window.location.pathname}${window.location.search}`);
      setTimeout(() => openModal(initialName), 50);
    }
  });
})();
