---
name: Something went wrong
about: A component misbehaved, looked wrong, or wouldn't install / remove
labels: bug
---

**Which component** (launcher, theme selector, background selector, overview)


**What happened, and what you expected**


**Your setup** - paste the output of:

```sh
./install.sh doctor
./install.sh list
hyprctl version | head -1
```

A shell log helps with anything visual: `omarchy restart shell`, reproduce,
then `qs log -i "$(ls -t /run/user/$UID/quickshell/by-id/ | head -1)" | tail -50`.
