#!/bin/bash
#
# ZedLinux managed shell configuration for every interactive, non-login
# bash instance (new terminals, su, subshells, etc). Login shells load the
# same settings via /etc/profile.d/zedlinux.sh instead.

# Bail out early for non-interactive shells.
case $- in
    *i*) ;;
      *) return ;;
esac

[ -r /etc/ZedLinux/bashrc.common ] && . /etc/ZedLinux/bashrc.common
