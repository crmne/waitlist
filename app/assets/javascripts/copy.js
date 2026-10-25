// Copy buttons: <button data-copy="#field-id">. No inline script, so the
// pages' Content-Security-Policy can stay strict.
document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy]");
  if (!button) return;
  const field = document.querySelector(button.dataset.copy);
  if (!field) return;
  try { await navigator.clipboard.writeText(field.value); } catch { field.select(); document.execCommand("copy"); }
  const label = button.textContent;
  button.textContent = "Copied";
  setTimeout(() => { button.textContent = label; }, 1600);
});
