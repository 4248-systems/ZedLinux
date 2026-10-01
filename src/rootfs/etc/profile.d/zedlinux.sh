#!/bin/sh

if [ -n "$BASH_VERSION" ]; then
    [ -r /etc/ZedLinux/bashrc.common ] && . /etc/ZedLinux/bashrc.common
    [ -r /etc/ZedLinux/bashrc ] && . /etc/ZedLinux/bashrc
fi
