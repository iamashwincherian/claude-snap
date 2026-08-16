const USAGE_PERCENT = 34;

function arcPath(pct) {
  const f = Math.min(pct, 99.9) / 100;
  if (f <= 0.005) return "";
  const end = ((-90 + 360 * f) * Math.PI) / 180;
  const largeArc = f > 0.5 ? 1 : 0;
  const x = (9 + 7 * Math.cos(end)).toFixed(2);
  const y = (9 + 7 * Math.sin(end)).toFixed(2);
  return `M9 2A7 7 0 ${largeArc} 1 ${x} ${y}`;
}

document.getElementById("usage-arc").setAttribute("d", arcPath(USAGE_PERCENT));

const copyBtn = document.getElementById("copy-btn");
const installCommandEl = document.getElementById("install-command");
const installCommand = `curl -s ${location.origin}/install.sh | bash`;
installCommandEl.textContent = installCommand;
let copyTimer;
copyBtn.addEventListener("click", () => {
  navigator.clipboard?.writeText(installCommand).catch(() => {});
  copyBtn.textContent = "Copied";
  clearTimeout(copyTimer);
  copyTimer = setTimeout(() => { copyBtn.textContent = "Copy"; }, 1600);
});
