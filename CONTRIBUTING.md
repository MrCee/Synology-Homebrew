# 🤝 Contributing to Synology-Homebrew

Thanks for being interested in contributing! We welcome pull requests, issues, and improvements of any kind 🙌

---

## 🛠️ How to Contribute

1. **Fork the repository**
2. Create a new feature branch:
   ```bash
   git checkout -b my-feature
   ```
3. Make your changes
4. Test your changes on a Synology NAS (DSM 7.2+) or macOS
5. Commit and push:
   ```bash
   git commit -m "Add: <your feature/fix>"
   git push origin my-feature
   ```
6. Open a **Pull Request** against `main`

---

## 🧪 Testing Guidelines

- Run the installer on Synology DSM 7.2+ and/or macOS
- Validate changes using:
  ```bash
  ./install-synology-homebrew.sh
  ```
- Ensure Minimal and Advanced modes work cleanly
- If modifying `config.yaml`, validate structure + aliases

---

## 🧰 Code Style

- Stick to Bash best practices (`set -euo pipefail`)
- Prioritize readability over cleverness
- Keep `eval` blocks minimal and explicit
- Use consistent spacing and naming

---

## 🐛 Issues

When opening an issue, please include:

- ✅ DSM version or macOS version
- ✅ Steps to reproduce
- ✅ Logs or terminal output
- ✅ What you expected vs. what happened

---

## 📦 Contributing Packages

Want to add packages to `config.yaml`?

- Add them under the correct section (e.g., `packages:` or `plugins:`)
- Provide useful aliases (e.g. `cat → bat`)
- Add `eval` if runtime initialization is needed
- Mention dependencies in your PR

---

## 🙏 Thank You

Whether it’s a code fix, typo, or test — every contribution helps.
Your effort is what keeps open source great 💙

