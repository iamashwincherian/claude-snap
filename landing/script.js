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
