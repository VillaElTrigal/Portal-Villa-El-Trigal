(() => {
  'use strict';

  // Emojis definidos con escapes Unicode para evitar problemas de codificación
  // al construir mensajes desde cualquier sistema operativo o editor.
  const EMOJI = Object.freeze({
    saludo: '\u{1F44B}',
    celebracion: '\u{1F389}',
    torta: '\u{1F382}',
    globo: '\u{1F388}',
    enlace: '\u{1F517}',
    reloj: '\u{23F3}',
    casa: '\u{1F3E0}',
    documento: '\u{1F4C4}',
    dinero: '\u{1F4B0}',
    telefono: '\u{1F4F1}',
    mensaje: '\u{1F4AC}',
    whatsapp: '\u{1F4F2}',
    regalo: '\u{1F381}',
    check: '\u{2705}',
    advertencia: '\u{26A0}\u{FE0F}',
    error: '\u{274C}'
  });

  function normalizePhone(phone) {
    let number = String(phone || '').replace(/\D/g, '');
    number = number.replace(/^0+/, '');
    if (number.length === 8) number = '569' + number;
    else if (number.length === 9 && number.startsWith('9')) number = '56' + number;
    return /^569\d{8}$/.test(number) ? number : '';
  }

  function isMobileDevice() {
    const ua = String(navigator.userAgent || '');
    const mobileUa = /Android|iPhone|iPad|iPod|IEMobile|Opera Mini|Mobile/i.test(ua);
    const touchOnly = navigator.maxTouchPoints > 1 && /Macintosh/i.test(ua); // iPadOS
    return mobileUa || touchOnly;
  }

  function url(phone, message = '') {
    const number = normalizePhone(phone);
    if (!number) return '';

    const text = encodeURIComponent(String(message ?? ''));
    if (isMobileDevice()) {
      return `https://wa.me/${number}${text ? `?text=${text}` : ''}`;
    }

    // En computador se abre WhatsApp Web directamente. Esto evita que la
    // redirección intermedia de wa.me altere el texto precargado o sus emojis.
    return `https://web.whatsapp.com/send?phone=${number}${text ? `&text=${text}` : ''}`;
  }

  function open(phone, message = '', target = '_blank') {
    const href = url(phone, message);
    if (!href) return null;
    return window.open(href, target, 'noopener,noreferrer');
  }

  function setLink(element, phone, message = '') {
    if (!element) return '';
    const href = url(phone, message);
    if (href) {
      element.href = href;
      element.target = '_blank';
      element.rel = 'noopener noreferrer';
    } else {
      element.removeAttribute('href');
    }
    return href;
  }

  window.SIGVE_EMOJI = EMOJI;
  window.SIGVE_WHATSAPP = Object.freeze({
    normalizePhone,
    isMobileDevice,
    url,
    open,
    setLink
  });
})();
