# Authentication & Identity Module Group
#
# This module group provides authentication and identity management services:
# - LDAP server (directory service)
# - LDAP client authentication
# - Kerberos KDC (optional, in auth/ subdirectory)
# - SSH server configuration
# - Password management
#
# Dependencies: core (for users, secrets, hosts)

{ ... }: {
  imports = [
    ../lib/fudo/auth
    ../lib/fudo/authentication.nix
    ../lib/fudo/ldap.nix
    ../lib/fudo/password.nix
    ../lib/fudo/ssh.nix
  ];
}
