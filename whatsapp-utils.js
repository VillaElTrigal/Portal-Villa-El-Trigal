(() => {
  'use strict';

  function normalizeNumber(value) {
    let number = String(value || '').replace(/\D/g, '');
    number = number.replace(/^0+/, '');
    if (number.length === 8) number = `569${number}`;
    else if (number.length === 9 && number.startsWith('9')) number = `56${number}`;
    return /^569\d{8}$/.test(number) ? number : '';
  }

  function isMobileDevice() {
    const ua = String(navigator.userAgent || '');
    return /Android|iPhone|iPad|iPod|IEMobile|Opera Mini|Mobile/i.test(ua)
      || (navigator.maxTouchPoints > 1 && /Macintosh/i.test(ua));
  }

  function buildUrl(phone, message = '') {
    const number = normalizeNumber(phone);
    if (!number) return '';
    const text = encodeURIComponent(String(message ?? ''));
    return isMobileDevice()
      ? `https://wa.me/${number}${text ? `?text=${text}` : ''}`
      : `https://web.whatsapp.com/send?phone=${number}${text ? `&text=${text}` : ''}`;
  }

  function open(phone, message = '', target = '_blank') {
    const href = buildUrl(phone, message);
    if (!href) return null;
    return window.open(href, target, 'noopener,noreferrer');
  }

  function setLink(element, phone, message = '') {
    if (!element) return '';
    const href = buildUrl(phone, message);
    if (href) {
      element.href = href;
      element.target = '_blank';
      element.rel = 'noopener noreferrer';
    } else {
      element.removeAttribute('href');
    }
    return href;
  }

  window.SIGVEWhatsApp = Object.freeze({
    normalizeNumber,
    isMobileDevice,
    buildUrl,
    open,
    setLink
  });
})();
