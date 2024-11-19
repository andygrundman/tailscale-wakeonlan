package TestInit;

use strict;
use warnings;
use Mojo::File qw(path);
use Mojo::JSON qw(encode_json);

BEGIN {
  # wipe and create a fresh json db file
  my $path = path("/var/lib/tailscale/mojo");
  my $json = $path->child("wakeonlan.json");

  if (!-d $path) {
    my $err;
    $path->make_path;
  }

  $json->spew(
    encode_json({ broadcast => "255.255.255.255", hosts => [] })
  );
  die "Couldn't create $json" unless -f $json;
}

1;
