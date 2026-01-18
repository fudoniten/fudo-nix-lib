# Application Services Module Group
#
# This module group provides various application and development services:
# - Chat (Mattermost team collaboration)
# - Git (version control hosting)
# - IPFS (distributed file storage)
# - Nexus (software repository manager)
# - Minecraft servers (both Java and Clojure-based)
# - Network info via email
# - Slynk (Common Lisp REPL server)
#
# Dependencies: core (for hosts, secrets, domains)
# Optional dependencies may include:
# - infrastructure (for postgresql if chat/nexus need it)
# - auth (for LDAP integration)

{ ... }: {
  imports = [
    ../lib/fudo/chat.nix
    ../lib/fudo/git.nix
    ../lib/fudo/ipfs.nix
    ../lib/fudo/minecraft-clj.nix
    ../lib/fudo/minecraft-server.nix
    ../lib/fudo/netinfo-email.nix
    ../lib/fudo/nexus.nix
    ../lib/fudo/slynk.nix
  ];
}
