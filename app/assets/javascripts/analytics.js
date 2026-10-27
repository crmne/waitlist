// Counts a public page's events with the product's Plausible: no cookies, and
// nothing about the person. Every request is reported under the page name the
// layout gives (PAGE_URL/confirmed), never this page's own address, which may
// carry a token, and without a referrer. Loaded before Plausible's script,
// which then picks up these settings and events.
(() => {
  const meta = document.querySelector('meta[name="analytics"]');
  if (!meta) return;
  const { url, events } = JSON.parse(meta.content);
  window.plausible = window.plausible || function () { (window.plausible.q = window.plausible.q || []).push(arguments); };
  window.plausible.init = window.plausible.init || function (options) { window.plausible.o = options || {}; };
  window.plausible.init({ autoCapturePageviews: false, transformRequest: request => ({ ...request, u: url, r: null }) });
  window.plausible("pageview");
  events.forEach(([name, props]) => window.plausible(name, props ? { props } : {}));
  document.addEventListener("click", event => {
    if (event.target.closest("[data-copy='#referral-link']")) window.plausible("Referral: Link copied");
  });
})();
