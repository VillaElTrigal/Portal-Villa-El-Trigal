(() => {
  'use strict';

  // Emojis definidos con escapes Unicode para evitar problemas de codificacion
  // al abrir mensajes desde navegadores de escritorio o WhatsApp Web.
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

  function url(phone, message) {
    const number = normalizePhone(phone);
    if (!number) return '';
    return `https://wa.me/${number}?text=${encodeURIComponent(String(message || ''))}`;
  }

  function open(phone, message, target = '_blank') {
    const href = url(phone, message);
    if (!href) return null;
    return window.open(href, target, 'noopener,noreferrer');
  }

  window.SIGVE_EMOJI = EMOJI;
  window.SIGVE_WHATSAPP = Object.freeze({ normalizePhone, url, open });
})();
