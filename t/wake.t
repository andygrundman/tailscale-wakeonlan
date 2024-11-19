use Mojo::Base -strict;
use Mojo::JSON qw(encode_json);
use Test::More;
use Test::Mojo;

require(Mojo::File::curfile->sibling("lib/TestInit.pm"));

my $t = Test::Mojo->new(
  Mojo::File::curfile->dirname->sibling('main.pl')
);

my $a = { add_name => q{Andy}, add_mac => '00:aa:11:BB:22:cc', add_ip => '127.0.0.1' };

subtest "Add host" => sub {
  $t->post_ok("/add", form => $a)->status_is(303);
};

## wake

subtest "/wake known mac" => sub {
  $t->ua->max_redirects(1);
  $t->get_ok("/wake", form => {mac => "00:AA:11:BB:22:CC"})
    ->status_is(200)
    ->content_like(qr/arisen='127.0.0.1'/);
};

subtest "/wake unknkown mac" => sub {
  $t->ua->max_redirects(1);
  $t->get_ok("/wake", form => {mac => "ff:ff:ff:ff:ff:ff"})
    ->status_is(200)
    ->content_like(qr/Unknown MAC address/);
};

subtest "/wake no mac" => sub {
  $t->ua->max_redirects(1);
  $t->get_ok("/wake")
    ->status_is(200)
    ->content_like(qr/Missing mac param/);
};

done_testing();
