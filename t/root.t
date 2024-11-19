use Test::More;
use Test::Mojo;

require(Mojo::File::curfile->sibling("lib/TestInit.pm"));

my $t = Test::Mojo->new(
  Mojo::File::curfile->dirname->sibling('main.pl')
);

$t->get_ok('/')->status_is(200)->content_like(qr/Tailscale Wake-on-LAN/);

done_testing();
