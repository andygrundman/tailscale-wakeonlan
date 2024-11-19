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

subtest "GET /edit redirects" => sub {
  $t->get_ok("/edit?mac=bar")->status_is(302);
};

subtest "POST /edit with no mac displays error" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/edit", form => {})
    ->status_is(200)
    ->content_like(qr/Missing mac param/);
};

subtest "POST /edit with missing data shows errors" => sub {
  $t->ua->max_redirects(0);
  $t->post_ok("/edit", form => {mac => '00:aa:11:BB:22:cc', edit_name => q{}, edit_mac => q{}, edit_ip => q{}})
    ->status_is(200)
    ->element_exists('input[name="edit_name"].field-with-error')
    ->element_exists('input[name="edit_mac"].field-with-error')
    ->element_exists('input[name="edit_ip"].field-with-error')
    ->element_count_is('.field-with-error', 3);
};

subtest "POST /edit with invalid MAC & IP shows errors" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/edit", form => {mac => '00:aa:11:BB:22:cc', edit_name => q{Home-PC}, edit_mac => '00-11-22', edit_ip => '192.168.275.3'})
    ->status_is(200)
    ->element_exists('input[name="edit_mac"].field-with-error')
    ->element_exists('input[name="edit_ip"].field-with-error')
    ->element_count_is('.field-with-error', 2);
};

subtest "POST /edit with valid data displays updated row with entry" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/edit", form => {mac => '00:ff:22:cc:33:dd', edit_name => q{Home-PC}, edit_mac => '00:aa:11:BB:22:cc', edit_ip => '192.168.1.3'})
    ->status_is(200)
    ->element_count_is('.field-with-error', 0)
    ->text_is('button[id="asleep_192.168.1.3"]', 'asleep')
    ->content_like(qr/Home-PC/)
    ->content_unlike(qr/Two/) # old name is gone
    ->content_like(qr/00:aa:11:bb:22:cc/)
    ->content_unlike(qr/00:ff:22:cc:33:dd/); # old MAC is gone
};

done_testing();
