use Mojo::Base -strict;
use Test::More;
use Test::Mojo;

require(Mojo::File::curfile->sibling("lib/TestInit.pm"));

my $t = Test::Mojo->new(
  Mojo::File::curfile->dirname->sibling('main.pl')
);

subtest "GET /add redirects" => sub {
  $t->get_ok("/add?name=foo&mac=bar")->status_is(302);
};

subtest "POST /add with no data is ignored" => sub {
  $t->ua->max_redirects(0);
  $t->post_ok("/add", form => {})
    ->status_is(200)
    ->element_count_is('.field-with-error', 0);
};

subtest "POST /add with missing data shows errors" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/add", form => {add_name => q{}, add_mac => q{}})
    ->status_is(200)
    ->element_exists('input[name="add_name"].field-with-error')
    ->element_exists('input[name="add_mac"].field-with-error')
    ->element_exists('input[name="add_ip"].field-with-error')
    ->element_count_is('.field-with-error', 3);
};

subtest "POST /add with invalid MAC & IP shows errors" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/add", form => {add_name => q{Home-PC}, add_mac => '00-11-22', add_ip => '192.168.275.3'})
    ->status_is(200)
    ->element_exists('input[name="add_mac"].field-with-error')
    ->element_exists('input[name="add_ip"].field-with-error')
    ->element_count_is('.field-with-error', 2);
};

subtest "POST /add with valid data displays new row with entry, lowercased MAC" => sub {
  $t->ua->max_redirects(1);
  $t->post_ok("/add", form => {add_name => q{Home-PC}, add_mac => '00:aa:11:BB:22:cc', add_ip => '192.168.1.3'})
    ->status_is(200)
    ->element_count_is('.field-with-error', 0)
    ->text_is('button[id="asleep_192.168.1.3"]', 'asleep')
    ->content_like(qr/Home-PC/)
    ->content_like(qr/00:aa:11:bb:22:cc/);
};

done_testing();
