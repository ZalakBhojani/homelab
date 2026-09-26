#!/bin/sh
# Sudo password for the fleet, pulled from the macOS Keychain at runtime —
# never stored on disk. Ansible runs this via become_password_file (see
# ansible.cfg) and uses stdout as the become password.
#
# One-time setup (prompts for the password, hidden):
#   security add-generic-password -s homelab-become -a zalak -w
#
# -K on the command line still overrides this when you want to be prompted.
exec security find-generic-password -s homelab-become -a zalak -w
