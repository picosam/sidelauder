# Simulates a Mac whose system-wide login files add no Homebrew path:
# skip /etc/zprofile and /etc/zshrc, start from the Dock's PATH.
unsetopt GLOBAL_RCS
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
