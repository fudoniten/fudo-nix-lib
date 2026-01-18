# Messaging Infrastructure Module Group
#
# This module group provides XMPP-based messaging infrastructure:
# - Backplane (inter-service messaging/coordination via XMPP)
# - Jabber server (XMPP server implementation)
#
# Dependencies: core (for hosts, secrets, domains)

{ ... }: {
  imports = [
    ../lib/fudo/backplane.nix
    ../lib/fudo/jabber.nix
  ];
}
