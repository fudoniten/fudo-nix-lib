{ config, lib, pkgs, ... }:

# Nebula overlay networks.
#
# A network is declared here; membership is declared per host, with
# `nebula-network`; and a host's overlay address is assigned in the network's
# DNS zone, alongside every other address in the fleet.  Three places, but each
# holds the kind of thing it already holds -- rather than a fourth place that
# holds Nebula addresses and nothing else.
#
# A host listed in `nebula-network` but with no address in the zone does not
# join. That is the opt-in: assigning an address is what puts a host on the
# mesh, and removing it is what takes it off.

with pkgs.lib;
let
  networkOpts = { name, ... }: {
    options = with types; {
      network = mkOption {
        type = str;
        description = "Name of this Nebula network.";
        default = name;
      };

      cidr = mkOption {
        type = str;
        description = ''
          The overlay address range.

          Every certificate is issued with this prefix, because it is what
          tells a host which addresses route over the tun device. Choose a
          range that collides with nothing the fleet already uses -- including
          the CIDRs of anything it runs, such as a Kubernetes cluster's pod and
          service ranges.
        '';
        example = "10.100.0.0/16";
      };

      port = mkOption {
        type = port;
        description = ''
          UDP port lighthouses listen on, and that other hosts dial them at.

          Only lighthouses use a fixed port; everyone else takes a random one,
          which is friendlier to NAT.
        '';
        default = 4242;
      };

      zone = mkOption {
        type = str;
        description = ''
          DNS zone holding this network's overlay addresses.

          Doubles as the address assignment table: a host joins the network by
          being given an address here, and its overlay name is
          <hostname>.<zone>.

          The zone's nameservers must be reachable WITHOUT the mesh. Serving it
          from a host that is only reachable over the overlay makes resolving a
          name require the tunnel that resolving it was meant to establish.
        '';
        example = "fudo.dev";
      };

      subdomain = mkOption {
        type = nullOr str;
        description = ''
          Subdomain of `zone` holding the addresses, if they do not live at its
          apex. Overlay names are then <hostname>.<subdomain>.<zone>.
        '';
        default = null;
      };

      cert-duration = mkOption {
        type = str;
        description = ''
          Lifetime of host certificates. Unlike most fleet key material these
          expire, and a host whose certificate lapses while it is remote drops
          off the mesh -- taking with it the route you would have used to fix
          it.
        '';
        default = "8760h";
      };

      ca-duration = mkOption {
        type = str;
        description = ''
          Lifetime of the network's CA. Wants to outlive the host certificates
          by a wide margin, so that rotating it stays a choice rather than an
          emergency.
        '';
        default = "43800h";
      };
    };
  };

in {
  options.fudo.nebula = with types; {
    networks = mkOption {
      type = attrsOf (submodule networkOpts);
      description = "Nebula overlay network configurations.";
      default = { };
    };
  };
}
