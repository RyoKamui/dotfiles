# Dotfiles

### Usage

```bash
bash <(curl -s https://raw.githubusercontent.com/RyoKamui/dotfiles/main/deploy.sh)
```
### Warning: Permissions Required

Before proceeding, please ensure that you have enabled **Full Disk Access** and **Accessibility** permissions for the following applications:

- Terminal
- WezTerm

These permissions are required for certain operations to function properly.

### Note: Mac App Store apps

`packages_mac` includes App Store apps (`mas` entries: Xcode, uBlock Origin Lite, APTV). These install only when you are signed into the Mac App Store — `brew bundle` silently skips them otherwise. Sign in, then re-run `chezmoi apply`.
