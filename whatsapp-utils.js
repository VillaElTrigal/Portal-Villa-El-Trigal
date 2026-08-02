(() => {
  'use strict';

  function normalizeNumber(value) {
    let number = String(value || '').replace(/\D/g, '');
    number = number.replace(/^0+/, '');
    if (number.length === 8) number = `569${number}`;
    else if (number.length === 9 && number.startsWith('9')) number = `56${number}`;
    return /^569\d{8}$/.test(number) ? number : '';
  }

  function buildUrl(phone, message = '') {
    const number = normalizeNumber(phone);
    if (!number) return '';
    // encodeURIComponent codifica el texto UTF-8 una sola vez y conserva
    // correctamente emojis, tildes, eñes y saltos de línea en WhatsApp.
    return `https://wa.me/${number}?text=${encodeURIComponent(String(message ?? ''))}`;
  }

  function open(phone, message = '', target = '_blank') {
    const url = buildUrl(phone, message);
    if (!url) return null;
    return window.open(url, target, 'noopener,noreferrer');
  }

  function setLink(element, phone, message = '') {
    if (!element) return '';
    const url = buildUrl(phone, message);
    if (url) element.href = url;
    else element.removeAttribute('href');
    return url;
  }

  window.SIGVEWhatsApp = Object.freeze({ normalizeNumber, buildUrl, open, setLink });
})();
