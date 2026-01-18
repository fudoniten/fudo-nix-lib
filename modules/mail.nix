# Mail Services Module Group
#
# This module group provides email server infrastructure:
# - Mail server orchestration (postfix, dovecot, rspamd, clamav, dkim)
# - Containerized mail deployment option
# - Webmail interface
#
# Dependencies:
# - core (for users, secrets, hosts, domains)
# - auth (for LDAP authentication)
# - infrastructure (for postgresql database)
#
# Note: Mail services require postgresql. Import the infrastructure module
# or ensure postgresql is configured separately.

{ ... }: {
  imports = [
    ../lib/fudo/mail.nix
    ../lib/fudo/mail-container.nix
    ../lib/fudo/webmail.nix
  ];
}
