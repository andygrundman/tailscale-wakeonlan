use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

require(Mojo::File::curfile->sibling("lib/TestInit.pm"));

my $t = Test::Mojo->new(
  Mojo::File::curfile->dirname->sibling('main.pl')
);

my $a = { add_name => q{Andy}, add_mac => '00:aa:11:BB:22:cc', add_ip => '127.0.0.1' };
my $b = { add_name => q{Two},  add_mac => '00:ff:22:cc:33:dd', add_ip => '127.0.0.2' };

subtest "Add 2 hosts" => sub {
  $t->post_ok("/add", form => $a)->status_is(303);
  $t->post_ok("/add", form => $b)->status_is(303);
};

subtest "POST delete, 303 redirect" => sub {
  $t->ua->max_redirects(0);
  $t->post_ok("/delete", form => {mac => "00:ff:22:cc:33:dd"})
    ->status_is(303);
};

subtest "POST delete, follow redirect" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/delete", form => {mac => "00:aa:11:BB:22:cc"})
    ->status_is(200)
    ->content_unlike(qr/Andy/)
    ->content_unlike(qr/Two/);
};

subtest "POST delete, mac not found" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/delete", form => {mac => "00:aa:11:BB:22:cc"})
    ->status_is(200)
    ->content_like(qr/Host not found/);
};

done_testing();
